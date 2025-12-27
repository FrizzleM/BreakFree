#!/bin/bash
set -euo pipefail

IPA_PATH="$1"
PLIST_OUT="$2"

GITHUB_USER="FrizzleM"
GITHUB_REPO="BreakFree"
IPA_FILENAME="$(basename "$IPA_PATH")"
IPA_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/main/Feather/output/$IPA_FILENAME"

TMPDIR="$(mktemp -d)"
unzip -q "$IPA_PATH" -d "$TMPDIR"

APP_PATH="$(find "$TMPDIR/Payload" -maxdepth 1 -name "*.app" | head -n 1)"
if [ -z "$APP_PATH" ]; then
  echo "No .app found inside IPA while generating plist"
  exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")
BUNDLE_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0")
TITLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$INFO_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST" 2>/dev/null || echo "$IPA_FILENAME")

cat > "$PLIST_OUT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>$IPA_URL</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>$BUNDLE_ID</string>
        <key>bundle-version</key>
        <string>$BUNDLE_VERSION</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>$TITLE</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
EOF

rm -rf "$TMPDIR"

echo "Generated plist at $PLIST_OUT"
