#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
runtime_dir="$root_dir/ios/PiRuntime"
jni_dir="$root_dir/app/src/main/jniLibs"
assets_dir="$root_dir/app/src/main/assets/pi-runtime"
archive_url="https://github.com/gmaclennan/nodejs-mobile/releases/download/v24.18.0-0/nodejs-mobile-android-24.18.0-0.zip"
archive_sha256="ceb86b0b8130006195a60cd37393ebe0fd665b644ce8d5674dfba1da65d3be28"

if [[ ! -f "$jni_dir/arm64-v8a/libnode.so" || ! -f "$jni_dir/x86_64/libnode.so" ]]; then
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  echo "Downloading nodejs-mobile Android binaries..."
  python3 -c "
import urllib.request
url = '$archive_url'
dest = '$temp_dir/node-mobile-android.zip'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
with urllib.request.urlopen(req) as resp, open(dest, 'wb') as f:
    f.write(resp.read())
"
  actual_sha256="$(shasum -a 256 "$temp_dir/node-mobile-android.zip" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$archive_sha256" ]]; then
    echo "NodeMobile Android archive checksum mismatch" >&2
    exit 1
  fi
  python3 -c "
import zipfile, os, shutil
zip_path = '$temp_dir/node-mobile-android.zip'
with zipfile.ZipFile(zip_path) as z:
    for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
        target_dir = os.path.join('$jni_dir', abi)
        os.makedirs(target_dir, exist_ok=True)
        with z.open(f'bin/{abi}/libnode.so') as src, open(os.path.join(target_dir, 'libnode.so'), 'wb') as dst:
            shutil.copyfileobj(src, dst)
"
fi

if [[ -d "$runtime_dir" ]]; then
  if [[ ! -f "$runtime_dir/bundle/main.js" ]]; then
    (cd "$runtime_dir" && npm ci && npm run build)
  fi
  mkdir -p "$assets_dir"
  cp "$runtime_dir/bundle/main.js" "$assets_dir/main.js"
fi

echo "Prepared NodeMobile Android 24.18.0-0 and Pi Agent runtime bundle"
