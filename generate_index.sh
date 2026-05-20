#!/bin/bash
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

if [[ -n "${GITHUB_REPOSITORY:-}" && "$GITHUB_REPOSITORY" == */* ]]; then
  GITHUB_USER="${GITHUB_USER:-${GITHUB_REPOSITORY%/*}}"
  GITHUB_REPO="${GITHUB_REPO:-${GITHUB_REPOSITORY#*/}}"
else
  GITHUB_USER="${GITHUB_USER:-FrizzleM}"
  GITHUB_REPO="${GITHUB_REPO:-BreakFree}"
fi

PLIST_FOLDER="$ROOT_DIR/Feather/output"
CERT_METADATA_FILE="$PLIST_FOLDER/certificate-validity.tsv"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/Feather/output"

TEMPLATE="$ROOT_DIR/template.html"
OUTPUT="$ROOT_DIR/index.html"

BLOCKS_FILE="$(mktemp)"
LAST_UPDATED="$(TZ=Europe/Paris date '+%d/%m/%Y, %H:%M CET')"

certificate_validity_block() {
  local name="$1"
  local row=""
  local cert_name=""
  local cert_expires_at=""
  local cert_days_left=""
  local expires_at=""
  local days_left=""
  local label=""
  local class_name="cert-validity"

  if [[ ! -f "$CERT_METADATA_FILE" ]]; then
    return 0
  fi

  while IFS=$'\t' read -r cert_name cert_expires_at cert_days_left; do
    if [[ "$cert_name" == "$name" ]]; then
      row=1
      expires_at="$cert_expires_at"
      days_left="$cert_days_left"
      break
    fi
  done < "$CERT_METADATA_FILE"

  if [[ -z "$row" ]]; then
    return 0
  fi

  if [[ -z "$expires_at" || -z "$days_left" || ! "$days_left" =~ ^-?[0-9]+$ ]]; then
    return 0
  fi

  if (( days_left < 0 )); then
    label="expired"
    class_name="$class_name expired"
  elif (( days_left == 1 )); then
    label="1 day left"
  else
    label="$days_left days left"
  fi

  printf '<div class="%s">Certificate validity: %s (expires %s)</div>\n' "$class_name" "$label" "$expires_at"
}

shopt -s nullglob
PLISTS=("$PLIST_FOLDER"/feather-*.plist)
shopt -u nullglob

if [[ ${#PLISTS[@]} -gt 0 ]]; then
  while IFS= read -r plist; do
    filename="$(basename "$plist")"
    name="${filename%.plist}"
    name="${name#feather-}"
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
  done < <(printf '%s\n' "${PLISTS[@]}" | LC_ALL=C sort)
fi

awk -v f="$BLOCKS_FILE" -v last_updated="$LAST_UPDATED" '
  {
    if ($0 ~ /{{PLIST_BLOCKS}}/) {
      while ((getline line < f) > 0) print line
      close(f)
    } else {
      gsub(/{{LAST_UPDATED}}/, last_updated)
      print
    }
  }
' "$TEMPLATE" > "$OUTPUT"

rm -f "$BLOCKS_FILE"

echo "Generated $OUTPUT"
