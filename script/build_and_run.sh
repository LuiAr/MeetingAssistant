#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
SMOKE_SECONDS="${2:-3}"
APP_NAME="MeetingAssistant"
BUNDLE_ID="devswift.MeetingAssistant"
MIN_SYSTEM_VERSION="26.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_NAME="AppIcon"
SOURCE_ICON="$ROOT_DIR/app.icns"
SOURCE_ICONSET="$ROOT_DIR/app.iconset"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$SOURCE_ICON" ]]; then
  cp "$SOURCE_ICON" "$APP_RESOURCES/$ICON_NAME.icns"
elif [[ -d "$SOURCE_ICONSET" ]]; then
  iconutil -c icns "$SOURCE_ICONSET" -o "$APP_RESOURCES/$ICON_NAME.icns"
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
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>MeetingAssistant records microphone audio so local transcripts can include what you say in meetings.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
  <key>NSSystemAudioCaptureUsageDescription</key>
  <string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
</dict>
</plist>
PLIST

/usr/bin/codesign \
  --force \
  --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP_BUNDLE" >/dev/null

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_smoke_record() {
  /usr/bin/open -n "$APP_BUNDLE" --args --smoke-record "$SMOKE_SECONDS"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --smoke-record|smoke-record)
    rm -f /tmp/MeetingAssistant-smoke-record-result.json
    open_smoke_record
    sleep "$((SMOKE_SECONDS + 5))"
    if [[ -f /tmp/MeetingAssistant-smoke-record-result.json ]]; then
      cat /tmp/MeetingAssistant-smoke-record-result.json
      echo
    else
      echo "Smoke recording did not finish or no result file was written." >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--smoke-record seconds]" >&2
    exit 2
    ;;
esac
