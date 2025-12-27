#!/bin/bash
set -u

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="$ROOT_DIR/Feather/output"

CERT_ZIP_URL="https://raw.githubusercontent.com/WhySooooFurious/Ultimate-Sideloading-Guide/refs/heads/main/raw-files/certificates.zip"
UNSIGNED_IPA_URL="https://github.com/FrizzleM/BreakFree/raw/refs/heads/main/Feather/featherunsigned.ipa"

P12_PASSWORD="WSF"
KC_PASSWORD="temp123"
FORCED_BUNDLE_ID="kh.crysalis.feather"

TMP_DIR="$(mktemp -d)"
CERT_DIR="$TMP_DIR/certificates"

mkdir -p "$OUTPUT_DIR"

log() {
  echo "[LOG] $1"
}

fail() {
  echo "[FAIL] $1"
}

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

    echo
    echo "=============================================="
    echo "[*] CERTIFICATE: $NAME"
    echo "=============================================="

    security cms -D -i "$PROFILE" > "$TMP_DIR/profile.plist"

    TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$TMP_DIR/profile.plist" 2>/dev/null || echo "unknown")
    APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$TMP_DIR/profile.plist" 2>/dev/null || echo "unknown")
    EXPIRY=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$TMP_DIR/profile.plist" 2>/dev/null || echo "unknown")

    log "Team ID: $TEAM_ID"
    log "Profile App ID: $APP_ID"
    log "Profile Expiry: $EXPIRY"

    KEYCHAIN="$TMP_DIR/$NAME.keychain-db"

    if ! security create-keychain -p "$KC_PASSWORD" "$KEYCHAIN"; then
        fail "Keychain creation failed"
        FAILED=$((FAILED+1))
        continue
    fi

    security unlock-keychain -p "$KC_PASSWORD" "$KEYCHAIN"
    security list-keychain -d user -s "$KEYCHAIN"

    log "Importing certificate"
    if ! security import "$P12_FILE" \
        -k "$KEYCHAIN" \
        -P "$P12_PASSWORD" \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security 2>&1; then
        fail "Certificate import failed"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    log "Available identities"
    security find-identity -p codesigning -v "$KEYCHAIN" || true

    IPA_WORK="$TMP_DIR/ipa-$NAME"
    mkdir -p "$IPA_WORK"

    log "Unzipping IPA"
    if ! unzip -q "$TMP_DIR/unsigned.ipa" -d "$IPA_WORK"; then
        fail "IPA unzip failed"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    APP_PATH="$(find "$IPA_WORK/Payload" -maxdepth 1 -name '*.app' | head -n 1)"
    INFO_PLIST="$APP_PATH/Info.plist"

    OLD_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "missing")
    log "Bundle ID before: $OLD_BUNDLE_ID"

    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $FORCED_BUNDLE_ID" "$INFO_PLIST" \
      || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $FORCED_BUNDLE_ID" "$INFO_PLIST"

    NEW_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
    log "Bundle ID after: $NEW_BUNDLE_ID"

    cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"
    rm -rf "$APP_PATH/_CodeSignature"

    ENTITLEMENTS="$TMP_DIR/$NAME-entitlements.plist"
    if codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null; then
        log "Extracted entitlements"
        cat "$ENTITLEMENTS"
    else
        log "No entitlements extracted"
        rm -f "$ENTITLEMENTS"
    fi

    IDENTITY="$(security find-identity -p codesigning -v "$KEYCHAIN" | awk -F'"' '{print $2}' | head -n 1)"

    if [[ -z "$IDENTITY" ]]; then
        fail "No signing identity found"
        security delete-keychain "$KEYCHAIN"
        FAILED=$((FAILED+1))
        continue
    fi

    log "Using identity: $IDENTITY"
    log "Running codesign"

    if [[ -f "$ENTITLEMENTS" ]]; then
        if ! codesign -f -s "$IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_PATH" 2>&1; then
            fail "codesign failed (entitlements)"
            security delete-keychain "$KEYCHAIN"
            FAILED=$((FAILED+1))
            continue
        fi
    else
        if ! codesign -f -s "$IDENTITY" --deep "$APP_PATH" 2>&1; then
            fail "codesign failed"
            security delete-keychain "$KEYCHAIN"
            FAILED=$((FAILED+1))
            continue
        fi
    fi

    pushd "$IPA_WORK" >/dev/null
    zip -qry "$OUTPUT_DIR/feather-$NAME.ipa" Payload
    popd >/dev/null

    log "Signed IPA created: feather-$NAME.ipa"

    security delete-keychain "$KEYCHAIN"
    SUCCESS=$((SUCCESS+1))
done

rm -rf "$TMP_DIR"

echo
echo "[✓] Done"
echo "[✓] Successful: $SUCCESS"
echo "[!] Failed: $FAILED"
