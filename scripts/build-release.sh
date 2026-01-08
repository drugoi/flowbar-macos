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
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

mkdir -p "$OUTPUT_DIR"

echo "Building ${SCHEME} (${CONFIGURATION})..."
XCODEBUILD_ARGS=(
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual
)

if [[ -n "$APP_VERSION" ]]; then
  XCODEBUILD_ARGS+=(MARKETING_VERSION="$APP_VERSION")
fi

if [[ -n "$BUILD_NUMBER" ]]; then
  XCODEBUILD_ARGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi

xcodebuild \
  "${XCODEBUILD_ARGS[@]}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at $APP_PATH" >&2
  exit 1
fi

ENTITLEMENTS="${ENTITLEMENTS:-$ROOT_DIR/Config/LongPlay.entitlements}"
APP_PATH="$APP_PATH" SIGN_IDENTITY="$SIGN_IDENTITY" ENTITLEMENTS="$ENTITLEMENTS" "$ROOT_DIR/scripts/sign-release.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")
ZIP_NAME="${SCHEME}-${VERSION}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "Packaging ${ZIP_NAME}..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  APP_PATH="$APP_PATH" ZIP_PATH="$ZIP_PATH" "$ROOT_DIR/scripts/notarize.sh"

  echo "Re-packaging ${ZIP_NAME} (with stapled ticket)..."
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
fi

echo "Release artifact: $ZIP_PATH"
