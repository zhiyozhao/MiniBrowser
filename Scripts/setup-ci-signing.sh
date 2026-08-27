#!/bin/bash
# 把 "MiniBrowser Development" 签名身份导出并设置为 GitHub Actions secrets
# 供 release workflow 在 CI 中用同一身份签名（brew 更新后 TCC 权限不丢）
# 用法: Scripts/setup-ci-signing.sh   （会提示输入钥匙串密码，并可能弹出"允许访问"对话框）
set -e

IDENTITY="MiniBrowser Development"
REPO="zhiyozhao/MiniBrowser"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

EXPORT_PW="mb-export-tmp"
P12_PW="$(openssl rand -hex 12)"

echo "==> 导出钥匙串身份（需要输入钥匙串密码）"
security unlock-keychain ~/Library/Keychains/login.keychain-db
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P "$EXPORT_PW" -o "$WORK/all.p12"

echo "==> 提取 $IDENTITY"
openssl pkcs12 -legacy -in "$WORK/all.p12" -out "$WORK/all.pem" -nodes -password "pass:$EXPORT_PW" 2>/dev/null
python3 - "$WORK" <<'EOF'
import re, sys
work = sys.argv[1]
pem = open(f'{work}/all.pem').read()
blocks = re.split(r'(?=Bag Attributes)', pem)
cert = key = None
for b in blocks:
    if 'MiniBrowser Development' not in b:
        continue
    m_cert = re.search(r'(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)', b, re.S)
    m_key = re.search(r'(-----BEGIN (?:RSA )?PRIVATE KEY-----.*?-----END (?:RSA )?PRIVATE KEY-----)', b, re.S)
    if m_cert: cert = m_cert.group(1)
    if m_key: key = m_key.group(1)
assert cert and key, '未找到 MiniBrowser Development 身份'
open(f'{work}/cert.pem', 'w').write(cert + '\n')
open(f'{work}/key.pem', 'w').write(key + '\n')
print('提取成功')
EOF

openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/mb-dev.p12" -password "pass:$P12_PW" -name "$IDENTITY"

echo "==> 设置 GitHub secrets (repo: $REPO)"
gh secret set MINIBROWSER_DEV_P12_BASE64 --repo "$REPO" < <(base64 -i "$WORK/mb-dev.p12")
echo "$P12_PW" | gh secret set MINIBROWSER_DEV_P12_PASSWORD --repo "$REPO"

echo "==> 完成。已设置 secrets: MINIBROWSER_DEV_P12_BASE64 / MINIBROWSER_DEV_P12_PASSWORD"
