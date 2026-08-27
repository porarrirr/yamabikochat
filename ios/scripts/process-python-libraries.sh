#!/usr/bin/env bash
set -euo pipefail

if [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphoneos" && "$CONFIGURATION" == "Release" ]]; then
  # Archive builds must fail before packaging or signing when the selected
  # toolchain would stamp an App Store-rejected SDK into bundled extensions.
  "$PROJECT_DIR/scripts/validate-active-app-store-sdk.sh"
fi

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

generate_framework_dsym() {
  local framework="$1"
  local framework_name
  local executable_name
  local binary
  local dsym_path
  local dsym_binary
  local binary_uuid
  local dsym_uuid

  framework_name="$(basename "$framework")"
  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")"
  binary="$framework/$executable_name"
  dsym_path="$DWARF_DSYM_FOLDER_PATH/$framework_name.dSYM"
  dsym_binary="$dsym_path/Contents/Resources/DWARF/$executable_name"

  if [[ ! -f "$binary" ]]; then
    echo "Framework executable is missing: $binary" >&2
    exit 1
  fi

  rm -rf "$dsym_path"
  echo "Generating symbols for $framework_name"
  xcrun dsymutil "$binary" -o "$dsym_path" >/dev/null 2>&1
  if [[ ! -f "$dsym_binary" ]]; then
    echo "dSYM generation did not produce a DWARF binary for $framework_name" >&2
    exit 1
  fi

  binary_uuid="$(dwarfdump --uuid "$binary" | awk '{print $2}' | sort | tr '\n' ' ')"
  dsym_uuid="$(dwarfdump --uuid "$dsym_path" | awk '{print $2}' | sort | tr '\n' ' ')"
  if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
    echo "dSYM UUID mismatch for $framework_name: binary=[$binary_uuid] dsym=[$dsym_uuid]" >&2
    exit 1
  fi
}

if [[ "$EFFECTIVE_PLATFORM_NAME" == "-iphoneos" && "${DEBUG_INFORMATION_FORMAT:-}" == *dwarf-with-dsym* ]]; then
  if [[ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]]; then
    echo "DWARF_DSYM_FOLDER_PATH is required for an archive build" >&2
    exit 1
  fi
  mkdir -p "$DWARF_DSYM_FOLDER_PATH"

  python_framework="$PROJECT_DIR/Vendor/Python.xcframework/ios-arm64/Python.framework"
  generate_framework_dsym "$python_framework"

  for framework in "$CODESIGNING_FOLDER_PATH"/Frameworks/*.framework; do
    [[ -d "$framework" ]] || continue
    generate_framework_dsym "$framework"
  done
fi
