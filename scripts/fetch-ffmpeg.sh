#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
FFMPEG_BIN="$DEST_DIR/ffmpeg"
FFPROBE_BIN="$DEST_DIR/ffprobe"
URL="https://evermeet.cx/ffmpeg/ffmpeg-7.0.1.zip"

if [ -f "$FFMPEG_BIN" ] && [ -f "$FFPROBE_BIN" ]; then
  exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/ffmpeg.zip" "$URL"
/usr/bin/unzip -q "$TMP_DIR/ffmpeg.zip" -d "$TMP_DIR"

mkdir -p "$DEST_DIR"
if [ -f "$TMP_DIR/ffmpeg" ]; then
  /bin/cp "$TMP_DIR/ffmpeg" "$FFMPEG_BIN"
  /bin/cp "$TMP_DIR/ffprobe" "$FFPROBE_BIN" || true
  /bin/chmod +x "$FFMPEG_BIN" "$FFPROBE_BIN" 2>/dev/null || true
fi
