#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export PROJECT_DIR="$root/project"
export CODESIGNING_FOLDER_PATH="$root/App.app"
export TARGET_TEMP_DIR="$root/intermediates"
export EFFECTIVE_PLATFORM_NAME=-iphonesimulator
export ARCHS=arm64
export CONFIGURATION=Debug
export IPHONEOS_DEPLOYMENT_TARGET=17.0
export EXPANDED_CODE_SIGN_IDENTITY=-
export PACKAGING_LOG="$root/packaging.log"
fonts="$PROJECT_DIR/YamabikoChat/Python/Resources/Fonts"
packages="$PROJECT_DIR/Vendor/PythonSitePackages/iphonesimulator-arm64"
mkdir -p "$PROJECT_DIR/scripts" "$PROJECT_DIR/Vendor/Python.xcframework/build" "$fonts" "$packages"
cp "$script_directory"/{process-python-libraries.sh,sync-python-site-packages.sh,build-cache.py} "$PROJECT_DIR/scripts/"
printf 'font\n' > "$fonts/test.ttf"
(cd "$fonts" && shasum -a 256 test.ttf > SHA256SUMS)
printf 'package\n' > "$packages/module.py"
# A fixture for the upstream packager keeps this test independent of Xcode
# signing and wheels while exercising the real cache/phase orchestration.
cat > "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh" <<'FIXTURE'
install_python() {
  echo packaged >> "$PACKAGING_LOG"
  mkdir -p "$CODESIGNING_FOLDER_PATH/python/lib" "$CODESIGNING_FOLDER_PATH/Frameworks/test.framework"
  cp "$PROJECT_DIR/Vendor/PythonSitePackages/$python_packages_slice/module.py" "$CODESIGNING_FOLDER_PATH/python/lib/module.py"
  printf 'binary\n' > "$CODESIGNING_FOLDER_PATH/Frameworks/test.framework/test"
  printf 'origin\n' > "$CODESIGNING_FOLDER_PATH/Frameworks/test.framework/test.origin"
}
FIXTURE
cat > "$PROJECT_DIR/scripts/align-python-framework-minimum-os.sh" <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
printf 'aligned\n' >> "$PACKAGING_LOG"
FIXTURE
chmod +x "$PROJECT_DIR/scripts/align-python-framework-minimum-os.sh"
phase="$PROJECT_DIR/scripts/process-python-libraries.sh"
"$phase" > "$root/first.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 2 ]]
"$phase" > "$root/reuse.log"
grep -q 'Reusing verified Python packaging' "$root/reuse.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 2 ]]
printf 'changed\n' > "$packages/module.py"
"$phase" > "$root/input.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 4 ]]
printf 'corrupt\n' > "$CODESIGNING_FOLDER_PATH/Frameworks/test.framework/test"
"$phase" > "$root/corrupt.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 6 ]]
rm -rf "$CODESIGNING_FOLDER_PATH/Frameworks/test.framework"
"$phase" > "$root/deleted.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 8 ]]
export EXPANDED_CODE_SIGN_IDENTITY=changed-identity
"$phase" > "$root/identity.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 10 ]]
export SDK_VERSION=changed-sdk
"$phase" > "$root/sdk.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 12 ]]
printf 'invalid font\n' > "$fonts/test.ttf"
if "$phase" > "$root/failure.log" 2>&1; then
  echo "Invalid font checksum must fail packaging" >&2
  exit 1
fi
test ! -f "$TARGET_TEMP_DIR/python-packaging-cache.json"
printf 'font\n' > "$fonts/test.ttf"
"$phase" > "$root/recover.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 14 ]]
# Release must not reuse file metadata to validate packaged contents.
export CONFIGURATION=Release
"$phase" > "$root/release.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 16 ]]
python3 - "$TARGET_TEMP_DIR/python-packaging-cache.json" <<'PY'
import json
import sys
assert "files" not in json.load(open(sys.argv[1]))
PY
"$phase" > "$root/release-reuse.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 16 ]]
# A newer local SDK must not block device builds or local archives. App Store
# distribution validates the finished bundle separately before export.
mkdir -p "$PROJECT_DIR/Vendor/PythonSitePackages/iphoneos-arm64"
cp "$packages/module.py" "$PROJECT_DIR/Vendor/PythonSitePackages/iphoneos-arm64/"
cat > "$PROJECT_DIR/scripts/validate-active-app-store-sdk.sh" <<'FIXTURE'
#!/usr/bin/env bash
echo 'Unsupported App Store build SDK' >&2
exit 1
FIXTURE
chmod +x "$PROJECT_DIR/scripts/validate-active-app-store-sdk.sh"
export EFFECTIVE_PLATFORM_NAME=-iphoneos
export ACTION=build
export DEBUG_INFORMATION_FORMAT=dwarf
"$phase" > "$root/device-release.log"
[[ "$(wc -l < "$PACKAGING_LOG" | tr -d ' ')" == 18 ]]
for configuration in Debug Release; do
  ACTION=install CONFIGURATION="$configuration" "$phase" > "$root/archive.log" 2>&1
done
echo "Python packaging cache integration tests passed"
