#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT_DIR/Resources/yt-dlp"
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

if [ -f "$DEST" ]; then
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$DEST" "$URL"
chmod +x "$DEST"
