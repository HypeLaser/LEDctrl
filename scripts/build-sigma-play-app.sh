#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/Sigma Play.app"
SCRIPT_PATH="/Users/alexscott/Projects/LEDctrl/scripts/open-sigma-play.sh"

rm -rf "$APP_PATH"
osacompile -o "$APP_PATH" -e "do shell script quoted form of \"$SCRIPT_PATH\""

PLIST="$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName 'Sigma Play'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Sigma Play'" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :LSUIElement false" "$PLIST" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo "$APP_PATH"
