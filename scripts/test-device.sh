#!/bin/sh
# DEVICE_ID=<connected iPhone/iPad UDID> sh scripts/test-device.sh
# Uses a separate UIFixtures directory and never changes the saved folder bookmark.
set -eu
cd "$(dirname "$0")/.."
: "${DEVICE_ID:?Set DEVICE_ID to the connected iPhone or iPad UDID}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
build_dir="${BUILD_DIR:-/tmp/ContinuousPlayerFinishing}"
result="${RESULT_BUNDLE:-/tmp/ContinuousPlayer-device-$(date +%Y%m%d-%H%M%S).xcresult}"
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
python3 - "$fixtures" <<'PY'
import sys, wave
from pathlib import Path
for name, seconds in [('OP', 120), ('ED', 120), ('OP2', 2), ('ED2', 2)]:
    with wave.open(str(Path(sys.argv[1]) / f'実機テスト {name}.wav'), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(8000)
        f.writeframes(b'\0\0' * 8000 * seconds)
second = Path(sys.argv[1]) / 'SecondPlaylist'
second.mkdir()
import shutil
shutil.copyfile(Path(sys.argv[1]) / '実機テスト OP.wav', second / '別フォルダー OP.wav')
PY
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj -scheme DeviceValidation \
    -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$build_dir" build-for-testing
xcrun devicectl device install app --device "$DEVICE_ID" \
    "$build_dir/Build/Products/Debug-iphoneos/ContinuousPlayer_for_iOS.app"
xcrun devicectl device copy to --device "$DEVICE_ID" --source "$fixtures" \
    --destination Documents/UIFixtures --domain-type appDataContainer \
    --domain-identifier jp.nagu.ContinuousPlayer-for-iOS
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj -scheme DeviceValidation \
    -destination "platform=iOS,id=$DEVICE_ID" -derivedDataPath "$build_dir" \
    -resultBundlePath "$result" test-without-building
printf 'Results: %s\n' "$result"
