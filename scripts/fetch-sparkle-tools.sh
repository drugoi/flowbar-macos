#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
TOOLS_DIR="${TOOLS_DIR:-$ROOT_DIR/build/sparkle-tools/$SPARKLE_VERSION}"
BIN_DIR="$TOOLS_DIR/bin"

if [[ -x "$BIN_DIR/generate_appcast" && -x "$BIN_DIR/sign_update" ]]; then
  echo "Sparkle tools already present: $BIN_DIR"
  exit 0
fi

mkdir -p "$BIN_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
ARCHIVE_PATH="$TMP_DIR/Sparkle-${SPARKLE_VERSION}.tar.xz"

echo "Downloading Sparkle tools (${SPARKLE_VERSION})..."
curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"

echo "Extracting..."
tar -xJf "$ARCHIVE_PATH" -C "$TMP_DIR"

if [[ ! -d "$TMP_DIR/bin" ]]; then
  echo "Unexpected archive layout; missing bin/ at archive root" >&2
  exit 1
fi

cp -f "$TMP_DIR/bin/generate_appcast" "$BIN_DIR/generate_appcast"
cp -f "$TMP_DIR/bin/sign_update" "$BIN_DIR/sign_update"
if [[ -f "$TMP_DIR/bin/generate_keys" ]]; then
  cp -f "$TMP_DIR/bin/generate_keys" "$BIN_DIR/generate_keys"
fi

chmod +x "$BIN_DIR/"*
echo "Sparkle tools installed: $BIN_DIR"
