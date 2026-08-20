#!/usr/bin/env bash
set -euo pipefail

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="$ios_dir/Vendor"
framework="$vendor_dir/Python.xcframework"
site_root="$vendor_dir/PythonSitePackages"
wheelhouse="$vendor_dir/PythonWheelhouse"
wheel_lock="$ios_dir/python-wheels.sha256"
support_url="https://github.com/beeware/Python-Apple-support/releases/download/3.14-b10/Python-3.14-iOS-support.b10.tar.gz"
support_sha256="200ef60eb67be0483ceb638daa9048f84f41a9a952707a5ad4c3198037c7b583"
runtime_only=false

if [[ "${1:-}" == "--runtime-only" ]]; then
  runtime_only=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--runtime-only]" >&2
  exit 2
fi

mkdir -p "$vendor_dir"
if [[ ! -d "$framework" ]]; then
  temp_dir="$(mktemp -d)"
  curl --fail --location --retry 3 "$support_url" --output "$temp_dir/python-support.tar.gz"
  actual_sha256="$(shasum -a 256 "$temp_dir/python-support.tar.gz" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$support_sha256" ]]; then
    echo "Python support archive checksum mismatch" >&2
    exit 1
  fi
  tar -xzf "$temp_dir/python-support.tar.gz" -C "$temp_dir"
  cp -R "$temp_dir/Python.xcframework" "$framework"
fi

mkdir -p "$site_root/iphoneos-arm64" "$site_root/iphonesimulator-arm64" "$site_root/iphonesimulator-x86_64"

if [[ "$runtime_only" == true ]]; then
  echo "Prepared CPython 3.14-b10 runtime without optional scientific wheels"
  exit 0
fi

mkdir -p "$wheelhouse"

download_wheel() {
  local filename="$1"
  local url="$2"
  local expected_sha256="$3"
  local destination="$wheelhouse/$filename"
  if [[ ! -f "$destination" ]]; then
    curl --fail --location --retry 3 "$url" --output "$destination"
  fi
  local actual_sha256
  actual_sha256="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Wheel checksum mismatch: $filename" >&2
    exit 1
  fi
}

download_wheel \
  "pillow-12.3.0-cp314-cp314-ios_13_0_arm64_iphoneos.whl" \
  "https://files.pythonhosted.org/packages/dc/01/001f65b68192f0228cc1dbbc8d2530ab5d58b61037ba0587f946fea607cd/pillow-12.3.0-cp314-cp314-ios_13_0_arm64_iphoneos.whl" \
  "9cf95fe4d0f84c82d282745d9bb08ad9f926efa00be4697e767b814ce40d4330"
download_wheel \
  "pillow-12.3.0-cp314-cp314-ios_13_0_arm64_iphonesimulator.whl" \
  "https://files.pythonhosted.org/packages/1a/d2/0219746d0fd16fc8a84498e79452375be3797d3ce4044596ce565164b84f/pillow-12.3.0-cp314-cp314-ios_13_0_arm64_iphonesimulator.whl" \
  "8728f216dcdb6e6d555cf971cb34076139ad74b31fc2c14da4fafc741c5f6217"
download_wheel \
  "pillow-12.3.0-cp314-cp314-ios_13_0_x86_64_iphonesimulator.whl" \
  "https://files.pythonhosted.org/packages/c8/02/8d0bc62ef0302318c46ff2a512822d2610e81c7aa46c9b3abe6cbaca5ad0/pillow-12.3.0-cp314-cp314-ios_13_0_x86_64_iphonesimulator.whl" \
  "a45650e8ce7fafffd731db8550230db6b0d306d181a90b67d3e6bca2f1990930"

for package in numpy pandas matplotlib; do
  for platform_tag in arm64_iphoneos arm64_iphonesimulator x86_64_iphonesimulator; do
    if ! compgen -G "$wheelhouse/${package}-*-cp314-cp314-ios_13_0_${platform_tag}.whl" >/dev/null; then
      echo "Missing verified CPython 3.14 iOS wheel: $package ($platform_tag)" >&2
      echo "Place an upstream-built or separately audited wheel in $wheelhouse; protocol or platform substitution is not allowed." >&2
      exit 1
    fi
  done
done

verify_locked_wheel() {
  local wheel="$1"
  local filename
  local expected_sha256
  local actual_sha256
  filename="$(basename "$wheel")"
  expected_sha256="$(awk -v filename="$filename" '$2 == filename { print $1 }' "$wheel_lock")"
  if [[ -z "$expected_sha256" ]]; then
    echo "Wheel is not pinned in $wheel_lock: $filename" >&2
    exit 1
  fi
  actual_sha256="$(shasum -a 256 "$wheel" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Locked wheel checksum mismatch: $filename" >&2
    exit 1
  fi
}

if [[ ! -f "$wheel_lock" ]]; then
  echo "Missing wheel checksum lock: $wheel_lock" >&2
  exit 1
fi
for wheel in "$wheelhouse"/*.whl; do
  verify_locked_wheel "$wheel"
done

for target in iphoneos-arm64 iphonesimulator-arm64 iphonesimulator-x86_64; do
  destination="$site_root/$target"
  find "$destination" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  for wheel in "$wheelhouse"/*.whl; do
    filename="$(basename "$wheel")"
    include=false
    case "$target:$filename" in
      iphoneos-arm64:*arm64_iphoneos.whl) include=true ;;
      iphonesimulator-arm64:*arm64_iphonesimulator.whl) include=true ;;
      iphonesimulator-x86_64:*x86_64_iphonesimulator.whl) include=true ;;
      *:*none-any.whl) include=true ;;
    esac
    if [[ "$include" == true ]]; then
      unzip -oq "$wheel" -d "$destination"
    fi
  done
done

echo "Prepared CPython 3.14-b10 with verified numpy, pandas, matplotlib, and Pillow wheel inputs"
