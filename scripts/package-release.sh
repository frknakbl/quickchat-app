#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOSITORY="${1:-frknakbl/quickchat-app}"
[[ "$REPOSITORY" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || { echo "GitHub deposu owner/repository biçiminde olmalı." >&2; exit 1; }
APP="$ROOT/outputs/QuickChat.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
MINIMUM_OS="$(plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist")"
[[ "$MINIMUM_OS" == "13.0" ]] || { echo "Beklenmeyen macOS alt sınırı: $MINIMUM_OS" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
ARCHITECTURES=" $(xcrun lipo -archs "$APP/Contents/MacOS/QuickChat") "
[[ "$ARCHITECTURES" == *" arm64 "* && "$ARCHITECTURES" == *" x86_64 "* ]]

RELEASE_DIR="$ROOT/outputs/releases"
TAP_DIR="$ROOT/distribution/homebrew-tap"
mkdir -p "$RELEASE_DIR" "$TAP_DIR/Casks"
ARCHIVE="QuickChat-$VERSION-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$ARCHIVE"
CHECKSUM="$(shasum -a 256 "$RELEASE_DIR/$ARCHIVE" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$CHECKSUM" "$ARCHIVE" > "$RELEASE_DIR/$ARCHIVE.sha256"

cat > "$TAP_DIR/Casks/quickchat.rb" <<EOF
cask "quickchat" do
  version "$VERSION"
  sha256 "$CHECKSUM"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/QuickChat-#{version}-universal.zip"
  name "QuickChat"
  desc "Floating ChatGPT window with a global keyboard shortcut"
  homepage "https://github.com/$REPOSITORY"

  depends_on macos: :ventura

  app "QuickChat.app"

  uninstall quit: "local.tools.QuickChat"

  caveats <<~EOS
    This preview is ad-hoc signed and has not been notarized by Apple.
    macOS may block the first launch. See the installation notes on the homepage.
  EOS
end
EOF
printf 'Arşiv: %s\nSHA-256: %s\nCask: %s\n' "$RELEASE_DIR/$ARCHIVE" "$CHECKSUM" "$TAP_DIR/Casks/quickchat.rb"
