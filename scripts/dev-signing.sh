#!/bin/bash
# Creates a local, self-signed code-signing identity ("Alt Right Local Signing").
#
# Why: with an ad-hoc signature the app's designated requirement is a cdhash, which
# changes on every rebuild — so every reinstall silently invalidates the Accessibility
# permission you granted. A certificate-based requirement stays the same across builds.
set -euo pipefail

IDENTITY="${IDENTITY:-Alt Right Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "==> Signing identity already present: $IDENTITY"
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cnf" >/dev/null 2>&1

# macOS' security tool cannot read OpenSSL 3's default PKCS#12 crypto, hence the legacy PBE.
openssl pkcs12 -export -out "$work/id.p12" -inkey "$work/key.pem" -in "$work/cert.pem" \
    -passout pass:altright -name "$IDENTITY" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1

security import "$work/id.p12" -k "$KEYCHAIN" -P altright \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> Created signing identity: $IDENTITY"
