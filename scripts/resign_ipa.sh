#!/bin/bash
set -euo pipefail

BASE_IPA="$1"
P12_FILE="$2"
P12_PASSWORD="$3"
PROFILE="$4"
OUTPUT_IPA="$5"

WORK_DIR="$(mktemp -d)"
KEYCHAIN="$WORK_DIR/build.keychain-db"

echo "Using work dir: $WORK_DIR"

security create-keychain -p "" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "" "$KEYCHAIN"

security import "$P12_FILE" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null

security list-keychain -d user -s "$KEYCHAIN"

mkdir -p "$WORK_DIR/ipa"
unzip -q "$BASE_IPA" -d "$WORK_DIR/ipa"

APP_PATH="$(find "$WORK_DIR/ipa/Payload" -maxdepth 1 -name "*.app" | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "No .app found inside IPA"
  exit 1
fi

if [ -z "${PROFILE:-}" ] || [ ! -f "$PROFILE" ]; then
  echo "Provisioning profile not found: $PROFILE"
  exit 1
fi

echo "Using provisioning profile: $PROFILE"
cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"

ENTITLEMENTS_PLIST="$WORK_DIR/entitlements.plist"
if codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PLIST" 2>/dev/null; then
  echo "Extracted entitlements"
else
  echo "No entitlements extracted; continuing without explicit entitlements"
  rm -f "$ENTITLEMENTS_PLIST"
fi

rm -rf "$APP_PATH/_CodeSignature"

IDENTITY=$(security find-identity -p codesigning -v "$KEYCHAIN" | head -n 1 | awk -F\" '{print $2}')
if [ -z "${IDENTITY:-}" ]; then
  echo "No signing identity found in $P12_FILE"
  exit 1
fi

echo "Signing with identity: $IDENTITY"

if [ -f "$ENTITLEMENTS_PLIST" ]; then
  codesign -f -s "$IDENTITY" --entitlements "$ENTITLEMENTS_PLIST" --deep "$APP_PATH"
else
  codesign -f -s "$IDENTITY" --deep "$APP_PATH"
fi

pushd "$WORK_DIR/ipa" >/dev/null
zip -qry "$WORK_DIR/signed.ipa" Payload
popd >/dev/null

mkdir -p "$(dirname "$OUTPUT_IPA")"
mv "$WORK_DIR/signed.ipa" "$OUTPUT_IPA"

security delete-keychain "$KEYCHAIN" || true
rm -rf "$WORK_DIR"

echo "Wrote signed IPA to $OUTPUT_IPA"
