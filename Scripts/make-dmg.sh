#!/bin/bash
# Build a Release ClipMemo.app and pack it into a DMG with an /Applications
# symlink. Usage: ./Scripts/make-dmg.sh
#
# ICLOUD=1 ./Scripts/make-dmg.sh
#   Signs with the iCloud entitlements (CloudKit container) instead of the
#   plain ones — requires a PAID Apple Developer team; free personal teams
#   can't register iCloud containers and the build will fail on signing.
#
# NOTARIZE=1 ./Scripts/make-dmg.sh          (可与 ICLOUD=1 组合)
#   Developer ID 签名 + 公证 + 装订(app 和 DMG 都做)。首次使用前:
#     1. Xcode → Settings → Accounts → Manage Certificates → +
#        创建 "Developer ID Application" 证书(需付费账号)
#     2. appleid.apple.com → 登录与安全 → App 专用密码,生成一个
#     3. xcrun notarytool store-credentials ClipMemo \
#          --apple-id <你的AppleID> --team-id <团队ID> --password <专用密码>
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="ClipMemo.xcodeproj"
SCHEME="ClipMemo"
CONFIG="Release"
OUT="build"

echo "==> Building ${CONFIG}…"
DERIVED="$OUT/DerivedData"
# Entitlements follow the ICLOUD flag in every build mode.
if [ "${ICLOUD:-0}" = "1" ]; then
  ENTITLEMENTS="ClipMemo/Resources/ClipMemo-iCloud.entitlements"
else
  ENTITLEMENTS="ClipMemo/Resources/ClipMemo.entitlements"
fi
if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Developer ID build (for notarization)"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ICLOUD_ENTITLEMENTS_PATH="$ENTITLEMENTS" \
    build >/dev/null
else
  if [ "${ICLOUD:-0}" = "1" ]; then
    echo "==> iCloud build (CloudKit entitlements)"
  fi
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
    ICLOUD_ENTITLEMENTS_PATH="$ENTITLEMENTS" \
    build >/dev/null
fi

APP="$DERIVED/Build/Products/$CONFIG/ClipMemo.app"
[ -d "$APP" ] || { echo "App not found at $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/ClipMemo-$VERSION.dmg"
rm -rf "$OUT/staging"
mkdir -p "$OUT/staging"
cp -R "$APP" "$OUT/staging/ClipMemo.app"
ln -sfn /Applications "$OUT/staging/Applications"

if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Notarizing app (this usually takes a few minutes)…"
  xcrun notarytool submit "$OUT/staging/ClipMemo.app" \
    --keychain-profile ClipMemo --wait
  xcrun notarytool staple "$OUT/staging/ClipMemo.app"
fi

echo "==> Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "ClipMemo" -srcfolder "$OUT/staging" -ov \
  -format UDZO "$DMG" >/dev/null

if [ "${NOTARIZE:-0}" = "1" ]; then
  echo "==> Notarizing DMG…"
  xcrun notarytool submit "$DMG" --keychain-profile ClipMemo --wait
  xcrun notarytool staple "$DMG"
fi

rm -rf "$OUT/staging"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
