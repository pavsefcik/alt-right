#!/bin/bash
# Builds Alt Right, installs it into /Applications and enables the Finder extension.
#
#   ./scripts/install.sh            # Release build
#   CONFIG=Debug ./scripts/install.sh
#
# macOS only loads a Finder Sync extension from an app bundle it can find, and it
# refuses to launch an extension whose bundle ID is registered at two different
# paths — so this script makes /Applications the one and only copy.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Alt Right.app"
BUNDLE_ID="com.pavel.altright"
PLUGIN_ID="$BUNDLE_ID.FinderSync"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="build"
BUILD_PRODUCT="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME"
DEST="/Applications/$APP_NAME"
LEGACY_DEST="/Applications/AltRight.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# Sign with a stable local identity if we can; an ad-hoc signature changes on every
# build and silently invalidates the Accessibility permission.
SIGN_IDENTITY="${SIGN_IDENTITY:-Alt Right Local Signing}"
if [ "$SIGN_IDENTITY" != "-" ]; then
    "./scripts/dev-signing.sh" >/dev/null
fi

echo "==> Building ($CONFIG, signing as $SIGN_IDENTITY)"
xcodebuild -project AltRight.xcodeproj -scheme AltRight -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build >/dev/null

# The app is English only, but a build directory reused from before that decision
# keeps empty <lang>.lproj folders around (Xcode refreshes the directories, it
# does not delete resources that left the project). Nothing in them is loaded —
# an empty .lproj just advertises a localization the bundle does not have — but
# they make the bundle lie, so strip them from the product we are about to copy.
find "$BUILD_PRODUCT/Contents/Resources" -maxdepth 1 -name '*.lproj' \
    ! -name 'en.lproj' -exec rm -rf {} + 2>/dev/null || true

# Forget every other copy of the app (Xcode's build product, old installs, …).
while IFS= read -r plugin_path; do
    case "$plugin_path" in
        "$DEST"/*|"") continue ;;
    esac
    other_app="${plugin_path%%/Contents/PlugIns/*}"
    "$LSREGISTER" -u "$other_app" >/dev/null 2>&1 || true
    pluginkit -r "$plugin_path" >/dev/null 2>&1 || true
done < <(pluginkit -m -v -i "$PLUGIN_ID" 2>/dev/null | grep -o '/[^[:space:]]*\.appex' || true)

echo "==> Installing to $DEST"
if [ -d "$LEGACY_DEST" ]; then
    "$LSREGISTER" -u "$LEGACY_DEST" >/dev/null 2>&1 || true
    rm -rf "$LEGACY_DEST"
fi
rm -rf "$DEST"
ditto "$BUILD_PRODUCT" "$DEST"
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "==> Registering Finder extension"
pluginkit -a "$DEST/Contents/PlugIns/AltRightFinderSync.appex" >/dev/null 2>&1 || true
pluginkit -e use -i "$PLUGIN_ID" >/dev/null 2>&1 || true

# Refresh the Services cache so a removed or changed Services declaration takes
# effect immediately (Alt Right no longer registers one, but older versions did).
"/System/Library/CoreServices/pbs" -update >/dev/null 2>&1 || true

# Restart the app so the freshly built binary is what's running.
killall AltRight "Alt Right" >/dev/null 2>&1 || true
sleep 0.5
open "$DEST" || true
killall Finder >/dev/null 2>&1 || true

echo "==> Done. Right-click a file in Finder → Alt Right."
echo "    If the submenu is missing: System Settings › General › Login Items & Extensions › Finder Extensions."
