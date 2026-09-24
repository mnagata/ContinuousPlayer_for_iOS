#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIMULATOR_ID:?Set SIMULATOR_ID to an available Apple TV Simulator UDID}"
output=$(mktemp -d)
server_pid=''
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$output"
}
trap cleanup EXIT
DLNA_FIXTURE_PORT=18765 python3 tests/dlna-fixture-server.py "$output" "${1:-validation/fixtures/09_h264.mp4}" > "$output/server.log" 2>&1 &
server_pid=$!
count=0
while [ ! -f "$output/port" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null || [ "$count" -gt 100 ]; then cat "$output/server.log"; exit 1; fi
    count=$((count + 1))
    sleep 0.05
done
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj -scheme ContinuousPlayer_for_tvOS \
    -destination "platform=tvOS Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath /tmp/ContinuousPlayer-tvOS \
    -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
