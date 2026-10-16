#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/repo-build"
APP_DIR="$SCRIPT_DIR/outputs/QuickChat.app"

rm -rf "$BUILD_DIR" "$APP_DIR"
mkdir -p "$BUILD_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" \
    -module-cache-path "$BUILD_DIR/module-cache-$arch" \
    "$SCRIPT_DIR/QuickChat.swift" \
    -o "$BUILD_DIR/QuickChat-$arch" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon
done
xcrun lipo -create "$BUILD_DIR/QuickChat-arm64" "$BUILD_DIR/QuickChat-x86_64" \
  -output "$APP_DIR/Contents/MacOS/QuickChat"
ARCHITECTURES=" $(xcrun lipo -archs "$APP_DIR/Contents/MacOS/QuickChat") "
[[ "$ARCHITECTURES" == *" arm64 "* && "$ARCHITECTURES" == *" x86_64 "* ]]

cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"

rsvg-convert -w 1024 -h 1024 "$SCRIPT_DIR/icon.svg" -o "$BUILD_DIR/icon-1024.png"
ICONSET_DIR="$BUILD_DIR/QuickChat.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD_DIR/icon-1024.png" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$BUILD_DIR/icon-1024.png" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/QuickChat.icns"
sips -s format png "$APP_DIR/Contents/Resources/QuickChat.icns" --out "$BUILD_DIR/icon-check.png" >/dev/null

if [[ -n "${QUICKCHAT_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$QUICKCHAT_SIGNING_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
