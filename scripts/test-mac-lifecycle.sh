#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun --sdk macosx clang -isysroot "$sdk" -fobjc-arc -fblocks -framework AppKit \
    tests/MacLifecycleTests.m -o "$output/tests"
"$output/tests" "${1:-/tmp/ContinuousPlayer-Catalyst/Build/Products/Debug-maccatalyst/ContinuousPlayer.app/Contents/PlugIns/MacPlaybackLifecycle.bundle}"
