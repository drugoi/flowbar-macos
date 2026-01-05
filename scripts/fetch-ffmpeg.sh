#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
FFMPEG_BIN="$DEST_DIR/ffmpeg"
FFPROBE_BIN="$DEST_DIR/ffprobe"
FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-7.0.1.zip"
FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-7.0.1.zip"

if [ -f "$FFMPEG_BIN" ] && [ -f "$FFPROBE_BIN" ]; then
  exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/ffmpeg.zip" "$FFMPEG_URL"
/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/ffprobe.zip" "$FFPROBE_URL"
/usr/bin/unzip -q "$TMP_DIR/ffmpeg.zip" -d "$TMP_DIR/ffmpeg"
/usr/bin/unzip -q "$TMP_DIR/ffprobe.zip" -d "$TMP_DIR/ffprobe"

mkdir -p "$DEST_DIR"
if [ -f "$TMP_DIR/ffmpeg/ffmpeg" ]; then
  /bin/cp "$TMP_DIR/ffmpeg/ffmpeg" "$FFMPEG_BIN"
fi
if [ -f "$TMP_DIR/ffprobe/ffprobe" ]; then
  /bin/cp "$TMP_DIR/ffprobe/ffprobe" "$FFPROBE_BIN"
fi

if [ ! -f "$FFMPEG_BIN" ] || [ ! -f "$FFPROBE_BIN" ]; then
  echo "ffmpeg or ffprobe missing after download" >&2
  exit 1
fi

/bin/chmod +x "$FFMPEG_BIN" "$FFPROBE_BIN" 2>/dev/null || true

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin"
  mkdir -p "$BUILD_DIR"
  /bin/cp "$FFMPEG_BIN" "$BUILD_DIR/ffmpeg"
  /bin/cp "$FFPROBE_BIN" "$BUILD_DIR/ffprobe"
fi
