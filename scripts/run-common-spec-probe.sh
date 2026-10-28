#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIMULATOR_ID:?Set SIMULATOR_ID to an already booted simulator UDID}"
kind="${1:-ios}"
case "$kind" in
    ios) scheme=ContinuousPlayer_for_iOS; platform='iOS Simulator'; products=Debug-iphonesimulator ;;
    tvos) scheme=ContinuousPlayer_for_tvOS; platform='tvOS Simulator'; products=Debug-appletvsimulator ;;
    *) echo 'usage: SIMULATOR_ID=<booted UDID> sh scripts/run-common-spec-probe.sh ios|tvos' >&2; exit 2 ;;
esac
# Never boot or erase a device as a side effect of observation.
xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
expected = "tvOS" if sys.argv[2] == "tvos" else "iOS"
assert any(d["udid"] == sys.argv[1] and d["state"] == "Booted"
           for runtime, rows in devices.items() if expected in runtime for d in rows), "Select a booted simulator of the requested platform"
' "$SIMULATOR_ID" "$kind"
derived="${BUILD_DIR:-/tmp/ContinuousPlayer-common-spec-$kind}"
mkdir -p validation/common-spec
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj -scheme "$scheme" \
    -configuration Debug -destination "platform=$platform,id=$SIMULATOR_ID" \
    -derivedDataPath "$derived" build CODE_SIGNING_ALLOWED=NO \
    > "validation/common-spec/$kind-probe-build.log" 2>&1
app="$derived/Build/Products/$products/$scheme.app"
bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")
xcrun simctl install "$SIMULATOR_ID" "$app"
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" "$bundle" --common-spec-probe
echo "Probe ready: $kind / $SIMULATOR_ID / $bundle"
