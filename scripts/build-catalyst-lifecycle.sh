#!/bin/sh
set -eu
[ "${EFFECTIVE_PLATFORM_NAME:-}" = '-maccatalyst' ] || exit 0
bundle="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/PlugIns/MacPlaybackLifecycle.bundle"
# Compile and sign in Xcode's writable scratch directory. codesign creates
# temporary files that cannot be listed as fixed build-phase outputs.
staging="$TEMP_DIR/MacPlaybackLifecycle-stage.bundle"
mkdir -p "$staging/Contents/MacOS"
cp "$SRCROOT/MacSupport/Info.plist" "$staging/Contents/Info.plist"
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
xcrun lipo -create "$@" -output "$staging/Contents/MacOS/MacPlaybackLifecycle"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$staging"
fi
# Keep these fixed paths in the phase's Output Files, including directories:
# an output bundle path alone grants access only to that path on a clean build.
mkdir -p "$bundle/Contents/MacOS"
cp "$staging/Contents/Info.plist" "$bundle/Contents/Info.plist"
cp "$staging/Contents/MacOS/MacPlaybackLifecycle" "$bundle/Contents/MacOS/MacPlaybackLifecycle"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
    mkdir -p "$bundle/Contents/_CodeSignature"
    cp "$staging/Contents/_CodeSignature/CodeResources" "$bundle/Contents/_CodeSignature/CodeResources"
else
    rm -f "$bundle/Contents/_CodeSignature/CodeResources"
    rmdir "$bundle/Contents/_CodeSignature" 2>/dev/null || true
fi
