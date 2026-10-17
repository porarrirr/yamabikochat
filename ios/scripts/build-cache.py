#!/usr/bin/env python3
"""Content-based cache for build preparation, including output integrity checks."""

import argparse
import hashlib
import json
import os
from pathlib import Path


def fingerprint(paths, previous_files=None, current_files=None):
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
                stat = entry.stat()
                digest.update(b"file\0" + str(stat.st_mode).encode())
                # ctime detects edits even when size and mtime are restored.
                # Inode/device also invalidate replacements and copied caches.
                identity = [stat.st_dev, stat.st_ino, stat.st_size, stat.st_mode,
                            stat.st_mtime_ns, stat.st_ctime_ns]
                cached = (previous_files or {}).get(str(entry), {})
                if cached.get("identity") == identity:
                    content_hash = cached["sha256"]
                else:
                    content = hashlib.sha256()
                    with entry.open("rb") as source:
                        for chunk in iter(lambda: source.read(1024 * 1024), b""):
                            content.update(chunk)
                    content_hash = content.hexdigest()
                digest.update(content_hash.encode())
                if current_files is not None:
                    current_files[str(entry)] = {"identity": identity, "sha256": content_hash}
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
    parser.add_argument("--reuse-file-digests", action="store_true",
                        help="Reuse digests of files with unchanged local filesystem metadata")
    args = parser.parse_args()
    # A missing input or product must never be accepted as a valid cache entry.
    if not args.output or not all(Path(p).exists() for p in args.input + args.output):
        return 1
    try:
        previous = json.loads(args.stamp.read_text())
        if not isinstance(previous, dict):
            previous = {}
    except (OSError, ValueError):
        previous = {}
    previous_files = previous.get("files", {}) if args.reuse_file_digests else {}
    # Malformed metadata must cause a rehash, never a failed build or false hit.
    if not isinstance(previous_files, dict):
        previous_files = {}
    previous_files = {
        path: item for path, item in previous_files.items()
        if isinstance(item, dict) and isinstance(item.get("identity"), list)
        and isinstance(item.get("sha256"), str) and len(item["sha256"]) == 64
    }
    current_files = {} if args.reuse_file_digests else None
    state = {
        "version": 2,
        "inputs": fingerprint(args.input, previous_files, current_files),
        "outputs": fingerprint(args.output, previous_files, current_files),
        "values": args.value,
    }
    if args.action == "check":
        return 0 if all(previous.get(key) == value for key, value in state.items()) else 1
    if current_files is not None:
        state["files"] = current_files
    args.stamp.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.stamp.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(state, sort_keys=True))
    temporary.replace(args.stamp)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
