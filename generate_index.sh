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

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/Feather/output"

TEMPLATE="$ROOT_DIR/template.html"
OUTPUT="$ROOT_DIR/index.html"

BLOCKS_FILE="$(mktemp)"
LAST_UPDATED="$(TZ=Europe/Paris date '+%d/%m/%Y, %H:%M CET')"

shopt -s nullglob
PLISTS=("$PLIST_FOLDER"/feather-*.plist)
shopt -u nullglob

if [[ ${#PLISTS[@]} -gt 0 ]]; then
  while IFS= read -r plist; do
    filename="$(basename "$plist")"
    name="${filename%.plist}"
    name="${name#feather-}"

    cat >> "$BLOCKS_FILE" <<EOF
<div class="plist-item">
<strong>$name</strong><br>
<a href="itms-services://?action=download-manifest&url=$BASE_URL/$filename">
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
