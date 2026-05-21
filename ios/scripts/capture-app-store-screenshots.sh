#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${ROOT_DIR}/AppStoreScreenshots"
DERIVED_DATA="${TMPDIR:-/tmp}/YamabikoScreenshotDerivedData"
IPHONE_NAME="${IPHONE_NAME:-iPhone 14 Plus}"
IPAD_NAME="${IPAD_NAME:-iPad Pro 13-inch (M5)}"
RUNTIME="${RUNTIME:-}"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

xcodegen generate

ensure_simulator() {
  local name="$1"
  local udid
  udid="$(xcrun simctl list devices available | grep -F "${name} (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')"
  if [[ -n "${udid}" ]]; then
    echo "${udid}"
    return
  fi

  if [[ -z "${RUNTIME}" ]]; then
    RUNTIME="$(xcrun simctl list runtimes available | grep -E 'iOS [0-9]' | tail -1 | sed -E 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.[^)]+).*/\1/')"
  fi

  local device_type
  device_type="$(xcrun simctl list devicetypes | awk -v name="${name}" '$0 ~ name { print $NF; exit }' | tr -d '()')"
  udid="$(xcrun simctl create "${name}" "${device_type}" "${RUNTIME}")"
  echo "${udid}"
}

prepare_device() {
  local udid="$1"
  xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true
  xcrun simctl erase "${udid}"
  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${udid}" -b
}

build_app() {
  local udid="$1"
  xcodebuild \
    -project YamabikoChat.xcodeproj \
    -scheme YamabikoChat \
    -destination "platform=iOS Simulator,id=${udid}" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null
}

capture_scene() {
  local udid="$1"
  local output_dir="$2"
  local filename="$3"
  local scene="$4"
  shift 4

  xcrun simctl terminate "${udid}" com.porarri.yamabikochat.ios >/dev/null 2>&1 || true
  xcrun simctl launch "${udid}" com.porarri.yamabikochat.ios \
    -AppStoreScreenshotDemo \
    -ScreenshotScene "${scene}" \
    "$@" >/dev/null
  sleep 5
  xcrun simctl io "${udid}" screenshot "${output_dir}/${filename}.png"
  echo "  ${filename}.png"
}

capture_device_set() {
  local device_name="$1"
  local output_dir="$2"
  local udid
  udid="$(ensure_simulator "${device_name}")"

  mkdir -p "${output_dir}"
  prepare_device "${udid}"
  build_app "${udid}"

  local app_path="${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/YamabikoChat.app"
  xcrun simctl install "${udid}" "${app_path}"

  echo "Capturing ${device_name} -> ${output_dir}"

  capture_scene "${udid}" "${output_dir}" "01-conversation-list" "list"
  capture_scene "${udid}" "${output_dir}" "02-chat-markdown" "chat" -ScreenshotConversationId 2
  capture_scene "${udid}" "${output_dir}" "03-chat-travel" "chat" -ScreenshotConversationId 5
  capture_scene "${udid}" "${output_dir}" "04-settings-api" "settings-api"
  capture_scene "${udid}" "${output_dir}" "05-settings-appearance" "settings-appearance"
  capture_scene "${udid}" "${output_dir}" "06-settings-dual" "settings-dual"
  capture_scene "${udid}" "${output_dir}" "07-settings-auto" "settings-auto"
  capture_scene "${udid}" "${output_dir}" "08-project-filter" "project" -ScreenshotProjectId 1

  if [[ "${device_name}" == *"iPad"* ]]; then
    capture_scene "${udid}" "${output_dir}" "09-ipad-split-chat" "chat" -ScreenshotConversationId 2
    xcrun simctl status_bar "${udid}" override --orientation landscapeLeft >/dev/null 2>&1 || true
    sleep 1
    capture_scene "${udid}" "${output_dir}" "10-ipad-landscape-chat" "chat" -ScreenshotConversationId 5
    xcrun simctl status_bar "${udid}" override --orientation portrait >/dev/null 2>&1 || true
  fi

  xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true

  echo "Dimensions:"
  for file in "${output_dir}"/*.png; do
    [[ -f "${file}" ]] || continue
    sips -g pixelWidth -g pixelHeight "${file}" | awk -v file="$(basename "${file}")" '/pixelWidth|pixelHeight/ { line=(line=="" ? file ": " : line ", ") $2 } END { print "  " line }'
  done
}

record_preview() {
  local udid="$1"
  local output_file="$2"
  local scene="$3"
  shift 3

  xcrun simctl launch "${udid}" com.porarri.yamabikochat.ios \
    -AppStoreScreenshotDemo \
    -ScreenshotScene "${scene}" \
    "$@" >/dev/null

  xcrun simctl io "${udid}" recordVideo --codec=h264 --force "${output_file}" &
  local recorder_pid=$!
  sleep 18
  kill -INT "${recorder_pid}" >/dev/null 2>&1 || true
  wait "${recorder_pid}" >/dev/null 2>&1 || true
  echo "  $(basename "${output_file}")"
}

rm -rf "${OUTPUT_ROOT}"
mkdir -p "${OUTPUT_ROOT}/iphone-6.5-inch" "${OUTPUT_ROOT}/ipad-13-inch"

capture_device_set "${IPHONE_NAME}" "${OUTPUT_ROOT}/iphone-6.5-inch"
capture_device_set "${IPAD_NAME}" "${OUTPUT_ROOT}/ipad-13-inch"

iphone_udid="$(ensure_simulator "${IPHONE_NAME}")"
ipad_udid="$(ensure_simulator "${IPAD_NAME}")"
prepare_device "${iphone_udid}"
prepare_device "${ipad_udid}"
build_app "${iphone_udid}"
xcrun simctl install "${iphone_udid}" "${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/YamabikoChat.app"
xcrun simctl install "${ipad_udid}" "${DERIVED_DATA}/Build/Products/Debug-iphonesimulator/YamabikoChat.app"

echo "Recording optional app previews"
record_preview "${iphone_udid}" "${OUTPUT_ROOT}/iphone-6.5-inch/preview-01.mp4" "chat" -ScreenshotConversationId 2
record_preview "${ipad_udid}" "${OUTPUT_ROOT}/ipad-13-inch/preview-01.mp4" "chat" -ScreenshotConversationId 2

cat <<EOF

Done.
iPhone folder: ${OUTPUT_ROOT}/iphone-6.5-inch
iPad folder:   ${OUTPUT_ROOT}/ipad-13-inch

App Store Connect (6.5-inch iPhone): use PNGs at 1284x2778 or 1242x2688
App Store Connect (13-inch iPad):    use PNGs at 2064x2752 or 2048x2732
Upload up to 10 screenshots and 3 app previews per device class.
EOF
