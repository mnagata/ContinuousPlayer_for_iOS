#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIMULATOR_ID:?Set SIMULATOR_ID to a booted iPhone/iPad or Apple TV}"
output=$(mktemp -d)
server_pid=''
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$output"
}
trap cleanup EXIT
case "${PLATFORM:-iOS}" in
    tvOS) port=18769; scheme=ContinuousPlayer_for_tvOS; suite=TVUITests/Stage3TVRecoveryUITests ;;
    iOS) port=18768; scheme=DeviceValidation; suite=DeviceUITests/Stage3RecoveryUITests ;;
    *) exit 2 ;;
esac
python3 tests/common_spec_fixture_server.py --port "$port" --delay 35 --ready-file "$output/address" > "$output/server.log" 2>&1 &
server_pid=$!
count=0
while [ ! -f "$output/address" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null || [ "$count" -gt 100 ]; then cat "$output/server.log"; exit 1; fi
    count=$((count + 1)); sleep 0.05
done
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj -scheme "$scheme" \
    -destination "platform=${PLATFORM:-iOS} Simulator,id=$SIMULATOR_ID" \
    -derivedDataPath "/tmp/ContinuousPlayer-stage3-${PLATFORM:-iOS}" \
    -only-testing:"${ONLY_TESTING:-$suite}" -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO
