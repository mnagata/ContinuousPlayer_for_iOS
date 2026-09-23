#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output=$(mktemp -d)
server_pid=''
cleanup() {
    if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    rm -rf "$output"
}
trap cleanup EXIT
xcrun swiftc -module-cache-path "$output/cache" -parse-as-library \
    ContinuousPlayer_for_iOS/DLNAClient.swift ContinuousPlayer_for_iOS/DLNADiscovery.swift \
    ContinuousPlayer_for_iOS/MediaScanner.swift ContinuousPlayer_for_iOS/PlaylistSorter.swift ContinuousPlayer_for_iOS/PlaybackState.swift \
    ContinuousPlayer_for_iOS/PlaybackController.swift ContinuousPlayer_for_iOS/MediaInfo.swift \
    tests/DLNATests.swift -o "$output/tests"
python3 tests/dlna-fixture-server.py "$output" "$@" > "$output/server.log" 2>&1 &
server_pid=$!
count=0
while [ ! -f "$output/port" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null || [ "$count" -gt 100 ]; then cat "$output/server.log"; exit 1; fi
    count=$((count + 1))
    sleep 0.05
done
"$output/tests" "http://127.0.0.1:$(cat "$output/port")"
