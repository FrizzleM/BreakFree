#!/bin/bash
set -euo pipefail

ROOT_DIR="${GITHUB_WORKSPACE:-$(pwd)}"

GITHUB_USER="FrizzleM"
GITHUB_REPO="BreakFree"
PLIST_FOLDER="$ROOT_DIR/Feather/output"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/Feather/output"

TEMPLATE="$ROOT_DIR/template.html"
OUTPUT="$ROOT_DIR/index.html"

plist_blocks=""

for plist in $(ls "$PLIST_FOLDER"/*.plist 2>/dev/null | sort); do
  filename=$(basename "$plist")
  name="${filename%.plist}"

  plist_blocks+="<div class=\"plist-item\">
<strong>$name</strong><br>
<a href=\"itms-services://?action=download-manifest&url=$BASE_URL/$filename\">
Install $name
</a>
</div>

"
done

awk -v blocks="$plist_blocks" '
  {
    if ($0 ~ /{{PLIST_BLOCKS}}/) {
      print blocks
    } else {
      print $0
    }
  }
' "$TEMPLATE" > "$OUTPUT"

echo "Generated $OUTPUT"