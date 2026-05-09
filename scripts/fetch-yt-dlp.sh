#!/bin/bash
# Fetches the latest yt-dlp universal macOS binary into deps/.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p deps
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
DEST="deps/yt-dlp_macos"

echo "→ $URL"
curl -L --fail --progress-bar -o "$DEST" "$URL"
chmod +x "$DEST"
echo "→ saved to $DEST"
"$DEST" --version
