#!/bin/bash
# Builds a universal (arm64 + x86_64) SnapMark.app into ./build.
# Usage: scripts/build_app.sh            (release, ad-hoc signed)
#        SIGN_IDENTITY="Apple Development: …" scripts/build_app.sh
#
# NOTE: macOS ties the Screen Recording grant to the code signature. Ad-hoc signatures change on
# every build, so you'd have to re-grant permission each time. Sign with a stable identity
# (SIGN_IDENTITY) to keep the grant across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/SnapMark.app"

for ARCH in arm64 x86_64; do
    swift build -c "$CONFIG" --arch "$ARCH" >/dev/null
done
BIN_ARM="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/SnapMark"
BIN_X86="$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/SnapMark"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$BIN_ARM" "$BIN_X86" -output "$APP/Contents/MacOS/SnapMark"
strip -x "$APP/Contents/MacOS/SnapMark" 2>/dev/null || true
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "$IDENTITY" \
    --entitlements Support/SnapMark.entitlements "$APP"

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/SnapMark"
du -sh "$APP"
