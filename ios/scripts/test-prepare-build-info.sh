#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
source_project="$(cd "$script_directory/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
export PROJECT_DIR="$root/project"
mkdir -p "$PROJECT_DIR/YamabikoChat/App/Resources" "$PROJECT_DIR/YamabikoShareExtension" "$PROJECT_DIR/scripts"
cp "$source_project/YamabikoChat/App/Resources/Info.plist" "$PROJECT_DIR/YamabikoChat/App/Resources/"
cp "$source_project/YamabikoShareExtension/Info.plist" "$PROJECT_DIR/YamabikoShareExtension/"
cp "$script_directory/set-build-version.sh" "$PROJECT_DIR/scripts/"
export BUILD_DIR="$root/products"
export CONFIGURATION=Debug
export EFFECTIVE_PLATFORM_NAME=-iphonesimulator
export BUILD_VERSION_TIMESTAMP='2026-07-04 09:05:00'
phase="$script_directory/prepare-build-info.sh"
destination="$BUILD_DIR/YamabikoBuildMetadata/$CONFIGURATION$EFFECTIVE_PLATFORM_NAME"
"$phase"
for name in App ShareExtension; do
  plist="$destination/$name-Info.plist"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == 09.05 ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == 2026.07.04 ]]
  touch -t 202001010000 "$plist"
done
before="$(stat -f '%m' "$destination/App-Info.plist")"
"$phase"
[[ "$(stat -f '%m' "$destination/App-Info.plist")" == "$before" ]]
[[ "$(stat -f '%m' "$destination/ShareExtension-Info.plist")" == "$before" ]]
export BUILD_VERSION_TIMESTAMP='2026-07-04 09:06:00'
"$phase"
for name in App ShareExtension; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$destination/$name-Info.plist")" == 09.06 ]]
done
rm "$destination/ShareExtension-Info.plist"
"$phase"
test -f "$destination/ShareExtension-Info.plist"
/usr/libexec/PlistBuddy -c 'Add :BuildMetadataTest string changed' "$PROJECT_DIR/YamabikoChat/App/Resources/Info.plist"
"$phase"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BuildMetadataTest' "$destination/App-Info.plist")" == changed ]]
export CONFIGURATION=Release
export EFFECTIVE_PLATFORM_NAME=-iphoneos
"$phase"
test -f "$BUILD_DIR/YamabikoBuildMetadata/Release-iphoneos/App-Info.plist"
echo "Build metadata generation tests passed"
