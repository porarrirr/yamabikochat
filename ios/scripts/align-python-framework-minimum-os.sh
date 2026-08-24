#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <frameworks-directory> <deployment-target>" >&2
  exit 64
fi

frameworks_directory="$1"
deployment_target="$2"
xcrun_command="${XCRUN_COMMAND:-xcrun}"
plutil_command="${PLUTIL_COMMAND:-plutil}"
codesign_command="${CODESIGN_COMMAND:-/usr/bin/codesign}"
codesign_arguments=(
  --force
  --sign "$EXPANDED_CODE_SIGN_IDENTITY"
)
if [[ -n "${OTHER_CODE_SIGN_FLAGS:-}" ]]; then
  read -r -a additional_code_sign_flags <<< "$OTHER_CODE_SIGN_FLAGS"
  codesign_arguments+=("${additional_code_sign_flags[@]}")
fi
codesign_arguments+=(
  -o runtime
  --timestamp=none
  "--preserve-metadata=identifier,entitlements,flags"
  --generate-entitlement-der
)

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

found_framework=false
for origin_file in "$frameworks_directory"/*.framework/*.origin; do
  [[ -f "$origin_file" ]] || continue
  found_framework=true

  binary="${origin_file%.origin}"
  framework="$(dirname "$binary")"
  info_plist="$framework/Info.plist"
  framework_name="$(basename "$framework")"

  if [[ ! -f "$binary" || ! -f "$info_plist" ]]; then
    echo "Malformed Python framework: $framework" >&2
    exit 1
  fi

  binary_minimum_versions="$(
    "$xcrun_command" vtool -show-build "$binary" |
      awk '$1 == "minos" { print $2 }' |
      sort -u
  )"
  if [[ -z "$binary_minimum_versions" ]]; then
    echo "Unable to read the minimum OS version from $binary" >&2
    exit 1
  fi

  while IFS= read -r binary_minimum_version; do
    if version_is_greater "$binary_minimum_version" "$deployment_target"; then
      echo "$framework_name requires iOS $binary_minimum_version, above the app deployment target $deployment_target" >&2
      exit 1
    fi
  done <<< "$binary_minimum_versions"

  "$plutil_command" -replace MinimumOSVersion -string "$deployment_target" "$info_plist"
  echo "Aligned $framework_name minimum OS version to $deployment_target"
  "$codesign_command" "${codesign_arguments[@]}" "$framework"
done

if [[ "$found_framework" == false ]]; then
  echo "No generated Python extension frameworks found in $frameworks_directory" >&2
  exit 1
fi
