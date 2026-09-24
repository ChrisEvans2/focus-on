#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm run build
swift build --package-path macos -c release --product FocusOn
BINARY_DIR="$(swift build --package-path macos -c release --show-bin-path)"
APP="build/Focus On.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Web"
# Replace the executable inode so an already running build is not modified in place.
cp "$BINARY_DIR/FocusOn" "$APP/Contents/MacOS/FocusOn.new"
mv -f "$APP/Contents/MacOS/FocusOn.new" "$APP/Contents/MacOS/FocusOn"
cp macos/Info.plist "$APP/Contents/Info.plist"
# Replace only generated web resources so removed assets cannot linger in the bundle.
rsync -a --delete dist/ "$APP/Contents/Resources/Web/"
codesign --force --sign "${FOCUS_SIGN_IDENTITY:--}" --options runtime --entitlements macos/FocusOn.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Built: $PWD/$APP"
