#!/usr/bin/env bash
set -euo pipefail

ios_directory="$(cd "$(dirname "$0")/.." && pwd)"
build_contract="$ios_directory/app-store-build.env"
xcrun_command="${XCRUN_COMMAND:-xcrun}"

if [[ ! -f "$build_contract" ]]; then
  echo "Missing App Store build contract: $build_contract" >&2
  exit 1
fi

# shellcheck disable=SC1090,SC1091
source "$build_contract"
app_store_xcode_version="${app_store_xcode_version:?Missing app_store_xcode_version in $build_contract}"
app_store_max_sdk_version="${app_store_max_sdk_version:?Missing app_store_max_sdk_version in $build_contract}"

version_is_greater() {
  awk -v lhs="$1" -v rhs="$2" 'BEGIN {
    lhs_count = split(lhs, lhs_parts, ".")
    rhs_count = split(rhs, rhs_parts, ".")
    count = lhs_count > rhs_count ? lhs_count : rhs_count
    for (part_index = 1; part_index <= count; part_index++) {
      lhs_part = part_index <= lhs_count ? lhs_parts[part_index] + 0 : 0
      rhs_part = part_index <= rhs_count ? rhs_parts[part_index] + 0 : 0
      if (lhs_part > rhs_part) exit 0
      if (lhs_part < rhs_part) exit 1
    }
    exit 1
  }'
}

active_sdk_version="$($xcrun_command --sdk iphoneos --show-sdk-version)"
if version_is_greater "$active_sdk_version" "$app_store_max_sdk_version"; then
  echo "Unsupported App Store build SDK: active iPhoneOS SDK $active_sdk_version exceeds allowed maximum $app_store_max_sdk_version." >&2
  echo "Select an Xcode containing iPhoneOS SDK $app_store_max_sdk_version or earlier (release CI uses Xcode $app_store_xcode_version), then run ios/bootstrap.sh again." >&2
  echo "The SDK-tagged wheel cache will be rebuilt automatically." >&2
  exit 1
fi

echo "Verified active iPhoneOS SDK $active_sdk_version for App Store maximum $app_store_max_sdk_version"
