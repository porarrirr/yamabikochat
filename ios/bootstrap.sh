#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
scripts/bootstrap-pi-runtime.sh
python3 scripts/bootstrap-python-wasm.py
xcodegen generate

echo "Generated YamabikoChat.xcodeproj"
