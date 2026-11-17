#!/bin/bash
# Removes Alt Right and its Finder extension registration.
set -euo pipefail

BUNDLE_ID="com.pavel.altright"
DEST="/Applications/Alt Right.app"
LEGACY_DEST="/Applications/AltRight.app"

pluginkit -e ignore -i "$BUNDLE_ID.FinderSync" >/dev/null 2>&1 || true
pluginkit -r "$DEST/Contents/PlugIns/AltRightFinderSync.appex" >/dev/null 2>&1 || true

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
killall "Alt Right" AltRight >/dev/null 2>&1 || true

rm -rf "$DEST" "$LEGACY_DEST"
killall Finder >/dev/null 2>&1 || true

echo "==> Alt Right removed."
