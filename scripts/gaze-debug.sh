#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --package-path macos -c debug --product FocusGazeDebug
BIN_DIR="$(swift build --package-path macos -c debug --show-bin-path)"
APP="build/Focus On Gaze Debug.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/FocusGazeDebug" "$APP/Contents/MacOS/FocusGazeDebug.new"
mv -f "$APP/Contents/MacOS/FocusGazeDebug.new" "$APP/Contents/MacOS/FocusGazeDebug"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.focuson.gazedebug</string>
<key>CFBundleName</key><string>Focus On Gaze Debug</string>
<key>CFBundleExecutable</key><string>FocusGazeDebug</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>在本机显示摄像头画面及眼睛和瞳孔检测标记，帮助调试视线估计。画面不保存、不上传。</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements macos/FocusOn.entitlements "$APP"
codesign --verify --strict "$APP"
if [[ "${1:-}" == "--build-only" ]]; then
  echo "Built: $PWD/$APP"
elif [[ "${1:-}" == "--smoke-test" ]]; then
  "$APP/Contents/MacOS/FocusGazeDebug" --smoke-test "$PWD/artifacts/gaze-debug"
else
  echo '在新窗口中点击「开始摄像头」。关闭窗口或按 ⌘Q 退出；仅停止终端命令不会关闭摄像头窗口。'
  open -W -n "$APP"
fi
