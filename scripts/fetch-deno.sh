#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
DEST="$DEST_DIR/deno"

VERSION="2.9.8"

ARCH="${ARCHS:-$(uname -m)}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) ARCH="$(uname -m)" ;;
esac

case "$ARCH" in
  arm64)
    ASSET="deno-aarch64-apple-darwin.zip"
    SHA256="d1e99265e5e6ee096c5780d88ff7d3e6cfdf33b1953a118b4889cab8ca6980ba"
    ;;
  x86_64)
    ASSET="deno-x86_64-apple-darwin.zip"
    SHA256="5d206ba69742549cc161db06e86f1d93c5622e1dbc8ba9d15a618e538fbc92f4"
    ;;
esac

if ! printf '%s  %s\n' "$SHA256" "$DEST" | /usr/bin/shasum -a 256 -c --status 2>/dev/null; then
  mkdir -p "$DEST_DIR"
  TMP_DIR="$(mktemp -d "$DEST_DIR/.deno.XXXXXX")"
  trap 'rm -rf "$TMP_DIR"' EXIT
  DENO_URL="https://github.com/denoland/deno/releases/download/v$VERSION/$ASSET"
  /usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/deno.zip" "$DENO_URL"
  /usr/bin/unzip -q "$TMP_DIR/deno.zip" -d "$TMP_DIR"
  printf '%s  %s\n' "$SHA256" "$TMP_DIR/deno" | /usr/bin/shasum -a 256 -c
  chmod +x "$TMP_DIR/deno"
  /bin/mv -f "$TMP_DIR/deno" "$DEST"
fi
chmod +x "$DEST"

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin/deno"
  mkdir -p "$(dirname "$BUILD_DEST")"
  /bin/cp "$DEST" "$BUILD_DEST"
fi
