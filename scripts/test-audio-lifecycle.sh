#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${SIMULATOR_ID:?Set SIMULATOR_ID to a booted tvOS 27+ Simulator}"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
sdk=$(xcrun --sdk appletvsimulator --show-sdk-path)
xcrun --sdk appletvsimulator swiftc -sdk "$sdk" -target arm64-apple-tvos27.0-simulator \
    -module-cache-path "$output/cache" -parse-as-library \
    ContinuousPlayer_for_iOS/PlaybackState.swift ContinuousPlayer_for_iOS/PlaybackController.swift \
    ContinuousPlayer_for_iOS/PlaybackSessionCoordinator.swift ContinuousPlayer_for_iOS/MediaInfo.swift \
    tests/PlaybackAudioLifecycleTests.swift -o "$output/tests"
media=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "${1:-validation/common-spec/media/Fixture OP.mp4}")
xcrun simctl spawn "$SIMULATOR_ID" "$output/tests" "$media"
