#!/usr/bin/env bash
set -euo pipefail

# Builds the Phase 1 hybrid spike: the Swift capture/permission sidecar, the React frontend,
# and the Tauri (Rust) shell. Stages them into a single .app, embeds the sidecar, and ad-hoc
# co-signs inner-then-outer with pinned identifiers and designated requirements, mirroring
# script/package_release.sh in the native app. Both bundle identifiers are deliberately
# distinct from the dev (devswift.MeetingAssistant) and release (com.devswift.MeetingAssistant)
# identities so TCC privacy permissions never collide.
#
# Usage:
#   ./rebuild/scripts/build_and_run.sh           # build, sign, launch
#   ./rebuild/scripts/build_and_run.sh build     # build and sign only, do not launch

MODE="${1:-run}"

APP_DISPLAY_NAME="MeetingAssistant Rebuild"
APP_BINARY_NAME="MeetingAssistantRebuild"
APP_BUNDLE_ID="com.devswift.MeetingAssistant.rebuild"
SIDECAR_BUNDLE_ID="com.devswift.MeetingAssistant.rebuild.sidecar"
SIDECAR_NAME="meetingcore-sidecar"
MIN_SYSTEM_VERSION="15.0"
SHORT_VERSION="0.1.0"
BUILD_VERSION="1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REBUILD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$REBUILD_DIR/.." && pwd)"

SIDECAR_DIR="$REBUILD_DIR/sidecar"
APP_DIR="$REBUILD_DIR/app"
TAURI_DIR="$APP_DIR/src-tauri"
DIST_DIR="$REBUILD_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

require() {
  command -v "$1" >/dev/null 2>&1 || { echo "error: \"$1\" is required but was not found in PATH." >&2; exit 1; }
}

require swift
require cargo
require npm

pkill -x "$APP_BINARY_NAME" >/dev/null 2>&1 || true
pkill -x "$SIDECAR_NAME" >/dev/null 2>&1 || true

echo "==> Building the Swift sidecar (release)"
( cd "$SIDECAR_DIR" && swift build -c release )
SIDECAR_BINARY="$(cd "$SIDECAR_DIR" && swift build -c release --show-bin-path)/$SIDECAR_NAME"

echo "==> Installing and building the React frontend"
( cd "$APP_DIR" && npm install && npm run build )

echo "==> Preparing the app icon"
mkdir -p "$TAURI_DIR/icons"
if [[ -f "$REPO_ROOT/app.icns" ]]; then
  cp "$REPO_ROOT/app.icns" "$TAURI_DIR/icons/icon.icns"
elif [[ -d "$REPO_ROOT/app.iconset" ]]; then
  iconutil -c icns "$REPO_ROOT/app.iconset" -o "$TAURI_DIR/icons/icon.icns"
fi
# Tauri's generate_context! embeds a default window icon from icons/icon.png and requires it
# to be true RGBA. The repo iconset PNGs are opaque without an alpha channel, so re-encode as
# RGBA with a small AppKit converter, falling back to sips if that fails.
ICON_PNG_SOURCE="$REPO_ROOT/app.iconset/icon_512x512@2x.png"
[[ -f "$ICON_PNG_SOURCE" ]] || ICON_PNG_SOURCE="$REPO_ROOT/app.iconset/icon_512x512.png"
ICON_CONVERTER="$(mktemp -t maicon).swift"
cat >"$ICON_CONVERTER" <<'SWIFT'
import AppKit
let args = CommandLine.arguments
guard args.count >= 3,
      let image = NSImage(contentsOfFile: args[1]),
      let tiff = image.tiffRepresentation,
      let source = NSBitmapImageRep(data: tiff) else { exit(1) }
let width = source.pixelsWide
let height = source.pixelsHigh
guard let out = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
out.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current?.imageInterpolation = .high
source.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
guard let data = out.representation(using: .png, properties: [:]) else { exit(1) }
do { try data.write(to: URL(fileURLWithPath: args[2])) } catch { exit(1) }
SWIFT
swift "$ICON_CONVERTER" "$ICON_PNG_SOURCE" "$TAURI_DIR/icons/icon.png" \
  || sips -s format png "$TAURI_DIR/icons/icon.icns" --out "$TAURI_DIR/icons/icon.png" >/dev/null
rm -f "$ICON_CONVERTER"

echo "==> Building the Tauri (Rust) shell (release)"
( cd "$TAURI_DIR" && cargo build --release --features custom-protocol )
APP_BUILD_BINARY="$TAURI_DIR/target/release/meetingassistant-rebuild"

echo "==> Staging $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$APP_BUILD_BINARY" "$APP_MACOS/$APP_BINARY_NAME"
cp "$SIDECAR_BINARY" "$APP_MACOS/$SIDECAR_NAME"
chmod +x "$APP_MACOS/$APP_BINARY_NAME" "$APP_MACOS/$SIDECAR_NAME"
if [[ -f "$TAURI_DIR/icons/icon.icns" ]]; then
  cp "$TAURI_DIR/icons/icon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_BINARY_NAME</string>
  <key>CFBundleIdentifier</key><string>$APP_BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleName</key><string>$APP_DISPLAY_NAME</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>MeetingAssistant records microphone audio so local transcripts can include what you say in meetings.</string>
  <key>NSScreenCaptureUsageDescription</key><string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
  <key>NSSystemAudioCaptureUsageDescription</key><string>MeetingAssistant captures system audio from meeting apps and browsers to transcribe remote participants.</string>
</dict>
</plist>
PLIST

echo "==> Co-signing the sidecar (inner) as $SIDECAR_BUNDLE_ID"
codesign --force --sign - \
  --identifier "$SIDECAR_BUNDLE_ID" \
  --requirements "=designated => identifier \"$SIDECAR_BUNDLE_ID\"" \
  "$APP_MACOS/$SIDECAR_NAME"

echo "==> Co-signing the app (outer) as $APP_BUNDLE_ID"
codesign --force --sign - \
  --identifier "$APP_BUNDLE_ID" \
  --requirements "=designated => identifier \"$APP_BUNDLE_ID\"" \
  "$APP_BUNDLE"

echo
echo "==> codesign verification (app)"
codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
echo
echo "==> codesign verification (sidecar)"
codesign -dv --verbose=4 "$APP_MACOS/$SIDECAR_NAME" 2>&1 | sed 's/^/    /'
echo

echo "Built $APP_BUNDLE"

case "$MODE" in
  run)
    echo "==> Launching"
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  build)
    echo "Skipping launch (build mode). Open it with: open \"$APP_BUNDLE\""
    ;;
  *)
    echo "usage: $0 [run|build]" >&2
    exit 2
    ;;
esac
