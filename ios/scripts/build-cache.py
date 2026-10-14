#!/usr/bin/env python3
"""Content-based cache for build preparation, including output integrity checks."""

import argparse
import hashlib
import json
import os
from pathlib import Path


def fingerprint(paths):
    digest = hashlib.sha256()
    for root in sorted({str(Path(path).resolve()) for path in paths}):
        path = Path(root)
        entries = [path]
        if path.is_dir() and not path.is_symlink():
            entries += sorted(path.rglob("*"))
        for entry in entries:
            digest.update(str(entry).encode() + b"\0")
            if entry.is_symlink():
                digest.update(b"link\0" + os.readlink(entry).encode())
            elif entry.is_file():
                digest.update(b"file\0" + str(entry.stat().st_mode).encode())
                with entry.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        digest.update(chunk)
            elif entry.is_dir():
                digest.update(b"directory\0")
            else:
                digest.update(b"missing\0")
            digest.update(b"\0")
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "save"])
    parser.add_argument("stamp", type=Path)
    parser.add_argument("--input", action="append", default=[])
    parser.add_argument("--output", action="append", default=[])
    parser.add_argument("--value", action="append", default=[])
    args = parser.parse_args()
    # A missing input or product must never be accepted as a valid cache entry.
    if not args.output or not all(Path(p).exists() for p in args.input + args.output):
        return 1
    state = {
        "version": 1,
        "inputs": fingerprint(args.input),
        "outputs": fingerprint(args.output),
        "values": args.value,
    }
    if args.action == "check":
        try:
            return 0 if json.loads(args.stamp.read_text()) == state else 1
        except (OSError, ValueError):
            return 1
    args.stamp.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.stamp.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state, sort_keys=True))
    temporary.replace(args.stamp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
