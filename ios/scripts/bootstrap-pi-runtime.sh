#!/usr/bin/env bash
set -euo pipefail

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
runtime_dir="$ios_dir/PiRuntime"
vendor_dir="$ios_dir/Vendor"
framework="$vendor_dir/NodeMobile.xcframework"
archive_url="https://github.com/gmaclennan/nodejs-mobile/releases/download/v24.18.0-0/nodejs-mobile-ios-24.18.0-0.zip"
archive_sha256="849526f5861a235e97d4ecc7a3272f1d6bb63d324716dbe1cc2bb5019992257a"

if [[ ! -d "$framework" ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  curl --fail --location --retry 3 "$archive_url" --output "$temp_dir/node-mobile.zip"
  actual_sha256="$(shasum -a 256 "$temp_dir/node-mobile.zip" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$archive_sha256" ]]; then
    echo "NodeMobile archive checksum mismatch" >&2
    exit 1
  fi
  unzip -q "$temp_dir/node-mobile.zip" -d "$temp_dir/unpacked"
  mkdir -p "$vendor_dir"
  cp -R "$temp_dir/unpacked/NodeMobile.xcframework" "$framework"
fi

cd "$runtime_dir"
npm ci
npm run build

echo "Prepared NodeMobile 24.18.0-0 and Pi 0.84.2 runtime"
