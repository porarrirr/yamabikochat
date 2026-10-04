#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
runtime_dir="$root_dir/ios/PiRuntime"
jni_dir="$root_dir/app/src/main/jniLibs"
assets_dir="$root_dir/app/src/main/assets/pi-runtime"
archive_url="https://github.com/gmaclennan/nodejs-mobile/releases/download/v24.18.0-0/nodejs-mobile-android-24.18.0-0.zip"
archive_sha256="ceb86b0b8130006195a60cd37393ebe0fd665b644ce8d5674dfba1da65d3be28"

if [[ ! -f "$jni_dir/arm64-v8a/libnode.so" || ! -f "$jni_dir/armeabi-v7a/libnode.so" || ! -f "$jni_dir/x86_64/libnode.so" ]]; then
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

# The NodeMobile archive ships libnode.so but not its shared C++ dependency.
# Restore the official NDK r27 runtime from an immutable Google source revision.
python3 - "$jni_dir" <<'PY'
import base64
import hashlib
import pathlib
import sys
import urllib.request

root = pathlib.Path(sys.argv[1])
revision = "77eba0d553f8f58557f99fa98f327eb5f46e0c8c"
base = f"https://android.googlesource.com/toolchain/prebuilts/ndk/r27/+/{revision}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib"
libraries = [
    ("arm64-v8a", "aarch64-linux-android", "46b51d661454b9cfaf42c1dc90893b5ad601b7a7ffc2e09d44bb3cc9d20e7ae2"),
    ("armeabi-v7a", "arm-linux-androideabi", "0ce8906c20a019f56d2cefbadeac35cca102234971d2c8a1e09c69ee099f957a"),
    ("x86_64", "x86_64-linux-android", "936e1150309bdae86216f14e493f478d39e588095f1577105856da6d0f24f149"),
]
for abi, triple, checksum in libraries:
    target = root / abi / "libc++_shared.so"
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == checksum:
        continue
    print(f"Restoring Android C++ runtime for {abi}...", flush=True)
    with urllib.request.urlopen(f"{base}/{triple}/libc%2B%2B_shared.so?format=TEXT", timeout=60) as response:
        data = base64.b64decode(response.read(), validate=True)
    if hashlib.sha256(data).hexdigest() != checksum:
        raise SystemExit(f"Android C++ runtime checksum mismatch for {abi}")
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".so.tmp")
    temporary.write_bytes(data)
    temporary.replace(target)
PY

mkdir -p "$assets_dir"
(cd "$runtime_dir" && npm ci && npm run build)
pi_version="$(cd "$runtime_dir" && node -p "require('./node_modules/@earendil-works/pi-ai/package.json').version")"

echo "Prepared NodeMobile Android 24.18.0-0 and Pi $pi_version runtime"
