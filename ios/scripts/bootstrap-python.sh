#!/usr/bin/env bash
set -euo pipefail
# Compatibility entry point. Native in-process CPython is retired.
if [[ $# -gt 0 && "${1:-}" != "--runtime-only" ]]; then
  echo "Usage: $0 [--runtime-only]" >&2
  exit 2
fi
exec python3 "$(dirname "$0")/bootstrap-python-wasm.py"
