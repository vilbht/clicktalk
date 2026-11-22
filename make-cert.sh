#!/bin/bash
# One-time: create a self-signed code signing certificate in your login keychain.
# build.sh then signs with it, so the Input Monitoring and Accessibility grants
# survive rebuilds. Ad hoc signatures change on every build and lose the grants.
#
# Usage: ./make-cert.sh            (creates "EucLink Dev")
#        ./make-cert.sh "My Name"  (custom name; pass the same to CODESIGN_ID)
#
# macOS asks for your login password once, to trust the certificate for code signing.
#
# The key is imported without any app on its "always allow" list, so every use asks you.
# When build.sh signs, click Allow. Never click Always Allow: that would let any program
# running under your account sign itself as EucLink and inherit its permissions.
set -euo pipefail

NAME="${1:-EucLink Dev}"

check_access() {
  echo
  echo "Check the key's access list once:"
  echo "  1. Open Keychain Access, select the login keychain and search for \"$NAME\"."
  echo "  2. Expand the certificate, double-click the private key, open Access Control."
  echo "  3. \"Always allow access by these applications\" must be empty. Remove any entry"
  echo "     with the minus button, keep \"Confirm before allowing access\", Save Changes."
  echo "Keys made by older versions of this script listed codesign and security there."
}

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Identity \"$NAME\" already exists, so nothing was created."
  check_access
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
  -out "$TMP/id.p12" -passout pass:euclink -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1

KEYCHAIN="$(security default-keychain -d user | tr -d ' "')"
# No -T: a trusted-application entry trusts a tool, not whoever runs it, so any program
# could sign as EucLink through it without asking. Without one, every use prompts.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P euclink >/dev/null
echo "Imported \"$NAME\" into $KEYCHAIN."
echo "Now trusting it for code signing. macOS will ask for your login password."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Done. ./build.sh will sign with \"$NAME\" from now on."
  echo "Each build asks to use the key: click Allow, never Always Allow."
  echo "Grant Input Monitoring once more after the next build; it then sticks."
  check_access
else
  echo "The identity is not valid for code signing yet. Open Keychain Access, find \"$NAME\","
  echo "double-click it, expand Trust, and set Code Signing to Always Trust."
  exit 1
fi
