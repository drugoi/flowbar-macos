#!/bin/sh
set -e

ARCH="${1:-}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Usage: $0 <arm64|x86_64>" >&2; exit 1 ;;
esac

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="9.1"
SOURCE_SHA256="0ac7c9b9806b58eda00a528dcba316a2f33d291d949438900efa811d04b051bd"
SRC_PARENT="$ROOT_DIR/build/ffmpeg-src"
OUTPUT_DIR="$ROOT_DIR/Resources/bin"
DEST_DIR="${2:-$OUTPUT_DIR}"
FFMPEG_BIN="$OUTPUT_DIR/ffmpeg-$ARCH-$VERSION"
FFPROBE_BIN="$OUTPUT_DIR/ffprobe-$ARCH-$VERSION"

mkdir -p "$SRC_PARENT" "$OUTPUT_DIR" "$DEST_DIR"

build_tools() {
  TMP_DIR="$(mktemp -d "$SRC_PARENT/build.XXXXXX")"
  trap 'rm -rf "$TMP_DIR"' EXIT
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

  ARCHIVE="$SRC_PARENT/ffmpeg-$VERSION.tar.gz"
  if ! printf '%s  %s\n' "$SOURCE_SHA256" "$ARCHIVE" | /usr/bin/shasum -a 256 -c --status 2>/dev/null; then
    /usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$TMP_DIR/source.tar.gz" "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n$VERSION"
    printf '%s  %s\n' "$SOURCE_SHA256" "$TMP_DIR/source.tar.gz" | /usr/bin/shasum -a 256 -c
    /bin/mv -f "$TMP_DIR/source.tar.gz" "$ARCHIVE"
  fi
  /usr/bin/tar -xf "$ARCHIVE" -C "$TMP_DIR"
  # Match the release tarball version instead of inheriting the parent Git checkout.
  printf '%s\n' "$VERSION" > "$TMP_DIR/FFmpeg-n$VERSION/FF_VERSION"

  mkdir "$TMP_DIR/build"
  cd "$TMP_DIR/build"

  set -- \
    --arch="$ARCH" \
    --target-os=darwin \
    --cc=clang \
    --enable-cross-compile \
    --disable-autodetect \
    --disable-debug \
    --disable-doc \
    --disable-shared \
    --enable-static \
    --disable-everything \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-avcodec \
    --enable-avformat \
    --enable-avfilter \
    --enable-swresample \
    --enable-protocol=file,https,tls \
    --enable-demuxer=mov,matroska,webm,ogg,mp3 \
    --enable-muxer=mp4,ipod \
    --enable-parser=aac,opus,vorbis,mp3 \
    --enable-decoder=aac,opus,vorbis,mp3 \
    --enable-encoder=aac \
    --enable-bsf=aac_adtstoasc \
    --enable-filter=aresample,volume \
    --enable-securetransport \
    --extra-cflags="-O2 -arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDK_PATH" \
    --extra-ldflags="-arch $ARCH -mmacosx-version-min=13.0 -isysroot $SDK_PATH"

  if [ "$ARCH" = "x86_64" ]; then
    set -- "$@" --disable-x86asm
  fi

  "$TMP_DIR/FFmpeg-n$VERSION/configure" "$@"
  make -j "$JOBS" ffmpeg ffprobe
  /usr/bin/strip -x ffmpeg ffprobe 2>/dev/null || true
  /bin/mv -f ffmpeg "$FFMPEG_BIN"
  /bin/mv -f ffprobe "$FFPROBE_BIN"

  echo "Built minimal ffmpeg for $ARCH at $OUTPUT_DIR"
}

if [ ! -x "$FFMPEG_BIN" ] || [ ! -x "$FFPROBE_BIN" ]; then
  build_tools
fi

/bin/cp "$FFMPEG_BIN" "$DEST_DIR/ffmpeg-$ARCH"
/bin/cp "$FFPROBE_BIN" "$DEST_DIR/ffprobe-$ARCH"
