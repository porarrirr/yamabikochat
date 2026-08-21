#!/usr/bin/env bash
set -euo pipefail

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
rsync -au --delete "$PROJECT_DIR/Vendor/PythonSitePackages/$python_packages_slice/" "$package_destination/"

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
