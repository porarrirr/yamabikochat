#!/usr/bin/env bash
set -euo pipefail

# Local archives also serve development and ad-hoc distribution. Enforce the
# App Store SDK policy in distribution workflows before export, where
# validate-app-sdk-versions.sh checks the app and every embedded binary.

if [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphoneos" ]]; then
  python_packages_slice="iphoneos-arm64"
elif [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphonesimulator" && "$ARCHS" == *"x86_64"* ]]; then
  python_packages_slice="iphonesimulator-x86_64"
elif [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphonesimulator" ]]; then
  python_packages_slice="iphonesimulator-arm64"
else
  echo "Unsupported Python target: $EFFECTIVE_PLATFORM_NAME ($ARCHS)" >&2
  exit 1
fi

# Keep the phase scheduled so product deletion/tampering is detected, but skip
# expensive packaging when both its inputs and generated products are unchanged.
cache_tool="$PROJECT_DIR/scripts/build-cache.py"
cache_stamp="$TARGET_TEMP_DIR/python-packaging-cache.json"
cache_arguments=(
  --input "$PROJECT_DIR/Vendor/Python.xcframework"
  --input "$PROJECT_DIR/Vendor/PythonSitePackages/$python_packages_slice"
  --input "$PROJECT_DIR/YamabikoChat/Python/Resources/Fonts"
  --input "$PROJECT_DIR/scripts/process-python-libraries.sh"
  --input "$PROJECT_DIR/scripts/sync-python-site-packages.sh"
  --input "$PROJECT_DIR/scripts/align-python-framework-minimum-os.sh"
  --input "$cache_tool"
)
if [[ "$CONFIGURATION" == "Debug" ]]; then
  # Local incremental builds only: Release continues to read every byte.
  cache_arguments+=(--reuse-file-digests)
fi
for setting in EFFECTIVE_PLATFORM_NAME ARCHS CONFIGURATION SDKROOT SDK_VERSION \
  XCODE_VERSION_ACTUAL IPHONEOS_DEPLOYMENT_TARGET PRODUCT_BUNDLE_IDENTIFIER \
  EXPANDED_CODE_SIGN_IDENTITY EXPANDED_CODE_SIGN_IDENTITY_NAME OTHER_CODE_SIGN_FLAGS \
  CODE_SIGNING_ALLOWED PLATFORM_FAMILY_NAME; do
  cache_arguments+=(--value "$setting=${!setting:-}")
done
packaging_outputs() {
  output_arguments=(
    --output "$CODESIGNING_FOLDER_PATH/python"
    --output "$CODESIGNING_FOLDER_PATH/PythonSitePackages"
  )
  for origin_file in "$CODESIGNING_FOLDER_PATH"/Frameworks/*.framework/*.origin; do
    [[ -f "$origin_file" ]] || continue
    output_arguments+=(--output "$(dirname "$origin_file")")
  done
}

prepare_python() {
  for origin_file in "$CODESIGNING_FOLDER_PATH"/Frameworks/*.framework/*.origin; do
    [[ -f "$origin_file" ]] || continue
    rm -rf "$(dirname "$origin_file")"
  done

  package_destination="$CODESIGNING_FOLDER_PATH/PythonSitePackages"
  mkdir -p "$package_destination"
  # Wheel archives can contain static libraries intended only for compiling
  # downstream extension modules. They are not runtime resources and App Store
  # bundles reject standalone archives outside a framework.
  "$PROJECT_DIR/scripts/sync-python-site-packages.sh" \
    "$PROJECT_DIR/Vendor/PythonSitePackages/$python_packages_slice" \
    "$package_destination"

  font_source="$PROJECT_DIR/YamabikoChat/Python/Resources/Fonts"
  font_destination="$package_destination/matplotlib/mpl-data/fonts/ttf"
  (
    cd "$font_source"
    shasum -a 256 -c SHA256SUMS
  )
  mkdir -p "$font_destination"
  cp "$font_source"/*.ttf "$font_destination/"

  # CPython's official packaging utility also signs dylib frameworks for
  # CODE_SIGNING_ALLOWED=NO simulator/CI builds. An explicit ad-hoc identity keeps
  # that required packaging step deterministic instead of relying on unset Xcode
  # signing variables.
  export EXPANDED_CODE_SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
  export EXPANDED_CODE_SIGN_IDENTITY_NAME="${EXPANDED_CODE_SIGN_IDENTITY_NAME:-Ad Hoc}"

  source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"
  install_python Vendor/Python.xcframework PythonSitePackages

  # CPython's framework template declares its own runtime minimum (currently iOS
  # 13), while locally built scientific extensions target the app's deployment
  # version. App Store validation compares that declaration with each Mach-O load
  # command, so validate the binary contract and align the generated framework
  # plist before the final nested-code signature is produced.
  "$PROJECT_DIR/scripts/align-python-framework-minimum-os.sh" \
    "$CODESIGNING_FOLDER_PATH/Frameworks" \
    "$IPHONEOS_DEPLOYMENT_TARGET"

  for forbidden_pattern in '*.a' '*.so' '*.dylib'; do
    forbidden_binary="$(find "$package_destination" -type f -name "$forbidden_pattern" -print -quit)"
    if [[ -n "$forbidden_binary" ]]; then
      echo "Forbidden standalone Python binary remains in app bundle: $forbidden_binary" >&2
      exit 1
    fi
  done
}

packaging_outputs
if python3 "$cache_tool" check "$cache_stamp" "${cache_arguments[@]}" "${output_arguments[@]}"; then
  echo "Reusing verified Python packaging"
else
  rm -f "$cache_stamp"
  prepare_python
  packaging_outputs
  python3 "$cache_tool" save "$cache_stamp" "${cache_arguments[@]}" "${output_arguments[@]}"
fi

if [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphoneos" && "${DEBUG_INFORMATION_FORMAT:-}" == *dwarf-with-dsym* ]]; then
  if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
    echo "DWARF_DSYM_FOLDER_PATH is required for an archive build" >&2
    exit 1
  fi
  mkdir -p "$DWARF_DSYM_FOLDER_PATH"

  python_framework="$PROJECT_DIR/Vendor/Python.xcframework/ios-arm64/Python.framework"
  "$PROJECT_DIR/scripts/generate-framework-dsym.sh" "$python_framework" "$DWARF_DSYM_FOLDER_PATH"

  for framework in "$CODESIGNING_FOLDER_PATH"/Frameworks/*.framework; do
    [[ -d "$framework" ]] || continue
    "$PROJECT_DIR/scripts/generate-framework-dsym.sh" "$framework" "$DWARF_DSYM_FOLDER_PATH"
  done
fi
