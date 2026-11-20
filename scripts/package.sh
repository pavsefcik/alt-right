#!/bin/bash
# Builds a self-contained, ad-hoc signed Release and packages it for another Mac:
#
#   dist/AltRight-<version>.dmg    drag-install image (app + Applications link + notes)
#   dist/AltRight-<version>.zip    zipped .app
#
# The build is intentionally NOT signed with the local "Alt Right Local Signing"
# identity: that certificate does not exist on the other Mac. Ad-hoc signing keeps
# the app and its Finder extension valid after the quarantine flag is removed.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=Release
DERIVED="build/package"
PRODUCT="$DERIVED/Build/Products/$CONFIG/Alt Right.app"
DIST="dist"
APP_NAME="Alt Right.app"

echo "==> Building $CONFIG (ad-hoc signed for distribution)"
xcodebuild -project AltRight.xcodeproj -scheme AltRight -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build >/dev/null

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$PRODUCT/Contents/Info.plist")

echo "==> Verifying signature and sandbox entitlement"
codesign --verify --deep --strict "$PRODUCT"
codesign -d --entitlements :- "$PRODUCT/Contents/PlugIns/AltRightFinderSync.appex" \
    2>&1 | grep -q "com.apple.security.app-sandbox" \
    || { echo "Finder extension lost its sandbox entitlement"; exit 1; }

rm -rf "$DIST"
mkdir -p "$DIST/stage" "$DIST/dmg"
ditto "$PRODUCT" "$DIST/stage/$APP_NAME"

cat > "$DIST/dmg/Install Notes.txt" <<'NOTES'
Alt Right — local build (signed ad-hoc, not notarized)

1. Drag "Alt Right" into Applications.
2. Open Terminal and remove the download quarantine:

     xattr -dr com.apple.quarantine "/Applications/Alt Right.app"

3. Open Alt Right. It has no Dock icon; it lives in the menu bar.

Finder extension
----------------
System Settings > General > Login Items & Extensions > Finder Extensions,
then enable Alt Right.

If the extension is missing, run:

     pluginkit -a "/Applications/Alt Right.app/Contents/PlugIns/AltRightFinderSync.appex"
     pluginkit -e use -i com.pavel.altright.FinderSync
     killall Finder

Permissions
-----------
- Accessibility: System Settings > Privacy & Security > Accessibility.
  Needed for Copy Path, Go to Folder and Connect to Server.
- Automation: macOS asks once when Add Bookmark reads the current Finder
  selection. Allow it.

Why the Terminal step?
----------------------
This app is not signed with a Developer ID and is not notarized. macOS
quarantines downloaded apps; removing the quarantine flag is the usual local
workaround. Permissions must be granted again on each Mac (and after a rebuild).
NOTES

ln -s /Applications "$DIST/dmg/Applications"
ditto "$DIST/stage/$APP_NAME" "$DIST/dmg/$APP_NAME"

echo "==> Writing zip"
ditto -c -k --keepParent "$DIST/stage/$APP_NAME" "$DIST/AltRight-$VERSION.zip"

echo "==> Writing dmg"
hdiutil create -quiet -volname "Alt Right $VERSION" -srcfolder "$DIST/dmg" \
    -ov -format UDZO "$DIST/AltRight-$VERSION.dmg"

rm -rf "$DIST/stage" "$DIST/dmg"

echo
echo "==> Done"
ls -lh "$DIST"/AltRight-"$VERSION".dmg "$DIST"/AltRight-"$VERSION".zip
echo
shasum -a 256 "$DIST"/AltRight-"$VERSION".dmg "$DIST"/AltRight-"$VERSION".zip
