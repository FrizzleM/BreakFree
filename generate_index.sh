#!/bin/bash
set -e

GITHUB_USER="FrizzleM"
GITHUB_REPO="BreakFree"
PLIST_FOLDER="output"

mkdir -p "$PLIST_FOLDER"

BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/$PLIST_FOLDER"

TEMPLATE="template.html"
OUTPUT="index.html"

plist_blocks=""

if compgen -G "$PLIST_FOLDER"/*.plist > /dev/null; then
    for plist in $(ls "$PLIST_FOLDER"/*.plist 2>/dev/null | sort); do
        filename=$(basename "$plist")
        name="${filename%.plist}"

        plist_blocks+="<div class=\"plist-item\">\n"
        plist_blocks+="<strong>$name</strong><br>\n"
        plist_blocks+="<a href=\"itms-services://?action=download-manifest&url=$BASE_URL/$filename\">\n"
        plist_blocks+="Install $name\n"
        plist_blocks+="</a>\n"
        plist_blocks+="</div>\n\n"
    done
else
    plist_blocks+="<div class=\"plist-item\">No signed installers are available right now.</div>\n"
fi

sed "s|{{PLIST_BLOCKS}}|$plist_blocks|" "$TEMPLATE" > "$OUTPUT"
echo "Generated $OUTPUT"
