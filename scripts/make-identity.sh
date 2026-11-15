#!/usr/bin/env bash
# One-time: create a self-signed code-signing identity in the login keychain.
# TCC permission grants then survive every rebuild — they bind to this cert.
# After running, trust the cert in Keychain Access:
#   login -> Certificates -> custos-dev -> Trust -> Code Signing -> Always Trust
set -euo pipefail

IDENTITY="custos-dev"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "identity '$IDENTITY' already exists — nothing to do"
    exit 0
fi

openssl req -newkey rsa:2048 -nodes \
    -keyout "$TMP/custos-dev.key" -x509 -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=codeSigning" \
    -out "$TMP/custos-dev.pem"

openssl pkcs12 -export -name "$IDENTITY" \
    -inkey "$TMP/custos-dev.key" -in "$TMP/custos-dev.pem" \
    -passout pass: -out "$TMP/custos-dev.p12"

security import "$TMP/custos-dev.p12" -P "" \
    -k "$HOME/Library/Keychains/login.keychain-db" -T /usr/bin/codesign
# key + cert die with the temp dir — the keychain copy is the surviving one

echo "created '$IDENTITY' in login keychain (valid 10 years)"
echo "trust it in Keychain Access, then verify:"
echo "security find-identity -v -p codesigning"