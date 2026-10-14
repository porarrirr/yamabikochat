#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
python3 - "$script_directory" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cache = Path(sys.argv[1]) / "build-cache.py"
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / "source"
    output = root / "output"
    source.mkdir()
    output.mkdir()
    module = source / "module"
    module.write_text("original")
    product = output / "binary"
    product.write_text("product")
    stamp = root / "stamp.json"
    arguments = [str(stamp), "--input", str(source), "--output", str(output), "--value", "sdk=27"]

    def run(action, extra=()):
        return subprocess.run([sys.executable, str(cache), action, *arguments, *extra], check=False).returncode

    assert run("check") == 1
    assert run("save") == 0
    assert run("check") == 0
    relative_arguments = [str(stamp), "--input", "source", "--output", "output", "--value", "sdk=27"]
    assert subprocess.run(
        [sys.executable, str(cache), "check", *relative_arguments], cwd=root, check=False
    ).returncode == 0
    assert run("check", ["--value", "identity=changed"]) == 1
    original_stat = module.stat()
    module.write_text("modified")  # Same size and mtime must still invalidate.
    os.utime(module, ns=(original_stat.st_atime_ns, original_stat.st_mtime_ns))
    assert run("check") == 1
    assert run("save") == 0
    product.write_text("corrupt")
    assert run("check") == 1
    assert run("save") == 0
    product.unlink()
    assert run("check") == 1
    assert run("save") == 0
    module.unlink()
    assert run("check") == 1
    module.write_text("restored")
    product.write_text("restored")
    assert run("save") == 0
    (source / "extra").write_text("new input")
    assert run("check") == 1
    (source / "extra").unlink()
    (source / "link").symlink_to("module")
    assert run("save") == 0
    (source / "link").unlink()
    (source / "link").symlink_to("extra")
    assert run("check") == 1
    stamp.write_text("interrupted JSON")
    assert run("check") == 1
    assert run("save") == 0
    product.chmod(0o755)
    assert run("check") == 1
    arguments += ["--input", str(root / "missing")]
    assert run("save") == 1
print("Build cache invalidation tests passed")
PY
