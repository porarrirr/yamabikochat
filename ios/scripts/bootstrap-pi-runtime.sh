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
cache_tool="$ios_dir/scripts/build-cache.py"
install_stamp="$vendor_dir/pi-npm-cache.json"
install_arguments=(
  --input package.json
  --input package-lock.json
  --input scripts
  --input "$ios_dir/scripts/bootstrap-pi-runtime.sh"
  --input "$cache_tool"
  --output node_modules
  --value "$(node --version)"
  --value "$(npm --version)"
  --value "$(uname -sm)"
  --value "NODE_ENV=${NODE_ENV:-}"
  --value "npm_config_omit=${npm_config_omit:-}"
  --value "npm_config_ignore_scripts=${npm_config_ignore_scripts:-}"
)
if python3 "$cache_tool" check "$install_stamp" "${install_arguments[@]}"; then
  echo "Reusing verified Pi npm dependencies"
else
  rm -f "$install_stamp"
  npm ci
  python3 "$cache_tool" save "$install_stamp" "${install_arguments[@]}"
fi

build_stamp="$vendor_dir/pi-bundle-cache.json"
build_arguments=(
  --input package.json
  --input package-lock.json
  --input src
  --input scripts
  --input node_modules
  --input "$cache_tool"
  --output bundle/main.js
  --output "$ios_dir/../app/src/main/assets/pi-runtime/main.js"
  --value "$(node --version)"
)
if python3 "$cache_tool" check "$build_stamp" "${build_arguments[@]}"; then
  echo "Reusing verified Pi runtime bundle"
else
  rm -f "$build_stamp"
  npm run build
  python3 "$cache_tool" save "$build_stamp" "${build_arguments[@]}"
fi

pi_version="$(node -p "require('./node_modules/@earendil-works/pi-ai/package.json').version")"
echo "Prepared NodeMobile 24.18.0-0 and Pi $pi_version runtime"
