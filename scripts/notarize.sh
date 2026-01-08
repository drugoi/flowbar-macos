#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${APP_PATH:-}"
ZIP_PATH="${ZIP_PATH:-}"
PROFILE="${NOTARY_PROFILE:-notarytool}"

if [[ -z "$APP_PATH" || -z "$ZIP_PATH" ]]; then
  echo "Set APP_PATH and ZIP_PATH before running." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found at $ZIP_PATH" >&2
  exit 1
fi

echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$PROFILE" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo "Validating stapled ticket..."
xcrun stapler validate "$APP_PATH"

echo "Validating code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -vvv --type exec "$APP_PATH"

echo "Notarization complete."
