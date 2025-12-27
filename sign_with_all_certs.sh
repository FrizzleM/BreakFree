#!/bin/bash
set -u

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="$ROOT_DIR/Feather/output"

CERT_ZIP_URL="https://raw.githubusercontent.com/WhySooooFurious/Ultimate-Sideloading-Guide/refs/heads/main/raw-files/certificates.zip"
UNSIGNED_IPA_URL="https://github.com/FrizzleM/BreakFree/raw/refs/heads/main/Feather/featherunsigned.ipa"

P12_PASSWORD="WSF"
KC_PASSWORD="temp123"

TMP_DIR="$(mktemp -d)"
CERT_DIR="$TMP_DIR/certificates"

mkdir -p "$OUTPUT_DIR"

echo "[*] Root dir: $ROOT_DIR"
echo "[*] Output dir: $OUTPUT_DIR"
echo "[*] Temp dir: $TMP_DIR"

curl -L "$CERT_ZIP_URL" -o "$TMP_DIR/certificates.zip"
curl -L "$UNSIGNED_IPA_URL" -o "$TMP_DIR/unsigned.ipa"

unzip -q "$TMP_DIR/certificates.zip" -d "$TMP_DIR"

SUCCESS=0
FAILED=0

for CERT_PATH in "$CERT_DIR"/*; do
    [[ -d "$CERT_PATH" ]] || continue

    NAME="$(basename "$CERT_PATH")"
    P12_FILE="$CERT_PATH/$NAME.p12"
    PROFILE="$CERT_PATH/$NAME.mobileprovision"

    [[ -f "$P12_FILE" && -f "$PROFILE" ]] || continue

    echo "[*] Processing certificate: $NAME"

    KEYCHAIN="$TMP_DIR/$NAME.keychain-db"

    security create-keychain -p "$KC_PASSWORD" "$KEYCHAIN" || { FAILED=$((FAILED+1)); continue; }
    security unlock-keychain -p "$KC_PASSWORD" "$KEYCHAIN" || { security delete-keychain "$KEYCHAIN"; FAILED=$((FAILED+1)); continue; }
    security list-keychain -d user -s "$KEYCHAIN"

    if ! security import "$P12_FILE" \
        -k "$KEYCHAIN" \
        -P "$P12_PASSWORD" \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security; then
        echo "[!] Import failed: $NAME"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    IPA_WORK="$TMP_DIR/ipa-$NAME"
    mkdir -p "$IPA_WORK"

    if ! unzip -q "$TMP_DIR/unsigned.ipa" -d "$IPA_WORK"; then
        echo "[!] IPA unzip failed: $NAME"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    APP_PATH="$(find "$IPA_WORK/Payload" -maxdepth 1 -name '*.app' | head -n 1)"

    if [[ -z "$APP_PATH" ]]; then
        echo "[!] No .app found: $NAME"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
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
        echo "[!] No identity found: $NAME"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    if [[ -f "$ENTITLEMENTS" ]]; then
        if ! codesign -f -s "$IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_PATH"; then
            echo "[!] Signing failed: $NAME"
            security delete-keychain "$KEYCHAIN"
            FAILED=$((FAILED+1))
            continue
        fi
    else
        if ! codesign -f -s "$IDENTITY" --deep "$APP_PATH"; then
            echo "[!] Signing failed: $NAME"
            security delete-keychain "$KEYCHAIN"
            FAILED=$((FAILED+1))
            continue
        fi
    fi

    pushd "$IPA_WORK" >/dev/null
    zip -qry "$OUTPUT_DIR/feather-$NAME.ipa" Payload
    popd >/dev/null

    echo "[✓] Signed successfully: feather-$NAME.ipa"

    security delete-keychain "$KEYCHAIN"
    SUCCESS=$((SUCCESS+1))
done

rm -rf "$TMP_DIR"

echo "[✓] Done"
echo "[✓] Successful: $SUCCESS"
echo "[!] Failed: $FAILED"