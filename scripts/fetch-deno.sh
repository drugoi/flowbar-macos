#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"
DEST="$DEST_DIR/deno"

VERSION="2.9.8"

mkdir -p "$DEST_DIR"
TMP_DIR="$(mktemp -d "$DEST_DIR/.deno.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

set -f
# ARCHS is an Xcode-provided list of architectures separated by spaces.
# shellcheck disable=SC2086
set -- ${ARCHS:-$(uname -m)}
for ARCH do
  case "$ARCH" in
    arm64)
      ASSET="deno-aarch64-apple-darwin.zip"
      SHA256="d1e99265e5e6ee096c5780d88ff7d3e6cfdf33b1953a118b4889cab8ca6980ba"
      ;;
    x86_64)
      ASSET="deno-x86_64-apple-darwin.zip"
      SHA256="5d206ba69742549cc161db06e86f1d93c5622e1dbc8ba9d15a618e538fbc92f4"
      ;;
    *)
      echo "Unsupported Deno architecture: $ARCH" >&2
      exit 1
      ;;
  esac

  CACHED="$DEST_DIR/deno-$VERSION-$ARCH"
  if ! printf '%s  %s\n' "$SHA256" "$CACHED" | /usr/bin/shasum -a 256 -c --status 2>/dev/null; then
    mkdir -p "$TMP_DIR/$ARCH"
    DENO_URL="https://github.com/denoland/deno/releases/download/v$VERSION/$ASSET"
    /usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/$ARCH/deno.zip" "$DENO_URL"
    /usr/bin/unzip -q "$TMP_DIR/$ARCH/deno.zip" -d "$TMP_DIR/$ARCH"
    printf '%s  %s\n' "$SHA256" "$TMP_DIR/$ARCH/deno" | /usr/bin/shasum -a 256 -c
    chmod 755 "$TMP_DIR/$ARCH/deno"
    /bin/mv -f "$TMP_DIR/$ARCH/deno" "$CACHED"
  fi
done

if [ "$#" -eq 1 ]; then
  /bin/cp "$DEST_DIR/deno-$VERSION-$1" "$TMP_DIR/deno"
else
  xcrun lipo -create "$DEST_DIR/deno-$VERSION-$1" "$DEST_DIR/deno-$VERSION-$2" -output "$TMP_DIR/deno"
fi
chmod 755 "$TMP_DIR/deno"

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin/deno"
  mkdir -p "$(dirname "$BUILD_DEST")"
  /bin/cp "$TMP_DIR/deno" "$BUILD_DEST"
fi

/bin/mv -f "$TMP_DIR/deno" "$DEST"
