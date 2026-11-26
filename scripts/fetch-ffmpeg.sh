#!/bin/sh
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="$ROOT_DIR/Resources/bin"

mkdir -p "$DEST_DIR"
TMP_DIR="$(mktemp -d "$DEST_DIR/.ffmpeg.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

set -f
# ARCHS is an Xcode-provided list of architectures separated by spaces.
# shellcheck disable=SC2086
set -- ${ARCHS:-$(uname -m)}
for ARCH do
  "$ROOT_DIR/scripts/build-ffmpeg-minimal.sh" "$ARCH" "$TMP_DIR"
done

stage_tool() {
  TOOL="$1"
  shift
  if [ "$#" -eq 1 ]; then
    /bin/mv "$TMP_DIR/$TOOL-$1" "$TMP_DIR/$TOOL"
  else
    xcrun lipo -create "$TMP_DIR/$TOOL-$1" "$TMP_DIR/$TOOL-$2" -output "$TMP_DIR/$TOOL"
  fi
}

stage_tool ffmpeg "$@"
stage_tool ffprobe "$@"

if [ -n "$TARGET_BUILD_DIR" ] && [ -n "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  BUILD_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin"
  mkdir -p "$BUILD_DIR"
  /bin/cp "$TMP_DIR/ffmpeg" "$TMP_DIR/ffprobe" "$BUILD_DIR"
fi

/bin/mv -f "$TMP_DIR/ffmpeg" "$TMP_DIR/ffprobe" "$DEST_DIR/"
