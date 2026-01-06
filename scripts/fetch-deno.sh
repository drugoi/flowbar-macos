#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
DEST="$DEST_DIR/deno"

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
  DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip"
else
  DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-apple-darwin.zip"
fi

if [ -f "$DEST" ]; then
  if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
    BUILD_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin/deno"
    mkdir -p "$(dirname "$BUILD_DEST")"
    /bin/cp "$DEST" "$BUILD_DEST"
  fi
  exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

/usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/deno.zip" "$DENO_URL"
/usr/bin/unzip -q "$TMP_DIR/deno.zip" -d "$TMP_DIR/deno"

mkdir -p "$DEST_DIR"
if [ -f "$TMP_DIR/deno/deno" ]; then
  /bin/cp "$TMP_DIR/deno/deno" "$DEST"
fi

if [ ! -f "$DEST" ]; then
  echo "deno missing after download" >&2
  exit 1
fi

/bin/chmod +x "$DEST" 2>/dev/null || true

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin/deno"
  mkdir -p "$(dirname "$BUILD_DEST")"
  /bin/cp "$DEST" "$BUILD_DEST"
fi
