#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -module-cache-path "$output/cache" -parse-as-library \
    ContinuousPlayer_for_iOS/PlaylistSorter.swift ContinuousPlayer_for_iOS/MediaScanner.swift ContinuousPlayer_for_iOS/MediaDisplayName.swift \
    ContinuousPlayer_for_iOS/PlaybackChromeState.swift tests/PlaybackChromeTests.swift -o "$output/tests"
"$output/tests"
