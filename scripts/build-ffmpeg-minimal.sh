#!/bin/sh
set -e

ARCH="${1:-}"
if [ -z "$ARCH" ]; then
  echo "Usage: $0 <arm64|x86_64>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="7.0.1"
SRC_PARENT="$ROOT_DIR/build/ffmpeg-src"
SRC_DIR="$SRC_PARENT/ffmpeg-$VERSION"
BUILD_DIR="$ROOT_DIR/build/ffmpeg-build-$ARCH"
PREFIX_DIR="$ROOT_DIR/build/ffmpeg-prefix-$ARCH"
OUTPUT_DIR="$ROOT_DIR/Resources/bin"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
HOST_ARCH="$(uname -m)"
USE_EXTERNAL_LIBS=1
if [ "$ARCH" != "$HOST_ARCH" ]; then
  USE_EXTERNAL_LIBS=0
fi

mkdir -p "$SRC_PARENT" "$BUILD_DIR" "$PREFIX_DIR" "$OUTPUT_DIR"

if [ ! -d "$SRC_DIR" ]; then
  ARCHIVE="$SRC_PARENT/ffmpeg-$VERSION.tar.xz"
  if [ ! -f "$ARCHIVE" ]; then
    /usr/bin/curl -L --fail --retry 3 --retry-delay 1 -o "$ARCHIVE" "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"
  fi
  /usr/bin/tar -xf "$ARCHIVE" -C "$SRC_PARENT"
fi

cd "$SRC_DIR"

make distclean >/dev/null 2>&1 || true

PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/usr/local/lib/pkgconfig"
export PKG_CONFIG_PATH

set -- \
  --prefix="$PREFIX_DIR" \
  --arch="$ARCH" \
  --target-os=darwin \
  --cc=clang \
  --enable-cross-compile \
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

if [ "$USE_EXTERNAL_LIBS" -eq 1 ]; then
  set -- "$@" --enable-libopus --enable-libvorbis
else
  if [ "$ARCH" = "x86_64" ]; then
    set -- "$@" --disable-x86asm
  fi
fi

./configure "$@"

make -j "$JOBS"
make install

FFMPEG_BIN="$PREFIX_DIR/bin/ffmpeg"
FFPROBE_BIN="$PREFIX_DIR/bin/ffprobe"
if [ ! -f "$FFMPEG_BIN" ] || [ ! -f "$FFPROBE_BIN" ]; then
  echo "ffmpeg build failed: output binaries missing" >&2
  exit 1
fi

/bin/cp "$FFMPEG_BIN" "$OUTPUT_DIR/ffmpeg-$ARCH"
/bin/cp "$FFPROBE_BIN" "$OUTPUT_DIR/ffprobe-$ARCH"
/usr/bin/strip -x "$OUTPUT_DIR/ffmpeg-$ARCH" "$OUTPUT_DIR/ffprobe-$ARCH" 2>/dev/null || true

echo "Built minimal ffmpeg for $ARCH at $OUTPUT_DIR"
