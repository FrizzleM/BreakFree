#!/bin/bash
set -euo pipefail

# This version of the signing script relies on the AskuaSign API instead of local codesign.
# It uploads an unsigned IPA and certificate files to the API, then triggers signing and downloads the signed IPA.
# See README or report for details on AskuaSign API usage.

# Configuration
# Base URL of the AskuaSign API. Can be overridden by setting the ASKUASIGN_BASE_URL environment variable.
API_BASE_URL="${ASKUASIGN_BASE_URL:-http://127.0.0.1:3000}"
# Forced bundle ID to apply when signing. Change as required.
FORCED_BUNDLE_ID="kh.crysalis.feather"
# Password for the .p12 certificate. Can be overridden via the P12_PASSWORD environment variable.
P12_PASSWORD="${P12_PASSWORD:-WSF}"

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="$ROOT_DIR/Feather/output"

# Source locations for signing assets. These can be adjusted if your repository changes.
CERT_ZIP_URL="https://raw.githubusercontent.com/WhySooooFurious/Ultimate-Sideloading-Guide/refs/heads/main/raw-files/certificates.zip"
UNSIGNED_IPA_URL="https://github.com/FrizzleM/BreakFree/raw/refs/heads/main/Feather/featherunsigned.ipa"

TMP_DIR="$(mktemp -d)"
CERT_DIR="$TMP_DIR/certificates"

mkdir -p "$OUTPUT_DIR"

echo "[*] Root dir: $ROOT_DIR"
echo "[*] Output dir: $OUTPUT_DIR"
echo "[*] Temp dir: $TMP_DIR"

# Download signing assets
curl -sSL "$CERT_ZIP_URL" -o "$TMP_DIR/certificates.zip"
curl -sSL "$UNSIGNED_IPA_URL" -o "$TMP_DIR/unsigned.ipa"
unzip -q "$TMP_DIR/certificates.zip" -d "$TMP_DIR"

SUCCESS=0
FAILED=0

for CERT_PATH in "$CERT_DIR"/*; do
    [[ -d "$CERT_PATH" ]] || continue

    NAME="$(basename "$CERT_PATH")"
    P12_FILE="$CERT_PATH/$NAME.p12"
    PROFILE_FILE="$CERT_PATH/$NAME.mobileprovision"

    [[ -f "$P12_FILE" && -f "$PROFILE_FILE" ]] || continue

    echo
    echo "=============================================="
    echo "[*] Remote signing for cert: $NAME"
    echo "=============================================="

    COOKIE_FILE="$TMP_DIR/cookies-$NAME.txt"
    UPLOAD_RESPONSE="$TMP_DIR/upload-$NAME.json"
    SIGN_RESPONSE="$TMP_DIR/sign-$NAME.json"

    # Upload unsigned IPA, certificate, and provisioning profile to AskuaSign.
    # The API returns a UUID identifying the upload session.
    if ! curl -sSL -c "$COOKIE_FILE" \
        -F "ipa=@$TMP_DIR/unsigned.ipa" \
        -F "p12=@$P12_FILE" \
        -F "prov=@$PROFILE_FILE" \
        -F "password=$P12_PASSWORD" \
        -F "bid=$FORCED_BUNDLE_ID" \
        "$API_BASE_URL/upload" \
        -o "$UPLOAD_RESPONSE"; then
        echo "[FAIL] Upload request failed for $NAME"
        FAILED=$((FAILED+1))
        continue
    fi

    UUID=$(python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid',''))" < "$UPLOAD_RESPONSE")
    if [[ -z "$UUID" ]]; then
        echo "[FAIL] Upload failed for $NAME: no uuid returned"
        cat "$UPLOAD_RESPONSE"
        FAILED=$((FAILED+1))
        continue
    fi

    echo "[LOG] Upload successful. UUID: $UUID"

    # Trigger signing. Passing the cookies ensures the password is available to the API.
    if ! curl -sSL -b "$COOKIE_FILE" \
        "$API_BASE_URL/sign?uuid=$UUID" \
        -o "$SIGN_RESPONSE"; then
        echo "[FAIL] Sign request failed for $NAME"
        FAILED=$((FAILED+1))
        continue
    fi

    STATUS=$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('status',''))" < "$SIGN_RESPONSE")
    if [[ "$STATUS" != "ok" ]]; then
        echo "[FAIL] Signing failed for $NAME"
        cat "$SIGN_RESPONSE"
        FAILED=$((FAILED+1))
        continue
    fi

    # Compute signed IPA URL (API serves it at /apps/<uuid>.ipa)
    SIGNED_IPA_URL="$API_BASE_URL/apps/$UUID.ipa"

    echo "[LOG] Downloading signed IPA from $SIGNED_IPA_URL"
    if ! curl -sSL -o "$OUTPUT_DIR/feather-$NAME.ipa" "$SIGNED_IPA_URL"; then
        echo "[FAIL] Failed to download signed IPA for $NAME"
        FAILED=$((FAILED+1))
        continue
    fi

    echo "[✓] Signed successfully: feather-$NAME.ipa"
    SUCCESS=$((SUCCESS+1))

    rm -f "$COOKIE_FILE" "$UPLOAD_RESPONSE" "$SIGN_RESPONSE"
done

rm -rf "$TMP_DIR"

echo
echo "[✓] Done"
echo "[✓] Successful: $SUCCESS"
echo "[!] Failed: $FAILED"