#!/usr/bin/env bash
set -euo pipefail
script_directory="$(cd "$(dirname "$0")" && pwd)"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
framework="$root/Test.framework"
symbols="$root/symbols"
mkdir -p "$framework"
printf 'int main(void) { return 0; }\n' > "$root/main.c"
xcrun clang -g "$root/main.c" -o "$framework/Test"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Test' "$framework/Info.plist" >/dev/null
"$script_directory/generate-framework-dsym.sh" "$framework" "$symbols"
dwarf="$symbols/Test.framework.dSYM/Contents/Resources/DWARF/Test"
first_inode="$(stat -f %i "$dwarf")"
"$script_directory/generate-framework-dsym.sh" "$framework" "$symbols" > "$root/reuse.log"
grep -q 'Reusing matching symbols' "$root/reuse.log"
[[ "$(stat -f %i "$dwarf")" == "$first_inode" ]]
printf 'int main(void) { return 42; }\n' > "$root/main.c"
xcrun clang -g "$root/main.c" -o "$framework/Test"
"$script_directory/generate-framework-dsym.sh" "$framework" "$symbols" > "$root/rebuild.log"
grep -q 'Generating symbols' "$root/rebuild.log"
rm "$dwarf"
"$script_directory/generate-framework-dsym.sh" "$framework" "$symbols" > "$root/missing.log"
grep -q 'Generating symbols' "$root/missing.log"
printf 'corrupt symbols' > "$dwarf"
"$script_directory/generate-framework-dsym.sh" "$framework" "$symbols" > "$root/corrupt.log"
grep -q 'Generating symbols' "$root/corrupt.log"
rm "$framework/Test"
if "$script_directory/generate-framework-dsym.sh" "$framework" "$symbols" > "$root/missing-binary.log" 2>&1; then
  echo "Missing framework binary should fail" >&2
  exit 1
fi
echo "dSYM reuse and invalidation tests passed"
