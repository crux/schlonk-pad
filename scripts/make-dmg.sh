#!/bin/bash
# Usage: make-dmg.sh APP_PATH VOLNAME OUTPUT_DMG
# Builds a drag-install DMG: the app staged beside an /Applications shortcut.
set -e
APP="$1"
VOLNAME="$2"
OUT="$3"

STAGE="$(mktemp -d)"
APP_NAME="$(basename "$APP")"
ditto "$APP" "$STAGE/$APP_NAME"

# Re-seal the bundle before packaging. Post-build edits (e.g. patching
# Info.plist version / display name) invalidate the ad-hoc signature, which
# makes a quarantined download report "damaged and can't be opened" on Apple
# Silicon. An ad-hoc re-sign restores a valid seal, so Gatekeeper instead shows
# the normal "unidentified developer → Open Anyway" path.
codesign --force --deep --sign - "$STAGE/$APP_NAME"

ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
