#!/usr/bin/env bash
set -euo pipefail

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="$ios_dir/Vendor"
framework="$vendor_dir/NodeMobile.xcframework"
cache_tool="$ios_dir/scripts/build-cache.py"
release="$ios_dir/node-mobile-release.json"
license="$ios_dir/../third_party/nodejs-mobile/LICENSE"
stamp="$vendor_dir/node-mobile-cache.json"
read -r node_version archive_url archive_sha256 < <(python3 - "$release" <<'PY'
import json, re, sys
with open(sys.argv[1]) as source:
    release = json.load(source)
assert re.fullmatch(r"24\.\d+\.\d+", release["nodeVersion"])
assert release["archiveURL"].startswith("https://github.com/porarrirr/nodejs-mobile/releases/download/")
assert re.fullmatch(r"[a-f0-9]{64}", release["archiveSHA256"])
print(release["nodeVersion"], release["archiveURL"], release["archiveSHA256"])
PY
)
cache_arguments=(
  --input "$ios_dir/scripts/bootstrap-node-mobile.sh"
  --input "$cache_tool"
  --input "$release"
  --input "$license"
  --output "$framework"
)

# Directory existence alone must never accept an older or modified runtime.
if python3 "$cache_tool" check "$stamp" "${cache_arguments[@]}"; then
  echo "Reusing verified NodeMobile $node_version"
  exit 0
fi

mkdir -p "$vendor_dir"
rm -f "$stamp"
work_dir="$(mktemp -d "$vendor_dir/.node-mobile.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
curl --fail --location --retry 3 "$archive_url" --output "$work_dir/node-mobile.zip"
actual_sha256="$(shasum -a 256 "$work_dir/node-mobile.zip" | awk '{print $1}')"
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
  echo "NodeMobile archive checksum mismatch" >&2
  exit 1
fi
unzip -q "$work_dir/node-mobile.zip" -d "$work_dir/unpacked"
product="$work_dir/unpacked/NodeMobile.xcframework"
for slice in ios-arm64 ios-arm64-simulator; do
  binary="$product/$slice/NodeMobile.framework/NodeMobile"
  # Check both slices before replacing the installed runtime. The content cache
  # then detects later edits to every framework file, including the binaries.
  strings "$binary" > "$work_dir/versions.txt"
  if ! grep -Fx "v$node_version" "$work_dir/versions.txt" >/dev/null; then
    echo "NodeMobile $slice does not contain Node.js $node_version" >&2
    exit 1
  fi
done
# Ensure the legal notice packaged by Xcode matches this exact release.
cmp "$work_dir/unpacked/LICENSE" "$license"
# Keep the previous framework until download and validation both succeed.
rm -rf "$framework"
mv "$product" "$framework"
python3 "$cache_tool" save "$stamp" "${cache_arguments[@]}"
echo "Prepared verified NodeMobile $node_version"
