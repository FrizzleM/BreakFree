#!/bin/bash
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
OUTPUT_DIR="$ROOT_DIR/Feather/output"
CERT_URL_FILE="$ROOT_DIR/Ksign-and-esign/certs/url"
LOCAL_UNSIGNED_IPA="$ROOT_DIR/Feather/featherunsigned.ipa"

DEFAULT_CERT_ZIP_URL="https://raw.githubusercontent.com/WhySooooFurious/Ultimate-Sideloading-Guide/refs/heads/main/raw-files/certificates.zip"
DEFAULT_UNSIGNED_IPA_URL="https://raw.githubusercontent.com/FrizzleM/BreakFree/main/Feather/featherunsigned.ipa"

DEFAULT_P12_PASSWORD="${P12_PASSWORD:-WSF}"
KC_PASSWORD="${KC_PASSWORD:-temp123}"
FORCED_BUNDLE_ID="${FORCED_BUNDLE_ID:-}"

TMP_DIR="$(mktemp -d)"
CERT_ARCHIVE="$TMP_DIR/certificates.zip"
UNSIGNED_IPA="$TMP_DIR/unsigned.ipa"

ORIGINAL_KEYCHAINS=()
OPENSSL_LEGACY_FLAG=""

log() {
  echo "[LOG] $1"
}

warn() {
  echo "[WARN] $1"
}

fail() {
  echo "[FAIL] $1"
}

