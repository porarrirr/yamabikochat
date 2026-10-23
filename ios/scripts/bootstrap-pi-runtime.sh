#!/usr/bin/env bash
set -euo pipefail

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
runtime_dir="$ios_dir/PiRuntime"
vendor_dir="$ios_dir/Vendor"
"$ios_dir/scripts/bootstrap-node-mobile.sh"

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
  --output bundle/PiAssets
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
echo "Prepared verified NodeMobile and Pi $pi_version runtime"
