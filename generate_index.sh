#!/bin/bash
set -e

GITHUB_USER="FrizzleM"
GITHUB_REPO="BreakFree"
PLIST_FOLDER="Feather/output"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/$PLIST_FOLDER"

TEMPLATE="template.html"
OUTPUT="index.html"

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

# SAFE multi-line replacement using printf
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