cleanup() {
  restore_keychains
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

restore_keychains() {
  if [[ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
}

trimmed_first_line() {
  awk '
    {
      sub(/\r$/, "")
      if ($0 ~ /[^[:space:]]/) {
        print
        exit
      }
    }
  ' "$1"
}

safe_name() {
  echo "$1" | tr ' ' '-' | sed 's/[^A-Za-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

clean_generated_artifacts() {
  local pattern="$1"
  local matches=()

  shopt -s nullglob
  matches=("$OUTPUT_DIR"/$pattern)
  shopt -u nullglob

  if [[ ${#matches[@]} -gt 0 ]]; then
    rm -f "${matches[@]}"
  fi
}

resolve_cert_zip_url() {
  if [[ -n "${CERT_ZIP_URL:-}" ]]; then
    echo "$CERT_ZIP_URL"
    return 0
  fi

  if [[ -f "$CERT_URL_FILE" ]]; then
    local configured_url
    configured_url="$(trimmed_first_line "$CERT_URL_FILE")"
    if [[ -n "$configured_url" ]]; then
      echo "$configured_url"
      return 0
    fi
  fi

  echo "$DEFAULT_CERT_ZIP_URL"
}

download_unsigned_ipa() {
  if [[ -n "${UNSIGNED_IPA_PATH:-}" && -f "$UNSIGNED_IPA_PATH" ]]; then
    cp "$UNSIGNED_IPA_PATH" "$UNSIGNED_IPA"
    return 0
  fi

  if [[ -f "$LOCAL_UNSIGNED_IPA" ]]; then
    cp "$LOCAL_UNSIGNED_IPA" "$UNSIGNED_IPA"
    return 0
  fi

  curl -fsSL "${UNSIGNED_IPA_URL:-$DEFAULT_UNSIGNED_IPA_URL}" -o "$UNSIGNED_IPA"
}

resolve_p12_password() {
  local cert_dir="$1"
  local base_name="$2"
  local candidate=""

  for candidate in \
    "$cert_dir/$base_name.password" \
    "$cert_dir/$base_name.pass" \
    "$cert_dir/$base_name.txt" \
    "$cert_dir/password.txt" \
    "$cert_dir/password"; do
    if [[ -f "$candidate" ]]; then
      local sidecar_password
      sidecar_password="$(trimmed_first_line "$candidate")"
      if [[ -n "$sidecar_password" ]]; then
        echo "$sidecar_password"
        return 0
      fi
    fi
  done

  echo "$DEFAULT_P12_PASSWORD"
}

set_plist_string() {
  local plist_path="$1"
  local key_path="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set $key_path $value" "$plist_path" >/dev/null 2>&1 \
    || /usr/libexec/PlistBuddy -c "Add $key_path string $value" "$plist_path" >/dev/null 2>&1
}

derive_bundle_id() {
  local team_id="$1"
  local profile_app_id="$2"
  local original_bundle_id="$3"

  if [[ -z "$team_id" || -z "$profile_app_id" ]]; then
    echo "$original_bundle_id"
    return 0
  fi

  case "$profile_app_id" in
    "$team_id.*")
      if [[ -n "$FORCED_BUNDLE_ID" ]]; then
        echo "$FORCED_BUNDLE_ID"
      else
        echo "$original_bundle_id"
      fi
      ;;
    "$team_id."*)
      echo "${profile_app_id#"$team_id."}"
      ;;
    *)
      echo "$original_bundle_id"
      ;;
  esac
}

normalize_keychain_groups() {
  local entitlements_path="$1"
  local team_id="$2"
  local target_bundle_id="$3"
  local idx=0
  local group_value=""

  while group_value=$(/usr/libexec/PlistBuddy -c "Print :keychain-access-groups:$idx" "$entitlements_path" 2>/dev/null); do
    if [[ "$group_value" == "$team_id.*" ]]; then
      /usr/libexec/PlistBuddy -c "Set :keychain-access-groups:$idx $team_id.$target_bundle_id" "$entitlements_path" >/dev/null 2>&1
    fi
    idx=$((idx + 1))
  done

  if ! /usr/libexec/PlistBuddy -c "Print :keychain-access-groups:0" "$entitlements_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" "$entitlements_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string $team_id.$target_bundle_id" "$entitlements_path" >/dev/null 2>&1
  fi
}

prepare_entitlements() {
  local profile_plist="$1"
  local entitlements_path="$2"
  local team_id="$3"
  local target_bundle_id="$4"

  if ! /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$profile_plist" > "$entitlements_path" 2>/dev/null; then
    return 1
  fi

  set_plist_string "$entitlements_path" ":application-identifier" "$team_id.$target_bundle_id"
  set_plist_string "$entitlements_path" ":com.apple.developer.team-identifier" "$team_id"
  normalize_keychain_groups "$entitlements_path" "$team_id" "$target_bundle_id"

  return 0
}

repack_pkcs12() {
  local input_p12="$1"
  local output_p12="$2"
  local password="$3"
  local repack_dir="$TMP_DIR/repack-$(basename "$input_p12" .p12)"
  local bundle_pem="$repack_dir/bundle.pem"

  mkdir -p "$repack_dir"

  if ! openssl pkcs12 $OPENSSL_LEGACY_FLAG -in "$input_p12" -passin "pass:$password" -nodes -out "$bundle_pem" >/dev/null 2>&1; then
    return 1
  fi

  openssl pkcs12 -export $OPENSSL_LEGACY_FLAG -in "$bundle_pem" -inkey "$bundle_pem" -out "$output_p12" -passout "pass:$password" >/dev/null 2>&1
}

import_certificate() {
  local p12_file="$1"
  local keychain="$2"
  local password="$3"
  local repacked_p12="$TMP_DIR/repacked-$(basename "$p12_file")"

  if security import "$p12_file" -f pkcs12 -k "$keychain" -P "$password" -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
    return 0
  fi

  warn "Direct PKCS#12 import failed for $(basename "$p12_file"); retrying with an OpenSSL-normalized copy"

  if ! command -v openssl >/dev/null 2>&1; then
    return 1
  fi

  if ! repack_pkcs12 "$p12_file" "$repacked_p12" "$password"; then
    return 1
  fi

  security import "$repacked_p12" -f pkcs12 -k "$keychain" -P "$password" -A -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1
}

sign_embedded_code() {
  local app_path="$1"
  local identity="$2"

  if [[ -d "$app_path/Frameworks" ]]; then
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      codesign -f -s "$identity" --generate-entitlement-der --timestamp=none "$component"
    done < <(find "$app_path/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) | LC_ALL=C sort)
  fi
}

while IFS= read -r existing_keychain; do
  existing_keychain="${existing_keychain//\"/}"
  [[ -n "$existing_keychain" ]] || continue
  ORIGINAL_KEYCHAINS+=("$existing_keychain")
done < <(security list-keychains -d user 2>/dev/null || true)

OPENSSL_PKCS12_HELP="$(openssl pkcs12 -help 2>&1 || true)"
if [[ "$OPENSSL_PKCS12_HELP" == *"-legacy"* ]]; then
  OPENSSL_LEGACY_FLAG="-legacy"
fi

mkdir -p "$OUTPUT_DIR"
clean_generated_artifacts "feather-*.ipa"

CERT_ZIP_URL="$(resolve_cert_zip_url)"

echo "[*] Root dir: $ROOT_DIR"
echo "[*] Output dir: $OUTPUT_DIR"
echo "[*] Temp dir: $TMP_DIR"
echo "[*] Certificate zip: $CERT_ZIP_URL"

curl -fsSL "$CERT_ZIP_URL" -o "$CERT_ARCHIVE"
download_unsigned_ipa
unzip -q "$CERT_ARCHIVE" -d "$TMP_DIR"

SUCCESS=0
FAILED=0
FOUND_P12=0

while IFS= read -r P12_FILE; do
  [[ -n "$P12_FILE" ]] || continue
  FOUND_P12=1

  CERT_PATH="$(dirname "$P12_FILE")"
  RAW_NAME="$(basename "$P12_FILE" .p12)"
  OUTPUT_NAME="$(safe_name "$RAW_NAME")"
  PROFILE="$CERT_PATH/$RAW_NAME.mobileprovision"

  if [[ ! -f "$PROFILE" ]]; then
    PROFILE="$(find "$CERT_PATH" -maxdepth 1 -type f -name '*.mobileprovision' | LC_ALL=C sort)"
    PROFILE="${PROFILE%%$'\n'*}"
  fi

  if [[ -z "${PROFILE:-}" || ! -f "$PROFILE" ]]; then
    warn "Skipping $RAW_NAME because no matching provisioning profile was found"
    FAILED=$((FAILED + 1))
    continue
  fi

  P12_PASSWORD_FOR_CERT="$(resolve_p12_password "$CERT_PATH" "$RAW_NAME")"

  echo
  echo "=============================================="
  echo "[*] CERTIFICATE: $RAW_NAME"
  echo "=============================================="

  PROFILE_PLIST="$TMP_DIR/$OUTPUT_NAME-profile.plist"
  if ! security cms -D -i "$PROFILE" > "$PROFILE_PLIST"; then
    fail "Unable to decode provisioning profile"
    FAILED=$((FAILED + 1))
    continue
  fi

  TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST" 2>/dev/null || echo "")
  PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PROFILE_PLIST" 2>/dev/null || echo "")
  EXPIRY=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$PROFILE_PLIST" 2>/dev/null || echo "unknown")
  PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$PROFILE_PLIST" 2>/dev/null || echo "$RAW_NAME")

  log "Profile name: $PROFILE_NAME"
  log "Team ID: ${TEAM_ID:-unknown}"
  log "Profile App ID: ${PROFILE_APP_ID:-unknown}"
  log "Profile Expiry: $EXPIRY"

  if [[ -z "$TEAM_ID" || -z "$PROFILE_APP_ID" ]]; then
    fail "Provisioning profile is missing TeamIdentifier or application-identifier"
    FAILED=$((FAILED + 1))
    continue
  fi

  KEYCHAIN="$TMP_DIR/$OUTPUT_NAME.keychain-db"
  IPA_WORK="$TMP_DIR/ipa-$OUTPUT_NAME"
  ENTITLEMENTS="$TMP_DIR/$OUTPUT_NAME-entitlements.plist"

  rm -rf "$IPA_WORK"
  mkdir -p "$IPA_WORK"

  if ! security create-keychain -p "$KC_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
    fail "Keychain creation failed"
    FAILED=$((FAILED + 1))
    continue
  fi

  security set-keychain-settings -lut 7200 "$KEYCHAIN" >/dev/null 2>&1 || true
  security unlock-keychain -p "$KC_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1
  if [[ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]]; then
    security list-keychains -d user -s "$KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1
  else
    security list-keychains -d user -s "$KEYCHAIN" >/dev/null 2>&1
  fi

  log "Importing certificate"
  if ! import_certificate "$P12_FILE" "$KEYCHAIN" "$P12_PASSWORD_FOR_CERT"; then
    fail "Certificate import failed"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true

  IDENTITY="$(security find-identity -p codesigning -v "$KEYCHAIN" | sed -n 's/.*"\([^"]*\)".*/\1/p')"
  IDENTITY="${IDENTITY%%$'\n'*}"
  if [[ -z "$IDENTITY" ]]; then
    fail "No signing identity found"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  log "Using identity: $IDENTITY"

  if ! unzip -q "$UNSIGNED_IPA" -d "$IPA_WORK"; then
    fail "IPA unzip failed"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  APP_PATH="$(find "$IPA_WORK/Payload" -maxdepth 1 -name '*.app' | LC_ALL=C sort)"
  APP_PATH="${APP_PATH%%$'\n'*}"
  if [[ -z "${APP_PATH:-}" || ! -d "$APP_PATH" ]]; then
    fail "No .app bundle found in IPA"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  INFO_PLIST="$APP_PATH/Info.plist"
  ORIGINAL_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || echo "")

  if [[ -z "$ORIGINAL_BUNDLE_ID" ]]; then
    fail "Missing CFBundleIdentifier in app Info.plist"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  TARGET_BUNDLE_ID="$(derive_bundle_id "$TEAM_ID" "$PROFILE_APP_ID" "$ORIGINAL_BUNDLE_ID")"

  if [[ -n "$FORCED_BUNDLE_ID" && "$PROFILE_APP_ID" != "$TEAM_ID.*" && "$FORCED_BUNDLE_ID" != "$TARGET_BUNDLE_ID" ]]; then
    warn "Ignoring FORCED_BUNDLE_ID for $RAW_NAME because the provisioning profile is explicit"
  fi

  log "Bundle ID before: $ORIGINAL_BUNDLE_ID"
  log "Bundle ID after: $TARGET_BUNDLE_ID"

  set_plist_string "$INFO_PLIST" ":CFBundleIdentifier" "$TARGET_BUNDLE_ID"

  cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"
  rm -rf "$APP_PATH/_CodeSignature"

  if ! prepare_entitlements "$PROFILE_PLIST" "$ENTITLEMENTS" "$TEAM_ID" "$TARGET_BUNDLE_ID"; then
    fail "Unable to prepare entitlements"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  sign_embedded_code "$APP_PATH" "$IDENTITY"

  if ! codesign -f -s "$IDENTITY" --generate-entitlement-der --timestamp=none --entitlements "$ENTITLEMENTS" "$APP_PATH"; then
    fail "codesign failed"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    fail "codesign verification failed"
    restore_keychains
    security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
    FAILED=$((FAILED + 1))
    continue
  fi

  pushd "$IPA_WORK" >/dev/null
  zip -qry "$OUTPUT_DIR/feather-$OUTPUT_NAME.ipa" Payload
  popd >/dev/null

  log "Signed IPA created: feather-$OUTPUT_NAME.ipa"

  restore_keychains
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  SUCCESS=$((SUCCESS + 1))
done < <(find "$TMP_DIR" -type f -name '*.p12' | LC_ALL=C sort)

if [[ $FOUND_P12 -eq 0 ]]; then
  fail "No .p12 files were found in the certificate archive"
  exit 1
fi

echo
echo "[✓] Done"
echo "[✓] Successful: $SUCCESS"
echo "[!] Failed: $FAILED"
