#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-macos.sh
APP="build/Focus On.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(lipo -archs "$APP/Contents/MacOS/FocusOn" | tr ' ' '-')"
OUTPUT="build/Focus-On-${VERSION}-${ARCH}.dmg"
DMG_WORK="$(mktemp -d)"
trap 'rm -rf "$DMG_WORK"' EXIT
mkdir -p "$DMG_WORK/staging"

ditto "$APP" "$DMG_WORK/staging/Focus On.app"
ln -s /Applications "$DMG_WORK/staging/Applications"
codesign --verify --strict "$DMG_WORK/staging/Focus On.app"
hdiutil create -volname "Focus On" -srcfolder "$DMG_WORK/staging" \
  -format UDZO "$DMG_WORK/Focus On.dmg"
hdiutil verify "$DMG_WORK/Focus On.dmg"
mv -f "$DMG_WORK/Focus On.dmg" "$OUTPUT"

echo "Built: $PWD/$OUTPUT"
echo "此脚本不执行 Apple 公证；默认使用本地签名，适合测试分发。"
