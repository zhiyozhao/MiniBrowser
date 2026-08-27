#!/bin/bash
# 构建 MiniBrowser.app：release 编译 → 打包（含图标）→ 代码签名 → 校验
# 用法: Scripts/build-app.sh
set -e
cd "$(dirname "$0")/.."

APP="MiniBrowser.app"
IDENTITY="MiniBrowser Development"   # 本地自签名证书（Scripts/create-signing-cert.sh 创建）

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MiniBrowser "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "警告: 未找到签名身份 '$IDENTITY'，回退为 ad-hoc 签名"
    echo "      可运行 Scripts/create-signing-cert.sh 创建"
    codesign --force --sign - "$APP"
fi
codesign -v "$APP"

echo "已生成并签名: $(pwd)/$APP"
