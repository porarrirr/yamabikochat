#!/usr/bin/env python3
"""Run identical simulator workloads against saved build products; retain raw evidence."""
import argparse
import json
import pathlib
import plistlib
import re
import signal
import statistics
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", required=True, type=pathlib.Path)
    parser.add_argument("--device", required=True, help="Dedicated simulator UDID; uses light appearance and medium text")
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--kind", choices=["render", "ui"], default="render")
    parser.add_argument("--reset-app-data", action="store_true",
                        help="Uninstall the benchmark app first; use only a disposable simulator")
    parser.add_argument("--trace", choices=["cpu", "metal"], help="Diagnostic run only; do not use these timings for the before/after comparison")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    with (args.output / "setup.log").open("w") as setup:
        subprocess.run(["xcrun", "simctl", "bootstatus", args.device, "-b"], check=True, timeout=180, stdout=setup, stderr=subprocess.STDOUT)
        for setting, value in [("appearance", "light"), ("content_size", "medium")]:
            subprocess.run(["xcrun", "simctl", "ui", args.device, setting, value], check=True, timeout=30, stdout=setup, stderr=subprocess.STDOUT)
        if args.reset_app_data:
            installed = subprocess.run(["xcrun", "simctl", "get_app_container", args.device,
                                        "com.porarri.yamabikochat.ios", "app"], capture_output=True, text=True, timeout=30)
            if installed.returncode == 0:
                subprocess.run(["xcrun", "simctl", "uninstall", args.device, "com.porarri.yamabikochat.ios"],
                               check=True, timeout=30, stdout=setup, stderr=subprocess.STDOUT)
            elif installed.returncode != 2 or "No such file or directory" not in installed.stderr:
                raise RuntimeError("Could not verify a clean simulator app container: " + installed.stderr)
    original = next(args.products.glob("YamabikoChat_*.xctestrun"))
    config = plistlib.loads(original.read_bytes())
    targets = [target for entry in config.get("TestConfigurations", []) for target in entry["TestTargets"]]
    if not targets:  # XcodeGen also emits the original xctestrun format.
        targets = [target for name, target in config.items() if not name.startswith("__")]
    for target in targets:
        target.setdefault("EnvironmentVariables", {})["YAMABIKO_RENDER_BENCHMARK"] = "1"
        target.setdefault("CommandLineArguments", []).extend(["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"])
    runfile = args.products / "RenderingBenchmark.xctestrun"
    runfile.write_bytes(plistlib.dumps(config))
    test = "YamabikoTests/ChatRenderingPerformanceTests" if args.kind == "render" else "YamabikoUITests/AppInteractionPerformanceTests"
    command = ["xcodebuild", "-xctestrun", str(runfile), "-destination", "platform=iOS Simulator,id=" + args.device,
               "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never", "-only-testing:" + test,
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "240",
               "-maximum-test-execution-time-allowance", "360",
               "-resultBundlePath", str(args.output / "result.xcresult"), "test-without-building"]
    (args.output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    trace = None
    trace_status = None
    try:
        prior_pids = set(subprocess.run(["pgrep", "-x", "YamabikoChat"], capture_output=True, text=True).stdout.split()) if args.trace else set()
        with (args.output / "test.log").open("w") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            if args.trace:
                deadline = time.monotonic() + 120
                while process.poll() is None and time.monotonic() < deadline:
                    # XCTest can launch a short-lived discovery host before the
                    # real run. Attach after the first completed rendering input.
                    if args.kind == "render" and "RENDER_BENCHMARK" not in (args.output / "test.log").read_text():
                        time.sleep(0.5)
                        continue
                    pids = subprocess.run(["pgrep", "-x", "YamabikoChat"], capture_output=True, text=True).stdout.split()
                    for pid in pids:
                        if pid in prior_pids:
                            continue
                        executable = subprocess.run(["ps", "-p", pid, "-o", "comm="], capture_output=True, text=True).stdout
                        if "/devices/" + args.device.lower() + "/" not in executable.lower():
                            continue
                        template = "Time Profiler" if args.trace == "cpu" else "Metal System Trace"
                        trace_command = ["xcrun", "xctrace", "record", "--template", template, "--attach", pid,
                                         "--device", args.device,
                                         "--time-limit", "25s", "--output", str(args.output / (args.trace + ".trace")), "--no-prompt"]
                        with (args.output / "trace.log").open("w") as trace_log:
                            trace = subprocess.Popen(trace_command, stdout=trace_log, stderr=subprocess.STDOUT)
                        trace_status = {"pid": int(pid), "command": trace_command}
                        break
                    if trace is not None:
                        break
                    time.sleep(0.5)
                if trace is None:
                    trace_status = {"error": "Simulator app was not found within 120 seconds"}
            exit_code = process.wait(timeout=480)
            if trace is not None:
                try:
                    trace_status["exit_code"] = trace.wait(timeout=90)
                except subprocess.TimeoutExpired:
                    trace.send_signal(signal.SIGINT)
                    try:
                        trace.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        trace.kill()
                        trace.wait()
                    trace_status["error"] = "Trace did not complete; recording was stopped"
    except subprocess.TimeoutExpired:
        process.terminate()
        exit_code = 124
        if trace is not None:
            trace.terminate()
    finally:
        runfile.unlink(missing_ok=True)
    text = (args.output / "test.log").read_text()
    samples = [json.loads(value) for value in re.findall(r"RENDER_BENCHMARK (\{[^\n]+\})", text)]
    medians = {name: statistics.median(s["cpu_seconds"] for s in samples if s["workload"] == name)
               for name in sorted({s["workload"] for s in samples})}
    report = {"exit_code": exit_code, "device": args.device, "products": str(args.products),
              "locale": "ja_JP", "languages": ["ja"],
              "appearance": "light", "content_size": "medium",
              "reset_app_data": args.reset_app_data,
              "profiled": args.trace is not None, "trace": trace_status,
              "samples": samples, "median_cpu_seconds": medians}
    if exit_code == 0 and args.kind == "ui":
        exported = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "metrics",
                                   "--path", str(args.output / "result.xcresult")],
                                  capture_output=True, text=True, timeout=60, check=True)
        report["xctest_metrics"] = json.loads(exported.stdout)
    (args.output / "metrics.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False), flush=True)
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
