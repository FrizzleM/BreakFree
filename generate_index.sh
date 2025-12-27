#!/bin/bash
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

GITHUB_USER="FrizzleM"
GITHUB_REPO="BreakFree"
PLIST_FOLDER="$ROOT_DIR/Feather/output"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/Feather/output"

TEMPLATE="$ROOT_DIR/template.html"
OUTPUT="$ROOT_DIR/index.html"

BLOCKS_FILE="$(mktemp)"

for plist in $(ls "$PLIST_FOLDER"/*.plist 2>/dev/null | sort); do
  filename="$(basename "$plist")"
  name="${filename%.plist}"

  cat >> "$BLOCKS_FILE" <<EOF
<div class="plist-item">
<strong>$name</strong><br>
<a href="itms-services://?action=download-manifest&url=$BASE_URL/$filename">
Install $name
</a>
</div>

EOF
done

awk -v f="$BLOCKS_FILE" '
  {
    if ($0 ~ /{{PLIST_BLOCKS}}/) {
      while ((getline line < f) > 0) print line
      close(f)
    } else {
      print
    }
  }
' "$TEMPLATE" > "$OUTPUT"

rm -f "$BLOCKS_FILE"

echo "Generated $OUTPUT"
