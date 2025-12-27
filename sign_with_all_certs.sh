#!/bin/bash
set -euo pipefail



WORKSPACE="/workspaces/BreakFree"
OUTPUT_DIR="$WORKSPACE/Feather/output"

CERT_ZIP_URL="https://raw.githubusercontent.com/WhySooooFurious/Ultimate-Sideloading-Guide/refs/heads/main/raw-files/certificates.zip"
UNSIGNED_IPA_URL="https://github.com/FrizzleM/BreakFree/raw/refs/heads/main/Feather/featherunsigned.ipa"

P12_PASSWORD="WSF"
KC_PASSWORD="temp123"

TMP_DIR="$(mktemp -d)"
CERT_DIR="$TMP_DIR/certificates"

mkdir -p "$OUTPUT_DIR"

echo "[*] Working dir: $TMP_DIR"



echo "[*] Downloading certificates.zip"
curl -L "$CERT_ZIP_URL" -o "$TMP_DIR/certificates.zip"

echo "[*] Downloading unsigned IPA"
curl -L "$UNSIGNED_IPA_URL" -o "$TMP_DIR/unsigned.ipa"



unzip -q "$TMP_DIR/certificates.zip" -d "$TMP_DIR"


for CERT_PATH in "$CERT_DIR"/*; do
    [[ -d "$CERT_PATH" ]] || continue

    NAME="$(basename "$CERT_PATH")"
    P12_FILE="$CERT_PATH/$NAME.p12"
    PROFILE="$CERT_PATH/$NAME.mobileprovision"

    [[ -f "$P12_FILE" && -f "$PROFILE" ]] || continue

    echo "[*] Signing with certificate: $NAME"

    

    KEYCHAIN="$TMP_DIR/$NAME.keychain-db"

    security create-keychain -p "$KC_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 7200 "$KEYCHAIN"
    security unlock-keychain -p "$KC_PASSWORD" "$KEYCHAIN"
    security list-keychain -d user -s "$KEYCHAIN"

    security import "$P12_FILE" \
        -k "$KEYCHAIN" \
        -P "$P12_PASSWORD" \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    

    IPA_WORK="$TMP_DIR/ipa-$NAME"
    mkdir -p "$IPA_WORK"
    unzip -q "$TMP_DIR/unsigned.ipa" -d "$IPA_WORK"

    APP_PATH="$(find "$IPA_WORK/Payload" -maxdepth 1 -name '*.app' | head -n 1)"

    if [[ -z "$APP_PATH" ]]; then
        echo "[!] No .app found for $NAME, skipping"
        security delete-keychain "$KEYCHAIN"
        continue
    fi

    cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"

    rm -rf "$APP_PATH/_CodeSignature"

    ENTITLEMENTS="$TMP_DIR/$NAME-entitlements.plist"
    if ! codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null; then
        rm -f "$ENTITLEMENTS"
    fi

    IDENTITY="$(security find-identity -p codesigning -v "$KEYCHAIN" | head -n 1 | awk -F'\"' '{print $2}')"

    if [[ -z "$IDENTITY" ]]; then
        echo "[!] No identity found for $NAME, skipping"
        security delete-keychain "$KEYCHAIN"
        continue
    fi

    if [[ -f "$ENTITLEMENTS" ]]; then
        codesign -f -s "$IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_PATH"
    else
        codesign -f -s "$IDENTITY" --deep "$APP_PATH"
    fi

    pushd "$IPA_WORK" >/dev/null
    zip -qry "$OUTPUT_DIR/feather-$NAME.ipa" Payload
    popd >/dev/null

    echo "[✓] Saved: feather-$NAME.ipa"

    security delete-keychain "$KEYCHAIN"
done


rm -rf "$TMP_DIR"

echo "[✓] All certificates processed"