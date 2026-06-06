#!/bin/bash
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
APP_DIR="${APP_DIR:-Feather}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-feather}"
APP_NAME="${APP_NAME:-Feather}"
PAGE_TITLE="${PAGE_TITLE:-$APP_NAME Breakfree}"
PAGE_HEADING="${PAGE_HEADING:-BreakFree $APP_NAME Installers}"
PAGE_DESCRIPTION="${PAGE_DESCRIPTION:-Use any of the below installers to install $APP_NAME}"
LOGO_URL="${LOGO_URL:-https://files.catbox.moe/god4p6.jpeg}"
LOGO_ALT="${LOGO_ALT:-$APP_NAME Logo}"
OUTPUT_HTML="${OUTPUT_HTML:-index.html}"

if [[ -n "${GITHUB_REPOSITORY:-}" && "$GITHUB_REPOSITORY" == */* ]]; then
  GITHUB_USER="${GITHUB_USER:-${GITHUB_REPOSITORY%/*}}"
  GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY#*/}}"
else
  GITHUB_USER="${GITHUB_USER:-FrizzleM}"
  GITHUB_REPO="${GITHUB_REPO:-BreakFree}"
fi

PLIST_FOLDER="$ROOT_DIR/$APP_DIR/output"
CERT_METADATA_FILE="$PLIST_FOLDER/certificate-validity.tsv"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/$APP_DIR/output"

TEMPLATE="$ROOT_DIR/template.html"
if [[ "$OUTPUT_HTML" = /* ]]; then
  OUTPUT="$OUTPUT_HTML"
else
  OUTPUT="$ROOT_DIR/$OUTPUT_HTML"
fi

BLOCKS_FILE="$(mktemp)"
LAST_UPDATED="$(TZ=Europe/Paris date '+%d/%m/%Y, %H:%M CET')"

certificate_validity_block() {
  local name="$1"
  local row=""
  local cert_name=""
  local cert_expires_at=""
  local cert_days_left=""
  local days_left=""
  local label=""
  local class_name="cert-days-left"

  if [[ ! -f "$CERT_METADATA_FILE" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r cert_name cert_expires_at cert_days_left; do
    if [[ "$cert_name" == "$name" ]]; then
      row=1
      days_left="$cert_days_left"
      break
    fi
  done < "$CERT_METADATA_FILE"

  if [[ -z "$row" ]]; then
    return 0
  fi

  if [[ -z "$days_left" || ! "$days_left" =~ ^-?[0-9]+$ ]]; then
    return 0
  fi

  if (( days_left < 0 )); then
    label="expired"
    class_name="$class_name expired"
  elif (( days_left == 1 )); then
    label="1 day left"
  elif (( days_left >= 100 )); then
    label="$days_left days left"
    class_name="$class_name good"
  else
    label="$days_left days left"
  fi

  printf '<div class="cert-validity"><span class="%s">%s</span></div>\n' "$class_name" "$label"
}

certificate_days_left() {
  local name="$1"
  local cert_name=""
  local cert_expires_at=""
  local cert_days_left=""

  if [[ ! -f "$CERT_METADATA_FILE" ]]; then
    printf '%s\n' "-999999"
    return 0
  fi

  while IFS=$'\t' read -r cert_name cert_expires_at cert_days_left; do
    if [[ "$cert_name" == "$name" && "$cert_days_left" =~ ^-?[0-9]+$ ]]; then
      printf '%s\n' "$cert_days_left"
      return 0
    fi
  done < "$CERT_METADATA_FILE"

  printf '%s\n' "-999999"
}

shopt -s nullglob
PLISTS=("$PLIST_FOLDER"/"$OUTPUT_PREFIX"-*.plist)
shopt -u nullglob

if [[ ${#PLISTS[@]} -gt 0 ]]; then
  while IFS=$'\t' read -r _sort_days_left _sort_name plist; do
    filename="$(basename "$plist")"
    name="${filename%.plist}"
    name="${name#$OUTPUT_PREFIX-}"
    validity_block="$(certificate_validity_block "$name")"
    if [[ -n "$validity_block" ]]; then
      validity_block="${validity_block}"$'\n'
    fi

    cat >> "$BLOCKS_FILE" <<EOF
<div class="plist-item">
<strong>$name</strong><br>
${validity_block}<a href="itms-services://?action=download-manifest&url=$BASE_URL/$filename">
Install $name
</a>
</div>

EOF
  done < <(
    for plist in "${PLISTS[@]}"; do
      filename="$(basename "$plist")"
      name="${filename%.plist}"
      name="${name#$OUTPUT_PREFIX-}"
      days_left="$(certificate_days_left "$name")"
      printf '%s\t%s\t%s\n' "$days_left" "$name" "$plist"
    done | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2
  )
fi

awk \
  -v f="$BLOCKS_FILE" \
  -v last_updated="$LAST_UPDATED" \
  -v page_title="$PAGE_TITLE" \
  -v logo_url="$LOGO_URL" \
  -v logo_alt="$LOGO_ALT" \
  -v page_heading="$PAGE_HEADING" \
  -v page_description="$PAGE_DESCRIPTION" \
  '
  {
    if ($0 ~ /{{PLIST_BLOCKS}}/) {
      while ((getline line < f) > 0) print line
      close(f)
    } else {
      gsub(/{{LAST_UPDATED}}/, last_updated)
      gsub(/{{PAGE_TITLE}}/, page_title)
      gsub(/{{LOGO_URL}}/, logo_url)
      gsub(/{{LOGO_ALT}}/, logo_alt)
      gsub(/{{PAGE_HEADING}}/, page_heading)
      gsub(/{{PAGE_DESCRIPTION}}/, page_description)
      print
    }
  }
' "$TEMPLATE" > "$OUTPUT"

rm -f "$BLOCKS_FILE"

echo "Generated $OUTPUT"
