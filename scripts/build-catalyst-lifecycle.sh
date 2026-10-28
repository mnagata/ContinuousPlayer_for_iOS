#!/bin/sh
set -eu
[ "${EFFECTIVE_PLATFORM_NAME:-}" = '-maccatalyst' ] || exit 0
bundle="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/PlugIns/MacPlaybackLifecycle.bundle"
mkdir -p "$bundle/Contents/MacOS"
cp "$SRCROOT/MacSupport/Info.plist" "$bundle/Contents/Info.plist"
sdk=$(xcrun --sdk macosx --show-sdk-path)
for arch in $ARCHS; do
    binary="$TEMP_DIR/MacPlaybackLifecycle-$arch"
    xcrun --sdk macosx clang -isysroot "$sdk" -arch "$arch" -mmacosx-version-min=26.0 \
        -fobjc-arc -fblocks -bundle -framework AppKit \
        "$SRCROOT/MacSupport/PlaybackLifecycle.m" -o "$binary"
done
# Build paths can contain spaces; use positional parameters for lipo's inputs.
set --
for arch in $ARCHS; do set -- "$@" "$TEMP_DIR/MacPlaybackLifecycle-$arch"; done
xcrun lipo -create "$@" -output "$bundle/Contents/MacOS/MacPlaybackLifecycle"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$bundle"
fi
