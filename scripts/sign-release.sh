#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/Config/LongPlay.entitlements}"
TOOL_ENTITLEMENTS="${TOOL_ENTITLEMENTS:-$ROOT_DIR/Config/EmbeddedTool.entitlements}"

if [[ -z "$APP_PATH" || -z "$SIGN_IDENTITY" ]]; then
  echo "Set APP_PATH and SIGN_IDENTITY before running." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

BIN_DIR="$APP_PATH/Contents/Resources/bin"
if [[ -d "$BIN_DIR" ]]; then
  while IFS= read -r -d '' bin; do
    echo "Signing embedded binary: $bin"
    if [[ "$(basename "$bin")" == "yt-dlp" ]]; then
      codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements "$TOOL_ENTITLEMENTS" "$bin"
    else
      codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$bin"
    fi
  done < <(find "$BIN_DIR" -type f -perm -111 -print0)
fi

echo "Signing app bundle: $APP_PATH"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP_PATH"
