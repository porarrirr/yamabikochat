#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

tools_directory="$temporary_directory/tools"
frameworks_directory="$temporary_directory/Frameworks"
framework="$frameworks_directory/numpy._core.framework"
mkdir -p "$tools_directory" "$framework"
touch "$framework/numpy._core" "$framework/numpy._core.origin"
printf 'MinimumOSVersion=13.0\n' > "$framework/Info.plist"

cat > "$tools_directory/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' 'Load command 10' '    minos 17.0'
SCRIPT
cat > "$tools_directory/plutil" <<'SCRIPT'
#!/usr/bin/env bash
printf 'MinimumOSVersion=%s\n' "$4" > "$5"
SCRIPT
cat > "$tools_directory/codesign" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CODESIGN_LOG"
SCRIPT
chmod +x "$tools_directory"/*

export EXPANDED_CODE_SIGN_IDENTITY="test-identity"
export XCRUN_COMMAND="$tools_directory/xcrun"
export PLUTIL_COMMAND="$tools_directory/plutil"
export CODESIGN_COMMAND="$tools_directory/codesign"
export CODESIGN_LOG="$temporary_directory/codesign.log"

"$script_directory/align-python-framework-minimum-os.sh" "$frameworks_directory" 17.0
grep -qx 'MinimumOSVersion=17.0' "$framework/Info.plist"
grep -q -- '--sign test-identity' "$CODESIGN_LOG"

cat > "$tools_directory/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' 'Load command 10' '    minos 18.0'
SCRIPT

if "$script_directory/align-python-framework-minimum-os.sh" "$frameworks_directory" 17.0 \
  >"$temporary_directory/too-new.stdout" 2>"$temporary_directory/too-new.stderr"; then
  echo "Expected a binary newer than the deployment target to be rejected" >&2
  exit 1
fi
grep -q 'requires iOS 18.0, above the app deployment target 17.0' "$temporary_directory/too-new.stderr"

echo "align-python-framework-minimum-os tests passed"
