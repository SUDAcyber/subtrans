#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.1.0}"
APP_NAME="SubtitleForge"
DISPLAY_NAME="SUDA字幕翻译助手"
BUNDLE_ID="com.subtitleforge.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/release"
WORK_DIR="$DIST_DIR/work"
APP_BUNDLE="$WORK_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
COMMIT_SHA="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

FINAL_APP="$DIST_DIR/$DISPLAY_NAME.app"
ZIP_PATH="$DIST_DIR/$DISPLAY_NAME-$VERSION-macOS.zip"
DMG_PATH="$DIST_DIR/$DISPLAY_NAME-$VERSION-macOS.dmg"
CHECKSUM_PATH="$DIST_DIR/$DISPLAY_NAME-$VERSION-checksums.txt"
DMG_STAGING="$WORK_DIR/dmg"

cd "$ROOT_DIR"

trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$WORK_DIR" "$FINAL_APP" "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>SUDAGitCommit</key>
  <string>$COMMIT_SHA</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - --options runtime "$APP_BUNDLE"
  codesign --verify --deep --strict "$APP_BUNDLE"
fi

ditto "$APP_BUNDLE" "$FINAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_APP" "$ZIP_PATH"

mkdir -p "$DMG_STAGING"
ditto "$FINAL_APP" "$DMG_STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")") >"$CHECKSUM_PATH"

echo "Release artifacts:"
echo "$FINAL_APP"
echo "$ZIP_PATH"
echo "$DMG_PATH"
echo "$CHECKSUM_PATH"
