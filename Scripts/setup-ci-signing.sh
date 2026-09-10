#!/bin/bash
# 把 "DEV X" 签名身份导出并设置为 GitHub Actions secrets
# 供 release workflow 在 CI 中用同一身份签名（brew 更新后 TCC 权限不丢）
# 用法: Scripts/setup-ci-signing.sh   （会提示输入钥匙串密码，并可能弹出"允许访问"对话框）
set -e

IDENTITY="DEV X"
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
# 证书的 friendlyName 是标签名；私钥的 friendlyName 是哈希，靠 localKeyID 与证书配对
target_keyid = cert = None
keys = {}
for b in blocks:
    m_fn = re.search(r'friendlyName: (.+)', b)
    m_kid = re.search(r'localKeyID: (.+)', b)
    m_cert = re.search(r'(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)', b, re.S)
    m_key = re.search(r'(-----BEGIN (?:RSA )?PRIVATE KEY-----.*?-----END (?:RSA )?PRIVATE KEY-----)', b, re.S)
    kid = ' '.join(m_kid.group(1).split()) if m_kid else None
    if m_cert and m_fn and m_fn.group(1).strip() == 'DEV X':
        cert = m_cert.group(1)
        target_keyid = kid
    if m_key and kid:
        keys[kid] = m_key.group(1)
assert cert, '未找到 DEV X 证书'
assert target_keyid in keys, '未找到对应私钥'
open(f'{work}/cert.pem', 'w').write(cert + '\n')
open(f'{work}/key.pem', 'w').write(keys[target_keyid] + '\n')
print('提取成功')
EOF

openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/mb-dev.p12" -password "pass:$P12_PW" -name "$IDENTITY"

echo "==> 设置 GitHub secrets (repo: $REPO)"
gh secret set MINIBROWSER_DEV_P12_BASE64 --repo "$REPO" < <(base64 -i "$WORK/mb-dev.p12")
echo "$P12_PW" | gh secret set MINIBROWSER_DEV_P12_PASSWORD --repo "$REPO"

echo "==> 完成。已设置 secrets: MINIBROWSER_DEV_P12_BASE64 / MINIBROWSER_DEV_P12_PASSWORD"
