#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
scripts/bootstrap-pi-runtime.sh
scripts/bootstrap-python.sh
xcodegen generate

echo "Generated YamabikoChat.xcodeproj"
