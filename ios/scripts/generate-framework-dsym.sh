#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 FRAMEWORK SYMBOLS_DIRECTORY" >&2
  exit 64
fi
framework="$1"
symbols_directory="$2"
mkdir -p "$symbols_directory"

framework_name="$(basename "$framework")"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$framework/Info.plist")"
binary="$framework/$executable_name"
dsym_path="$symbols_directory/$framework_name.dSYM"
dsym_binary="$dsym_path/Contents/Resources/DWARF/$executable_name"

if [[ ! -f "$binary" ]]; then
  echo "Framework executable is missing: $binary" >&2
  exit 1
fi

binary_uuid="$(dwarfdump --uuid "$binary" | awk '{print $2}' | sort | tr '\n' ' ')"
if [[ -f "$dsym_binary" && -n "$binary_uuid" ]]; then
  dsym_uuid="$(dwarfdump --uuid "$dsym_path" 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' ' || true)"
  if [[ "$binary_uuid" == "$dsym_uuid" ]]; then
    echo "Reusing matching symbols for $framework_name"
    exit 0
  fi
fi

rm -rf "$dsym_path"
echo "Generating symbols for $framework_name"
xcrun dsymutil "$binary" -o "$dsym_path" >/dev/null 2>&1
if [[ ! -f "$dsym_binary" ]]; then
  echo "dSYM generation did not produce a DWARF binary for $framework_name" >&2
  exit 1
fi

binary_uuid="$(dwarfdump --uuid "$binary" | awk '{print $2}' | sort | tr '\n' ' ')"
dsym_uuid="$(dwarfdump --uuid "$dsym_path" | awk '{print $2}' | sort | tr '\n' ' ')"
if [[ -z "$binary_uuid" || "$binary_uuid" != "$dsym_uuid" ]]; then
  echo "dSYM UUID mismatch for $framework_name: binary=[$binary_uuid] dsym=[$dsym_uuid]" >&2
  exit 1
fi
