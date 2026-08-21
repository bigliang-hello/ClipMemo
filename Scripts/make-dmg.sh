#!/bin/bash
# Build a Release ClipMemo.app and pack it into a DMG with an /Applications
# symlink. Usage: ./Scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="ClipMemo.xcodeproj"
SCHEME="ClipMemo"
CONFIG="Release"
OUT="build"

echo "==> Building ${CONFIG}…"
DERIVED="$OUT/DerivedData"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build >/dev/null

APP="$DERIVED/Build/Products/$CONFIG/ClipMemo.app"
[ -d "$APP" ] || { echo "App not found at $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/ClipMemo-$VERSION.dmg"
rm -rf "$OUT/staging"
mkdir -p "$OUT/staging"
cp -R "$APP" "$OUT/staging/ClipMemo.app"
ln -sfn /Applications "$OUT/staging/Applications"

echo "==> Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "ClipMemo" -srcfolder "$OUT/staging" -ov \
  -format UDZO "$DMG" >/dev/null
rm -rf "$OUT/staging"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
