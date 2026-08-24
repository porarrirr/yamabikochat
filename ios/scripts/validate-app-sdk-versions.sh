#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-bundle> <maximum-sdk-version>" >&2
  exit 64
fi

app_bundle="$1"
maximum_sdk_version="$2"
xcrun_command="${XCRUN_COMMAND:-xcrun}"
plist_buddy_command="${PLIST_BUDDY_COMMAND:-/usr/libexec/PlistBuddy}"

if [[ ! -d "$app_bundle" ]]; then
  echo "App bundle not found: $app_bundle" >&2
  exit 1
fi

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

checked_binary_count=0
while IFS= read -r bundle; do
  info_plist="$bundle/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    echo "Executable bundle is missing Info.plist: $bundle" >&2
    exit 1
  fi

  executable_name="$($plist_buddy_command -c 'Print :CFBundleExecutable' "$info_plist")"
  binary="$bundle/$executable_name"
  if [[ ! -f "$binary" ]]; then
    echo "Bundle executable is missing: $binary" >&2
    exit 1
  fi

  sdk_versions="$($xcrun_command vtool -show-build "$binary" | awk '$1 == "sdk" { print $2 }' | sort -u)"
  if [[ -z "$sdk_versions" ]]; then
    echo "Unable to read LC_BUILD_VERSION SDK from $binary" >&2
    exit 1
  fi

  while IFS= read -r sdk_version; do
    if version_is_greater "$sdk_version" "$maximum_sdk_version"; then
      echo "App Store SDK validation failed: $binary uses SDK $sdk_version, above allowed maximum $maximum_sdk_version" >&2
      exit 1
    fi
  done <<< "$sdk_versions"

  checked_binary_count=$((checked_binary_count + 1))
done < <(find "$app_bundle" -type d \( -name '*.app' -o -name '*.appex' -o -name '*.framework' \) -print | sort)

if [[ "$checked_binary_count" -eq 0 ]]; then
  echo "No executable bundles found in $app_bundle" >&2
  exit 1
fi

echo "Verified LC_BUILD_VERSION SDK <= $maximum_sdk_version for $checked_binary_count bundled executables"
