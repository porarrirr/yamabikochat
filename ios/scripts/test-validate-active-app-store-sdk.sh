#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
ios_directory="$(cd "$script_directory/.." && pwd)"
repository_directory="$(cd "$ios_directory/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

# shellcheck disable=SC1090,SC1091
source "$ios_directory/app-store-build.env"
app_store_xcode_version="${app_store_xcode_version:?}"
app_store_max_sdk_version="${app_store_max_sdk_version:?}"

for workflow in ios-ci.yml ios-ipa.yml ios-testflight.yml; do
  workflow_path="$repository_directory/.github/workflows/$workflow"
  grep -Fq "XCODE_VERSION: \"$app_store_xcode_version\"" "$workflow_path"
  grep -Fq "APP_STORE_MAX_SDK_VERSION: \"$app_store_max_sdk_version\"" "$workflow_path"
done

cat > "$test_directory/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "${TEST_ACTIVE_SDK:?}"
SCRIPT
chmod +x "$test_directory/xcrun"

for supported_version in 26.4 26.5 26.5.0; do
  TEST_ACTIVE_SDK="$supported_version" \
    XCRUN_COMMAND="$test_directory/xcrun" \
    "$script_directory/validate-active-app-store-sdk.sh"
done

if TEST_ACTIVE_SDK=27.0 \
  XCRUN_COMMAND="$test_directory/xcrun" \
  "$script_directory/validate-active-app-store-sdk.sh"; then
  echo "Expected SDK 27.0 validation to fail" >&2
  exit 1
fi

echo "Active App Store SDK validation tests passed"
