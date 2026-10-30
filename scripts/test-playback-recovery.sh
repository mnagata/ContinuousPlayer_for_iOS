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
python3 tests/common_spec_fixture_server.py --port 0 --delay 2 --ready-file "$output/address" > "$output/server.log" 2>&1 &
server_pid=$!
count=0
while [ ! -f "$output/address" ]; do
    if ! kill -0 "$server_pid" 2>/dev/null || [ "$count" -gt 100 ]; then cat "$output/server.log"; exit 1; fi
    count=$((count + 1)); sleep 0.05
done
python3 - "$output/audio.wav" <<'PY'
import sys, wave
with wave.open(sys.argv[1], 'wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(8000); f.writeframes(b'\0\0' * 8000)
PY
ffmpeg -hide_banner -loglevel error -y -i "validation/common-spec/media/Fixture OP.mp4" -an -c:v copy "$output/video-only.mp4"
xcrun swiftc -module-cache-path "$output/cache" -parse-as-library \
    ContinuousPlayer_for_iOS/PlaybackState.swift ContinuousPlayer_for_iOS/PlaybackController.swift \
    ContinuousPlayer_for_iOS/MediaInfo.swift tests/PlaybackRecoveryTests.swift -o "$output/tests"
"$output/tests" "$(cat "$output/address")" "${1:-validation/common-spec/media}" "$output/audio.wav" "$output/video-only.mp4"
