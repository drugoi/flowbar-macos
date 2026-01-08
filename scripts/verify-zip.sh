#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-${ZIP_PATH:-}}"

if [[ -z "$ZIP_PATH" ]]; then
  ZIP_PATH=$(ls -t "$ROOT_DIR"/dist/LongPlay-*.zip 2>/dev/null | head -n 1 || true)
fi

if [[ -z "$ZIP_PATH" || ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found. Pass a path or set ZIP_PATH." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Extracting: $ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$TMP_DIR"

APP_PATH=$(find "$TMP_DIR" -maxdepth 2 -name "*.app" -type d -print -quit)
if [[ -z "$APP_PATH" ]]; then
  echo "No .app found in zip." >&2
  exit 1
fi

echo "Validating stapled ticket..."
xcrun stapler validate "$APP_PATH"

echo "Validating code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Validating Gatekeeper assessment..."
spctl -a -vvv --type exec "$APP_PATH"

echo "OK: $APP_PATH"
