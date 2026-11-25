#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="RightMenuPlus.app"
APP_PATH="$BUILD_DIR/$APP_NAME"
EXT_NAME="RightMenuPlusExtension.appex"
EXT_PATH="$APP_PATH/Contents/PlugIns/$EXT_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos13.0"

echo "==> 清理旧构建产物..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$EXT_PATH/Contents/MacOS"

echo "==> 生成应用图标..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
swift "$PROJECT_DIR/Scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

echo "==> 编译宿主应用 RightMenuPlus ($TARGET)..."
swiftc -O -swift-version 5 \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -framework Cocoa \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  "$PROJECT_DIR/Sources/Shared/ActionProtocol.swift" \
  "$PROJECT_DIR/Sources/App/OfficeTemplates.swift" \
  "$PROJECT_DIR/Sources/App/ActionExecutor.swift" \
  "$PROJECT_DIR/Sources/App/RightMenuPlusApp.swift" \
  -o "$APP_PATH/Contents/MacOS/RightMenuPlus"

echo "==> 编译 FinderSync 扩展 ($TARGET)..."
swiftc -O -swift-version 5 \
  -parse-as-library \
  -application-extension \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -module-name RightMenuPlusExtension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework Cocoa \
  -framework Foundation \
  -framework FinderSync \
  "$PROJECT_DIR/Sources/Shared/ActionProtocol.swift" \
  "$PROJECT_DIR/Sources/Extension/FinderSync.swift" \
  -o "$EXT_PATH/Contents/MacOS/RightMenuPlusExtension"

echo "==> 复制 Info.plist..."
cp "$PROJECT_DIR/Resources/App-Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Extension-Info.plist" "$EXT_PATH/Contents/Info.plist"

echo "==> 代码签名 (Ad-Hoc)..."
codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/Extension.entitlements" -s - "$EXT_PATH/Contents/MacOS/RightMenuPlusExtension"
codesign --force --options runtime --entitlements "$PROJECT_DIR/Resources/Extension.entitlements" -s - "$EXT_PATH"
codesign --force --options runtime -s - "$APP_PATH/Contents/MacOS/RightMenuPlus"
codesign --force --options runtime -s - "$APP_PATH"

echo "==> 安装到 $INSTALL_PATH..."
pkill -x RightMenuPlus 2>/dev/null || true
pkill -x RightMenuPlusExtension 2>/dev/null || true
rm -rf "$INSTALL_PATH"
ditto "$APP_PATH" "$INSTALL_PATH"

echo "==> 注册系统服务与 Finder 扩展..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_PATH"
pluginkit -a "$INSTALL_PATH/Contents/PlugIns/$EXT_NAME"
pluginkit -e use -i com.local.RightMenuPlus.FinderSync || true

echo "==> 配置并启用开机静默自启 (LaunchAgent)..."
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="$LAUNCH_AGENTS_DIR/com.local.RightMenuPlus.plist"
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENT_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.RightMenuPlus</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/RightMenuPlus.app/Contents/MacOS/RightMenuPlus</string>
        <string>--background</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
UID_NUM="$(id -u)"
launchctl bootout "gui/${UID_NUM}/com.local.RightMenuPlus" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "$LAUNCH_AGENT_PLIST"

echo "==> 当前扩展状态："
pluginkit -m -v -i com.local.RightMenuPlus.FinderSync || true
echo "✅ 构建并安装完成：$INSTALL_PATH"
