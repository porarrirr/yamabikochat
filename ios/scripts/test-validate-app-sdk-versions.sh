#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

app="$test_directory/YamabikoChat.app"
framework="$app/Frameworks/numpy._core.framework"
mkdir -p "$framework" "$test_directory/bin"

write_info_plist() {
  local path="$1"
  local executable="$2"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleExecutable</key><string>%s</string></dict></plist>\n' \
    "$executable" > "$path"
}

write_info_plist "$app/Info.plist" "YamabikoChat"
write_info_plist "$framework/Info.plist" "numpy._core"
touch "$app/YamabikoChat" "$framework/numpy._core"

cat > "$test_directory/bin/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$3" == *numpy._core ]]; then
  printf '      sdk %s\n' "${TEST_FRAMEWORK_SDK:?}"
else
  printf '      sdk %s\n' "${TEST_APP_SDK:?}"
fi
SCRIPT
chmod +x "$test_directory/bin/xcrun"

TEST_APP_SDK=26.5 TEST_FRAMEWORK_SDK=26.4 \
  XCRUN_COMMAND="$test_directory/bin/xcrun" \
  "$script_directory/validate-app-sdk-versions.sh" "$app" 26.5

if TEST_APP_SDK=26.5 TEST_FRAMEWORK_SDK=27.0 \
  XCRUN_COMMAND="$test_directory/bin/xcrun" \
  "$script_directory/validate-app-sdk-versions.sh" "$app" 26.5; then
  echo "Expected SDK 27.0 validation to fail" >&2
  exit 1
fi

echo "App SDK version validation tests passed"
