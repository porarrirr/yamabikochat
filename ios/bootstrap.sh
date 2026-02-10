#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f ".env.local" ]; then
  set -a
  # shellcheck disable=SC1091
  . ".env.local"
  set +a
fi

xcodegen generate

echo "Generated YamabikoChat.xcodeproj"
