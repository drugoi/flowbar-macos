#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build}"
CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-LongPlay}"
TEAM_ID="${TEAM_ID:-K6H76QJBE9}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Nikita Bayev (${TEAM_ID})}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
NOTARIZE="${NOTARIZE:-0}"

mkdir -p "$OUTPUT_DIR"

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/Config/LongPlay.entitlements}"
APP_PATH="$APP_PATH" SIGN_IDENTITY="$SIGN_IDENTITY" ENTITLEMENTS="$ENTITLEMENTS" "$ROOT_DIR/scripts/sign-release.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
ZIP_NAME="${SCHEME}-${VERSION}.zip"

echo "Packaging ${ZIP_NAME}..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/$ZIP_NAME"

if [[ "$NOTARIZE" == "1" ]]; then
  APP_PATH="$APP_PATH" ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME" "$ROOT_DIR/scripts/notarize.sh"
fi

echo "Release artifact: $OUTPUT_DIR/$ZIP_NAME"
