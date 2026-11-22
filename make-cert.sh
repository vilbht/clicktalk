#!/bin/bash
# One-time: create a self-signed code signing certificate in your login keychain.
# build.sh then signs with it, so the Input Monitoring and Accessibility grants
# survive rebuilds. Ad hoc signatures change on every build and lose the grants.
#
# Usage: ./make-cert.sh            (creates "Clicktalk Dev")
#        ./make-cert.sh "My Name"  (custom name; pass the same to CODESIGN_ID)
#
# macOS asks for your login password once, to trust the certificate for code signing.
set -euo pipefail

NAME="${1:-Clicktalk Dev}"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
EOF

# Use the system OpenSSL (LibreSSL). A Homebrew or conda OpenSSL 3 writes PKCS12 files
# with ciphers the macOS keychain importer rejects ("MAC verification failed").
OPENSSL=/usr/bin/openssl
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:clicktalk -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

KEYCHAIN="$(security default-keychain -d user | tr -d ' "')"
# -T lets codesign use the key without a prompt on every build. No other tool gets that
# access: anything else that wants the key has to ask you first.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P clicktalk -T /usr/bin/codesign >/dev/null
echo "Imported \"$NAME\" into $KEYCHAIN."
echo "Now trusting it for code signing. macOS will ask for your login password."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Done. ./build.sh will sign with \"$NAME\" from now on."
  echo "Grant Input Monitoring once more after the next build; it then sticks."
else
  echo "The identity is not valid for code signing yet. Open Keychain Access, find \"$NAME\","
  echo "double-click it, expand Trust, and set Code Signing to Always Trust."
  exit 1
fi
