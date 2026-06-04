#!/bin/bash
# Usage: make-dmg.sh APP_PATH VOLNAME OUTPUT_DMG
# Builds a drag-install DMG: the app staged beside an /Applications shortcut.
set -e
APP="$1"
VOLNAME="$2"
OUT="$3"

STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
rm -rf "$STAGE"
