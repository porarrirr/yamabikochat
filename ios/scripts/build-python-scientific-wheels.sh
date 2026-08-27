#!/usr/bin/env bash
set -euo pipefail

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="$ios_dir/Vendor"
framework="$vendor_dir/Python.xcframework"
wheelhouse="$vendor_dir/PythonWheelhouse"
build_environment="$vendor_dir/PythonWheelBuild"
source_lock="$ios_dir/python-scientific-sources.env"
generated_lock="$wheelhouse/source-built.sha256"
generated_sdk_lock="$wheelhouse/source-built.sdk"
active_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"

# Native extension load commands preserve the SDK used here. Reject an SDK
# that App Store Connect does not accept before it can enter the wheel cache.
"$ios_dir/scripts/validate-active-app-store-sdk.sh"

if [[ ! -d "$framework" ]]; then
  echo "Missing $framework; run ios/scripts/bootstrap-python.sh --runtime-only first." >&2
  exit 1
fi
if [[ ! -f "$source_lock" ]]; then
  echo "Missing scientific source lock: $source_lock" >&2
  exit 1
fi

# shellcheck source=../python-scientific-sources.env
source "$source_lock"

host_python="${YAMABIKO_BUILD_PYTHON:-$(command -v python3.14 || true)}"
if [[ -z "$host_python" ]]; then
  echo "A native CPython 3.14 executable is required to cross-build iOS wheels." >&2
  exit 1
fi
if [[ "$($host_python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" != "3.14" ]]; then
  echo "YAMABIKO_BUILD_PYTHON must point to native CPython 3.14: $host_python" >&2
  exit 1
fi

mkdir -p "$wheelhouse"

architectures=(
  arm64_iphoneos
  arm64_iphonesimulator
  x86_64_iphonesimulator
)

expected_wheels=()
for architecture in "${architectures[@]}"; do
  expected_wheels+=(
    "numpy-2.6.0.dev0-cp314-cp314-ios_17_0_${architecture}.whl"
    "matplotlib-${matplotlib_version}-cp314-cp314-ios_17_0_${architecture}.whl"
    "contourpy-${contourpy_version}-cp314-cp314-ios_17_0_${architecture}.whl"
    "kiwisolver-${kiwisolver_version}-cp314-cp314-ios_13_0_${architecture}.whl"
  )
done

generated_wheels_are_valid() {
  [[ -f "$generated_lock" ]] || return 1
  [[ -f "$generated_sdk_lock" ]] || return 1
  [[ "$(<"$generated_sdk_lock")" == "$active_sdk_version" ]] || return 1
  for filename in "${expected_wheels[@]}"; do
    local wheel="$wheelhouse/$filename"
    local expected_sha256
    [[ -f "$wheel" ]] || return 1
    expected_sha256="$(awk -v filename="$filename" '$2 == filename { print $1 }' "$generated_lock")"
    [[ -n "$expected_sha256" ]] || return 1
    [[ "$(shasum -a 256 "$wheel" | awk '{print $1}')" == "$expected_sha256" ]] || return 1
  done
}

if generated_wheels_are_valid; then
  echo "Verified cached CPython 3.14 iOS scientific wheels built with SDK $active_sdk_version"
  exit 0
fi

# Generated native wheels are toolchain artifacts. Rebuild the exact expected
# set whenever the active iOS SDK changes instead of mixing cached Mach-O files
# from a different Xcode installation into the app bundle.
for filename in "${expected_wheels[@]}"; do
  rm -f "$wheelhouse/$filename"
done
rm -f "$generated_lock" "$generated_sdk_lock"

if [[ ! -x "$build_environment/bin/python" ]]; then
  "$host_python" -m venv "$build_environment"
fi
"$build_environment/bin/python" -m pip install --disable-pip-version-check --upgrade \
  "cibuildwheel==$cibuildwheel_version" \
  "ninja==$ninja_version"

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

download_source() {
  local name="$1"
  local url="$2"
  local expected_sha256="$3"
  local archive="$temp_dir/$name.tar.gz"
  curl --fail --location --retry 3 "$url" --output "$archive"
  local actual_sha256
  actual_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Source checksum mismatch: $name" >&2
    exit 1
  fi
  tar -xzf "$archive" -C "$temp_dir"
}

git clone --quiet --filter=blob:none --no-checkout "$numpy_repository" "$temp_dir/numpy"
git -C "$temp_dir/numpy" fetch --quiet --depth=1 origin "$numpy_commit"
git -C "$temp_dir/numpy" checkout --quiet --detach FETCH_HEAD
if [[ "$(git -C "$temp_dir/numpy" rev-parse HEAD)" != "$numpy_commit" ]]; then
  echo "NumPy source commit mismatch" >&2
  exit 1
