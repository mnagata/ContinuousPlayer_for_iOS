#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
python3 - "$output" <<'PY'
import sys, wave
from pathlib import Path
for name in ('a.wav', 'b.wav'):
    with wave.open(str(Path(sys.argv[1]) / name), 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(8000)
        f.writeframes(b'\0\0' * 4000)
PY
xcrun swiftc -module-cache-path "$output/cache" -parse-as-library ContinuousPlayer_for_iOS/PlaybackState.swift ContinuousPlayer_for_iOS/PlaybackController.swift ContinuousPlayer_for_iOS/MediaInfo.swift ContinuousPlayer_for_iOS/MediaLibrary.swift ContinuousPlayer_for_iOS/MediaScanner.swift ContinuousPlayer_for_iOS/PlaylistSorter.swift tests/PlaybackIntegrationTests.swift -o "$output/tests"
"$output/tests" "$output" "$@"
