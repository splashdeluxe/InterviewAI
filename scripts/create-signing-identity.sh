#!/bin/bash
# One-time setup: a self-signed code-signing identity for InterviewAI,
# in your login keychain. Run this once in Terminal:
#
#     bash scripts/create-signing-identity.sh
#
# Why: macOS ties permission grants (Screen Recording, Microphone) to
# the app's signing identity. Ad hoc builds get a new identity on every
# rebuild, so macOS asks again even though you already allowed it. With
# this identity, build.sh signs every build the same way and the grants
# stick. The first time codesign uses the new key, macOS may ask for
# your keychain password: choose Always Allow.
set -euo pipefail

NAME="InterviewAI Local Signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Already set up: '$NAME' exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Creating the certificate..."
if ! openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -days 3650 -nodes -subj "/CN=$NAME" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null; then
    # Older openssl without -addext support: plain certificate still works.
    openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
        -days 3650 -nodes -subj "/CN=$NAME"
fi

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/identity.p12" -passout pass:interviewai -name "$NAME"

echo "Importing it into your login keychain..."
security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P interviewai -T /usr/bin/codesign

echo "Trusting it for code signing (this can ask for your Mac password)..."
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem" || \
    echo "Trust step skipped. If builds still do not use the identity, open Keychain Access, find '$NAME', and set it to Always Trust for Code Signing."

security find-identity -p codesigning | grep "$NAME" || true
echo "Done. From now on ./build.sh signs InterviewAI with '$NAME', and macOS keeps its permission grants across rebuilds."
