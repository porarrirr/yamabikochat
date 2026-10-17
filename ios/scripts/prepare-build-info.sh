#!/usr/bin/env bash
set -euo pipefail

# Generate plist inputs before Xcode processes them, rather than modifying the
# built plists behind its dependency graph. Both products share one timestamp.
destination="$BUILD_DIR/YamabikoBuildMetadata/$CONFIGURATION$EFFECTIVE_PLATFORM_NAME"
mkdir -p "$destination"
temporary="$(mktemp -d "$destination/.prepare.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
cp "$PROJECT_DIR/YamabikoChat/App/Resources/Info.plist" "$temporary/App-Info.plist"
cp "$PROJECT_DIR/YamabikoShareExtension/Info.plist" "$temporary/ShareExtension-Info.plist"
TARGET_BUILD_DIR="$temporary" INFOPLIST_PATH=App-Info.plist BUILD_DIR="$temporary" \
  "$PROJECT_DIR/scripts/set-build-version.sh" write
TARGET_BUILD_DIR="$temporary" INFOPLIST_PATH=ShareExtension-Info.plist BUILD_DIR="$temporary" \
  "$PROJECT_DIR/scripts/set-build-version.sh" read
for name in App ShareExtension; do
  if ! cmp -s "$temporary/$name-Info.plist" "$destination/$name-Info.plist"; then
    mv "$temporary/$name-Info.plist" "$destination/$name-Info.plist"
  fi
done
