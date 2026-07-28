#!/bin/sh

set -eu

test_directory=$(mktemp -d)
trap 'rm -rf "${test_directory}"' EXIT

info_plist="${test_directory}/Info.plist"
cat > "${info_plist}" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>0</string>
    <key>CFBundleVersion</key>
    <string>0</string>
</dict>
</plist>
PLIST

TARGET_BUILD_DIR="${test_directory}" \
INFOPLIST_PATH="Info.plist" \
BUILD_DIR="${test_directory}" \
PRODUCT_NAME="VersionScriptTest" \
BUILD_VERSION_TIMESTAMP="2026-07-04 09:05:00" \
    "$(dirname "$0")/set-build-version.sh" write

marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")

[ "${marketing_version}" = "2026.07.04" ]
[ "${bundle_version}" = "09.05" ]

/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0' "${info_plist}"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 0' "${info_plist}"

TARGET_BUILD_DIR="${test_directory}" \
INFOPLIST_PATH="Info.plist" \
BUILD_DIR="${test_directory}" \
PRODUCT_NAME="VersionScriptReadTest" \
    "$(dirname "$0")/set-build-version.sh" read

marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")
bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")

[ "${marketing_version}" = "2026.07.04" ]
[ "${bundle_version}" = "09.05" ]

echo "Build version script test passed"
