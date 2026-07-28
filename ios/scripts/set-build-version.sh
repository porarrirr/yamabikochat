#!/bin/sh

set -eu

if [ "$#" -ne 1 ] || { [ "$1" != "write" ] && [ "$1" != "read" ]; }; then
    echo "error: Usage: $0 write|read" >&2
    exit 1
fi

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${INFOPLIST_PATH:-}" ] || [ -z "${BUILD_DIR:-}" ]; then
    echo "error: TARGET_BUILD_DIR, INFOPLIST_PATH, and BUILD_DIR are required" >&2
    exit 1
fi

info_plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ ! -f "${info_plist}" ]; then
    echo "error: Built Info.plist not found at ${info_plist}" >&2
    exit 1
fi

timestamp_file="${BUILD_DIR}/yamabiko-build-version.timestamp"
if [ "$1" = "write" ]; then
    build_timestamp="${BUILD_VERSION_TIMESTAMP:-$(date '+%Y-%m-%d %H:%M:%S')}"
    printf '%s\n' "${build_timestamp}" > "${timestamp_file}"
elif [ -f "${timestamp_file}" ]; then
    build_timestamp=$(sed -n '1p' "${timestamp_file}")
else
    echo "error: Shared build timestamp not found at ${timestamp_file}" >&2
    exit 1
fi

marketing_version=$(date -j -f '%Y-%m-%d %H:%M:%S' "${build_timestamp}" '+%Y.%m.%d')
bundle_version=$(date -j -f '%Y-%m-%d %H:%M:%S' "${build_timestamp}" '+%H.%M')

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${marketing_version}" "${info_plist}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${bundle_version}" "${info_plist}"

echo "Set ${PRODUCT_NAME:-target} version to ${marketing_version} (${bundle_version})"
