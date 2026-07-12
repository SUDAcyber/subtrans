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
BUILD_BIN_DIR="$(dirname "$BUILD_BINARY")"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

# SwiftPM resource bundles are not embedded when only the executable is copied.
# Bundle.module needs these at runtime for the Typhoon installer and future assets.
while IFS= read -r -d '' RESOURCE_BUNDLE; do
  ditto "$RESOURCE_BUNDLE" "$APP_RESOURCES/$(basename "$RESOURCE_BUNDLE")"
done < <(find "$BUILD_BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

if [[ -n "${BUNDLE_WHISPER_MODEL_DIR:-}" ]]; then
  [[ -d "$BUNDLE_WHISPER_MODEL_DIR" ]] || {
    echo "BUNDLE_WHISPER_MODEL_DIR is not a directory: $BUNDLE_WHISPER_MODEL_DIR" >&2
    exit 2
  }
  mkdir -p "$APP_RESOURCES/WhisperModels"
  ditto "$BUNDLE_WHISPER_MODEL_DIR" "$APP_RESOURCES/WhisperModels/$(basename "$BUNDLE_WHISPER_MODEL_DIR")"
fi

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

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --options runtime --timestamp=none "$APP_BUNDLE"
else
  codesign --force --deep --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "WARNING: using ad-hoc signing; set CODE_SIGN_IDENTITY to a Developer ID Application identity for public distribution" >&2
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
fi

ditto "$APP_BUNDLE" "$FINAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_APP" "$ZIP_PATH"

mkdir -p "$DMG_STAGING"
ditto "$FINAL_APP" "$DMG_STAGING/$DISPLAY_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$DISPLAY_NAME $VERSION" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi
fi

(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")") >"$CHECKSUM_PATH"

echo "Release artifacts:"
echo "$FINAL_APP"
echo "$ZIP_PATH"
echo "$DMG_PATH"
echo "$CHECKSUM_PATH"
