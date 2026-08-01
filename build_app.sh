#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="LazyMouse"
BUNDLE_ID="com.engbyume.LazyMouse"
APP_PATH="$ROOT_DIR/.build/lazymouse-package/$APP_NAME.app"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_SOURCE="$ROOT_DIR/assets/AppIcon.svg"
MENU_ICON_SOURCE="$ROOT_DIR/assets/AppIconMenu.svg"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_PATH="$INSTALL_DIR/$APP_NAME.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-LazyMouse Local Development}"
trap 'rm -rf "$APP_PATH" "$ICONSET_DIR"' EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command swift
require_command rsvg-convert
require_command sips
require_command iconutil
require_command codesign
require_command security

SIGNING_ARGUMENT="-"
SIGNING_MATCH_COUNT="$(security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null | awk -v identity="$SIGNING_IDENTITY" 'index($0, "\"" identity "\"") { count += 1 } END { print count + 0 }')"
if [[ "$SIGNING_MATCH_COUNT" == "1" ]]; then
  SIGNING_ARGUMENT="$SIGNING_IDENTITY"
  echo "Using stable signing identity: $SIGNING_IDENTITY"
elif [[ "${ALLOW_ADHOC_SIGNING:-0}" == "1" ]]; then
  echo "Stable signing identity unavailable; using an ad-hoc signature by explicit request." >&2
else
  echo "A unique stable signing identity named '$SIGNING_IDENTITY' is required for Input Monitoring." >&2
  echo "Create or select that identity, or set SIGNING_IDENTITY to one valid identity." >&2
  exit 1
fi

cd "$ROOT_DIR"
echo "Building $APP_NAME in release mode..."
# Swift 6.3 can hit a release-optimizer module deserialization bug when
# importing LazyMouseCore's CoreGraphics geometry types. Keep the packaged
# utility unoptimized until that toolchain issue is resolved.
swift build -c release -Xswiftc -Onone

rm -rf "$APP_PATH" "$ICONSET_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$ICONSET_DIR"

ICON_PNG="$ICONSET_DIR/icon_512x512@2x.png"
rsvg-convert -w 1024 -h 1024 "$ICON_SOURCE" -o "$ICON_PNG"
rsvg-convert -w 128 -h 128 "$MENU_ICON_SOURCE" -o "$APP_PATH/Contents/Resources/AppIconMenu.png"

make_icon_size() {
  local size="$1"
  local name="$2"
  sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon_size 16 icon_16x16.png
make_icon_size 32 icon_16x16@2x.png
make_icon_size 32 icon_32x32.png
make_icon_size 64 icon_32x32@2x.png
make_icon_size 128 icon_128x128.png
make_icon_size 256 icon_128x128@2x.png
make_icon_size 256 icon_256x256.png
make_icon_size 512 icon_256x256@2x.png
make_icon_size 512 icon_512x512.png
iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_PATH/Contents/MacOS/$APP_NAME"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>LazyMouse</string>
    <key>CFBundleExecutable</key>
    <string>LazyMouse</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LazyMouse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>LazyMouse needs pointing-device input access to keep the overlay cursor independent from the normal macOS cursor.</string>
</dict>
</plist>
PLIST

echo "Signing local app bundle..."
codesign --force --deep --sign "$SIGNING_ARGUMENT" "$APP_PATH" >/dev/null
codesign --verify --deep --strict "$APP_PATH"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

echo "Installed: $INSTALL_PATH"
if [[ "${1:-}" == "--open" ]]; then
  open "$INSTALL_PATH"
  echo "Launched: $INSTALL_PATH"
fi
