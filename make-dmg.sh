#!/bin/bash
# Builds a universal, ad-hoc signed app and wraps it in a disk image for the GitHub release.
#   ./make-dmg.sh            -> build/Tidy-for-Mac-<version>.dmg
# Ad-hoc on purpose: the local development certificate means nothing on other Macs, and a
# Developer ID (see notarize.sh) is the only thing that removes the first-open warning.
set -euo pipefail
cd "$(dirname "$0")"

SIGN_IDENTITY="${SIGN_IDENTITY:--}" ./build-app.sh >/dev/null
APP="build/Tidy for Mac.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Tidy-for-Mac-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First time - read me.txt" <<'TXT'
Tidy for Mac

1. Drag "Tidy for Mac" onto the Applications folder next to it.
2. Open it from Applications. macOS will say it can't check the app for malware,
   because it isn't signed with a paid Apple developer certificate.
3. Open System Settings > Privacy & Security, scroll down, and click "Open Anyway"
   next to Tidy for Mac. Enter your password once. That's it, for good.

Or, in Terminal:  xattr -d com.apple.quarantine "/Applications/Tidy for Mac.app"

The source, and the reason it's safe: https://github.com/keithadler/tidymac
TXT

rm -f "$DMG"
hdiutil create -volname "Tidy for Mac" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG"
