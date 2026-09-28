#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify|--build-only) ;;
  *) echo "usage: $0 [--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="${BUILD_DIR:-/tmp/ContinuousPlayer-Catalyst}"
mkdir -p "$BUILD_DIR"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd -P)"
APP_NAME="ContinuousPlayer_for_iOS"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug-maccatalyst/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Match the Catalyst executable path, leaving iOS/tvOS Simulator processes alone.
if [[ "$MODE" != --build-only ]]; then
  pkill -f -x "$APP_BINARY" >/dev/null 2>&1 || true
fi
cd "$ROOT_DIR"
xcodebuild -project ContinuousPlayer_for_iOS.xcodeproj \
  -scheme ContinuousPlayer_for_iOS -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath "$BUILD_DIR" build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""

case "$MODE" in
  --build-only) exit 0 ;;
  --debug) exec lldb -- "$APP_BINARY" ;;
  *) /usr/bin/open -n "$APP_BUNDLE" ;;
esac
case "$MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "jp.nagu.ContinuousPlayer-for-iOS"' ;;
  --verify)
    sleep 2
    pgrep -f -x "$APP_BINARY" >/dev/null
    echo "Mac Catalyst app is running: $APP_BUNDLE"
    ;;
esac
