#!/usr/bin/env bash
set -euo pipefail

# Builds a distributable, release-configuration MeetingAssistant.app, ad-hoc signs it with the
# release bundle identifier (distinct from the dev build so their privacy permissions never
# collide), and zips it for upload to a GitHub Release.
#
# Usage:
#   ./script/package_release.sh            # version defaults to 1.0.0
#   ./script/package_release.sh 1.2.0      # set the marketing version

APP_NAME="MeetingAssistant"
BUNDLE_ID="com.devswift.MeetingAssistant"
MIN_SYSTEM_VERSION="15.0"
SHORT_VERSION="${1:-1.0.0}"
BUILD_VERSION="1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT_DIR/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$SHORT_VERSION.zip"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

if [[ -f "$ROOT_DIR/app.icns" ]]; then
  cp "$ROOT_DIR/app.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -d "$ROOT_DIR/app.iconset" ]]; then
  iconutil -c icns "$ROOT_DIR/app.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
fi

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>MeetingAssistant records microphone audio so local transcripts can include what you say in meetings.</string>
  <key>NSScreenCaptureUsageDescription</key><string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
  <key>NSSystemAudioCaptureUsageDescription</key><string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
</dict>
</plist>
PLIST

codesign --force --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "Built $APP"
echo "Zipped $ZIP"
echo "Open it with:  open \"$APP\""
