#!/bin/bash
# Create a self-signed code signing identity in the login keychain for local development.
# It is not trusted system-wide (and does not need to be); it only gives every build the same
# designated requirement, so Accessibility / Screen Recording grants survive rebuilds.
set -euo pipefail
NAME="WindowPilot Local Signing"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "Identity already exists: $NAME"
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<EOF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Created: $NAME"
echo "The first codesign may ask for keychain access; choose \"Always Allow\"."
