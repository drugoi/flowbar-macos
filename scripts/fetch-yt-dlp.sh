#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  DEST_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin"
else
  DEST_DIR="$ROOT_DIR/Resources/bin"
fi
DEST="$DEST_DIR/yt-dlp"
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

if [ -f "$DEST" ]; then
  exit 0
fi

mkdir -p "$DEST_DIR"
/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$DEST" "$URL"
chmod +x "$DEST"
