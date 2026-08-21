#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BUILT_PRODUCTS_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
    echo "error: BUILT_PRODUCTS_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH are required" >&2
    exit 1
fi

src_root="$(cd "$(dirname "$0")/../.." && pwd)"
dest="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/legal"
mkdir -p "$dest"

cp "${src_root}/LICENSE" "${dest}/LICENSE.txt"
cp "${src_root}/THIRD_PARTY_NOTICES.md" "${dest}/THIRD_PARTY_NOTICES.md"
cp "${src_root}/third_party/nodejs-mobile/LICENSE" "${dest}/NODEJS_LICENSE.txt"
cp "${src_root}/third_party/npm-licenses.md" "${dest}/npm-licenses.md"

font_license_root="${src_root}/ios/YamabikoChat/Python/Resources/Fonts/licenses"
font_license_output="${dest}/NOTO_FONTS_LICENSES.txt"
: > "$font_license_output"
for license_file in "$font_license_root"/*.txt; do
    printf '===== %s =====\n\n' "$(basename "$license_file")" >> "$font_license_output"
    cat "$license_file" >> "$font_license_output"
    printf '\n\n' >> "$font_license_output"
done

echo "Copied legal notices to ${dest}"
