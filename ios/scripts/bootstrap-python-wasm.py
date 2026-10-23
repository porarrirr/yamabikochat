#!/usr/bin/env python3
"""Fetch the pinned, offline-only WebAssembly Python distribution.

The npm archive authenticates the upstream package lock; every wheel is then
checked against that lock. No package or interpreter is downloaded by the app.
"""
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

VERSION = "314.0.7"
INTEGRITY = "0YvXxEhfEdpLfb/XkM2BFAeMROq0iMUX2bzzH9pOttyMcWkwq+HbE5uyuGD82LN7y2q+SNvi/6V5JEsOlD2R1A=="
ROOT = Path(__file__).resolve().parents[1] / "Vendor" / "Pyodide"
CORE = ("pyodide.js", "pyodide.asm.mjs", "pyodide.asm.wasm", "python_stdlib.zip")


def cap_wasm_memory(content):
    # The pinned core exports one memory: minimum 480 pages, maximum 65536.
    # Lower its declared maximum to 8192 pages (512 MiB). Unlike a Python/JS
    # watchdog, the WebAssembly engine enforces this even for hostile code.
    def leb(position):
        result = shift = 0
        while True:
            byte = content[position]
            position += 1
            result |= (byte & 127) << shift
            if not byte & 128:
                return result, position
            shift += 7
    position = 8
    while position < len(content):
        section = content[position]
        size, start = leb(position + 1)
        end = start + size
        if section == 5:
            if content[start:end] != bytes.fromhex("0101e003808004"):
                raise SystemExit("Review Pyodide WebAssembly memory contract")
            payload = bytes.fromhex("0101e0038040")
            return content[:position] + bytes([5, len(payload)]) + payload + content[end:]
        position = end
    raise SystemExit("Pyodide memory declaration is missing")


def download(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def main():
    fonts = Path(__file__).resolve().parents[1] / "YamabikoChat" / "Python" / "Resources" / "Fonts"
    for line in (fonts / "SHA256SUMS").read_text().splitlines():
        expected, filename = line.split(None, 1)
        if hashlib.sha256((fonts / filename.strip()).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"Bundled font checksum mismatch: {filename}")
    ROOT.mkdir(parents=True, exist_ok=True)
    cache = ROOT.parent / "PyodideCache"
    cache.mkdir(parents=True, exist_ok=True)
    archive_path = cache / "distribution.tgz"
    previous = ROOT / "distribution.tgz"
    if previous.exists() and not archive_path.exists():
        previous.replace(archive_path)
    archive = archive_path.read_bytes() if archive_path.exists() else download(
        f"https://registry.npmjs.org/pyodide/-/pyodide-{VERSION}.tgz"
    )
    if base64.b64encode(hashlib.sha512(archive).digest()).decode() != INTEGRITY:
        raise SystemExit("Pyodide distribution checksum mismatch")
    archive_path.write_bytes(archive)
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        lock = json.load(tar.extractfile("package/pyodide-lock.json"))
        for name in CORE:
            content = tar.extractfile(f"package/{name}").read()
            (ROOT / name).write_bytes(cap_wasm_memory(content) if name.endswith(".wasm") else content)
    selected = {}

    def include(name):
        if name in selected:
            return
        package = lock["packages"][name]
        selected[name] = package
        for dependency in package["depends"]:
            include(dependency)

    for name in ("numpy", "matplotlib", "pillow"):
        include(name)
    for name, package in selected.items():
        filename = package["file_name"]
        destination = ROOT / filename
        content = destination.read_bytes() if destination.exists() else download(
            f"https://cdn.jsdelivr.net/pyodide/v{VERSION}/full/{filename}"
        )
        if hashlib.sha256(content).hexdigest() != package["sha256"]:
            raise SystemExit(f"Pyodide package checksum mismatch: {name}")
        destination.write_bytes(content)
    # Only these bundled packages can be resolved. No runtime CDN fallback.
    lock["packages"] = selected
    (ROOT / "pyodide-lock.json").write_text(json.dumps(lock, sort_keys=True))
    files = [*CORE, "pyodide-lock.json", *(p["file_name"] for p in selected.values())]
    manifest = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files}
    (ROOT / "manifest.json").write_text(json.dumps({"version": VERSION, "files": manifest}, sort_keys=True))
    print(f"Prepared offline WebAssembly Python {VERSION} with {len(selected)} scientific packages")


if __name__ == "__main__":
    main()
