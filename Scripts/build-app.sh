#!/bin/sh
# 构建 MiniBrowser.app：release 编译 → 打包（含图标）→ DEV X 签名 → 校验
set -eu
cd "$(dirname "$0")/.."

APP="MiniBrowser.app"
VERSION=$(Scripts/version.sh)

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MiniBrowser "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# 稳定的 DEV X 签名让覆盖安装保留已有权限；禁止回退为 ad-hoc。
if ! security find-certificate -c "DEV X" >/dev/null 2>&1; then
    echo "error: DEV X signing certificate not found" >&2
    exit 1
fi
codesign --force --sign "DEV X" "$APP"
codesign --verify --deep --strict "$APP"
codesign -dvv "$APP" 2>&1 | grep "Authority=DEV X"

echo "built $(pwd)/$APP"
