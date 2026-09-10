#!/bin/bash
# 创建本地自签名代码签名证书 "DEV X" 并导入登录钥匙串
# 无需 Apple 开发者账号；提供稳定签名身份（TCC 权限等不会因重编译失效）
set -e

IDENTITY="DEV X"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 已存在则跳过
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "签名身份 '$IDENTITY' 已存在，跳过"
    exit 0
fi

openssl genrsa -out "$WORK/key.pem" 2048 2>/dev/null
openssl req -x509 -new -key "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=digitalSignature" \
    -addext "extendedKeyUsage=codeSigning"
# -legacy: 兼容 macOS security 可识别的 PKCS12 算法
openssl pkcs12 -export -legacy -out "$WORK/cert.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -password pass:minibrowser
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P minibrowser -T /usr/bin/codesign

security find-certificate -c "$IDENTITY" >/dev/null && echo "已创建并导入: $IDENTITY"