fi
git -C "$temp_dir/numpy" submodule update --init --depth=1 \
  numpy/_core/src/common/pythoncapi-compat \
  numpy/_core/src/highway \
  numpy/_core/src/npysort/x86-simd-sort \
  numpy/_core/src/umath/svml \
  numpy/fft/pocketfft \
  vendored-meson/meson

download_source "matplotlib-$matplotlib_version" "$matplotlib_source_url" "$matplotlib_source_sha256"
download_source "contourpy-$contourpy_version" "$contourpy_source_url" "$contourpy_source_sha256"
download_source "kiwisolver-$kiwisolver_version" "$kiwisolver_source_url" "$kiwisolver_source_sha256"

run_cibuildwheel() {
  local package_dir="$1"
  local architecture="$2"
  local config_settings="$3"
  local xbuild_tools="$4"
  local deployment_target="$5"
  local identifier="cp314-ios_${architecture}"

  CIBW_BUILD="$identifier" \
  CIBW_ARCHS_IOS="$architecture" \
  CIBW_BEFORE_BUILD_IOS="" \
  CIBW_BEFORE_TEST_IOS="" \
  CIBW_TEST_COMMAND_IOS="" \
  CIBW_TEST_REQUIRES_IOS="" \
  CIBW_CONFIG_SETTINGS_IOS="$config_settings" \
  CIBW_XBUILD_TOOLS_IOS="$xbuild_tools" \
  CIBW_ENVIRONMENT_IOS="IPHONEOS_DEPLOYMENT_TARGET=$deployment_target" \
  PATH="$build_environment/bin:$PATH" \
  YAMABIKO_BUILD_PYTHON="$build_environment/bin/python" \
  YAMABIKO_TARGET_ROOT="$vendor_dir" \
    "$build_environment/bin/python" "$ios_dir/scripts/run-ios-cibuildwheel.py" \
      --platform ios \
      --output-dir "$wheelhouse" \
      "$package_dir"
}

for architecture in "${architectures[@]}"; do
  numpy_wheel="numpy-2.6.0.dev0-cp314-cp314-ios_17_0_${architecture}.whl"
  if [[ ! -f "$wheelhouse/$numpy_wheel" ]]; then
    run_cibuildwheel \
      "$temp_dir/numpy" \
      "$architecture" \
      "setup-args=-Duse-ilp64=true setup-args=-Dallow-noblas=false build-dir=build-ios-$architecture" \
      "ninja" \
      "17.0"
  fi

  matplotlib_wheel="matplotlib-${matplotlib_version}-cp314-cp314-ios_17_0_${architecture}.whl"
  if [[ ! -f "$wheelhouse/$matplotlib_wheel" ]]; then
    run_cibuildwheel \
      "$temp_dir/matplotlib-$matplotlib_version" \
      "$architecture" \
      "setup-args=-Dmacosx=false setup-args=-DrcParams-backend=Agg build-dir=build-ios-$architecture" \
      "ninja" \
      "17.0"
  fi

  contourpy_wheel="contourpy-${contourpy_version}-cp314-cp314-ios_17_0_${architecture}.whl"
  if [[ ! -f "$wheelhouse/$contourpy_wheel" ]]; then
    run_cibuildwheel \
      "$temp_dir/contourpy-$contourpy_version" \
      "$architecture" \
      "build-dir=build-ios-$architecture" \
      "ninja" \
      "17.0"
  fi

  kiwisolver_wheel="kiwisolver-${kiwisolver_version}-cp314-cp314-ios_13_0_${architecture}.whl"
  if [[ ! -f "$wheelhouse/$kiwisolver_wheel" ]]; then
    run_cibuildwheel \
      "$temp_dir/kiwisolver-$kiwisolver_version" \
      "$architecture" \
      "" \
      "" \
      "13.0"
  fi
done

: > "$generated_lock"
for filename in "${expected_wheels[@]}"; do
  wheel="$wheelhouse/$filename"
  if [[ ! -f "$wheel" ]]; then
    echo "Expected source-built wheel was not produced: $filename" >&2
    exit 1
  fi
  printf '%s %s\n' "$(shasum -a 256 "$wheel" | awk '{print $1}')" "$filename" >> "$generated_lock"
done

printf '%s\n' "$active_sdk_version" > "$generated_sdk_lock"

echo "Built and locked CPython 3.14 iOS NumPy and Matplotlib wheel set with SDK $active_sdk_version"
