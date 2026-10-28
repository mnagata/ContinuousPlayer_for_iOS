#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
xcrun swiftc -module-cache-path "$output/cache" -parse-as-library \
    ContinuousPlayer_for_iOS/PlaybackState.swift ContinuousPlayer_for_iOS/PlaybackController.swift \
    ContinuousPlayer_for_iOS/PlaybackSessionCoordinator.swift ContinuousPlayer_for_iOS/MediaInfo.swift \
    ContinuousPlayer_for_iOS/MediaLibrary.swift ContinuousPlayer_for_iOS/MediaScanner.swift \
    ContinuousPlayer_for_iOS/PlaylistSorter.swift \
    tests/PlaybackSessionTests.swift -o "$output/tests"
"$output/tests" "${1:-validation/common-spec/media}"
