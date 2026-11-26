#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
DEST="$DEST_DIR/yt-dlp"
VERSION="2026.11.23"
SHA256="57654854886d0398a798895aadf5173e2749fbb5e249b9f3728022ab376e11fb"
URL="https://github.com/yt-dlp/yt-dlp/releases/download/$VERSION/yt-dlp_macos"

if ! printf '%s  %s\n' "$SHA256" "$DEST" | /usr/bin/shasum -a 256 -c --status 2>/dev/null; then
  mkdir -p "$DEST_DIR"
  TMP_FILE="$(mktemp "$DEST_DIR/.yt-dlp.XXXXXX")"
  trap 'rm -f "$TMP_FILE"' EXIT
  /usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_FILE" "$URL"
  printf '%s  %s\n' "$SHA256" "$TMP_FILE" | /usr/bin/shasum -a 256 -c
  chmod 755 "$TMP_FILE"
  /bin/mv -f "$TMP_FILE" "$DEST"
fi
chmod 755 "$DEST"

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin/yt-dlp"
  mkdir -p "$(dirname "$BUILD_DEST")"
  /bin/cp "$DEST" "$BUILD_DEST"
fi
