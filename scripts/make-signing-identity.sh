#!/bin/bash
# One-time: creates a free, self-signed code-signing certificate in its own keychain at
# ~/.fretos-signing. make-app.sh signs with it when present, so every FretOS release has the
# same identity and macOS keeps the Accessibility permission across updates.
# Back up ~/.fretos-signing: if it's lost, users must re-allow FretOS once after the next update.
set -euo pipefail
openssl() { /usr/bin/openssl "$@"; }   # macOS LibreSSL: its .p12 files import cleanly
DIR="$HOME/.fretos-signing"
NAME="FretOS Code Signing"
[ -f "$DIR/identity" ] && { echo "Already set up: $(cat "$DIR/identity")"; exit 0; }
mkdir -p "$DIR"; chmod 700 "$DIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS="$(openssl rand -hex 24)"
echo "$PASS" > "$DIR/password"; chmod 600 "$DIR/password"

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/id.p12" -passout pass:"$PASS" 2>/dev/null

KC="$DIR/signing.keychain-db"
security create-keychain -p "$PASS" "$KC"
security set-keychain-settings "$KC"            # no auto-lock timeout
security unlock-keychain -p "$PASS" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
HASH="$(openssl x509 -in "$TMP/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
echo "$HASH" > "$DIR/identity"
echo "✓ signing identity $HASH in $KC"
