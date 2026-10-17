#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
for cache_mode in strict reuse; do
python3 - "$script_directory" "$cache_mode" <<'PY'
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from unittest.mock import patch

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
    if sys.argv[2] == "reuse":
        arguments += ["--reuse-file-digests"]

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
    product_stat = product.stat()
    product.write_text("corrupt")
    os.utime(product, ns=(product_stat.st_atime_ns, product_stat.st_mtime_ns))
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

    fingerprint = runpy.run_path(str(cache))["fingerprint"]
    files = {}
    expected = fingerprint([source], current_files=files)
    # A warm check must avoid opening unchanged file contents.
    with patch.object(Path, "open", side_effect=AssertionError("Unexpected content read")):
        assert fingerprint([source], previous_files=files) == expected
    # Strict checks always read contents, even with a warm metadata cache.
    with patch.object(Path, "open", side_effect=AssertionError("Strict content read")):
        try:
            fingerprint([source])
        except AssertionError:
            pass
        else:
            raise AssertionError("Strict check reused file metadata")
print("Build cache invalidation tests passed")
PY
done
