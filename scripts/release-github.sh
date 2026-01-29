#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-}"
NOTES_FILE="${NOTES_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ROOT_DIR/.env"
  set +a
fi

if [[ -z "$TAG" ]]; then
  echo "Set TAG (e.g. TAG=v0.1.0) before running." >&2
  exit 1
fi

APP_VERSION="$TAG"
if [[ "$APP_VERSION" == v* ]]; then
  APP_VERSION="${APP_VERSION#v}"
fi

if [[ -z "$APP_VERSION" ]]; then
  echo "Invalid TAG: $TAG" >&2
  exit 1
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")
fi

APP_VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" NOTARIZE="${NOTARIZE:-1}" "$ROOT_DIR/scripts/build-release.sh"

ZIP_PATH=$(ls -t "$OUTPUT_DIR"/FlowBar-*.zip | head -n 1 || true)
if [[ -z "$ZIP_PATH" ]]; then
  echo "No release zip found in $OUTPUT_DIR" >&2
  exit 1
fi

echo "Verifying release artifact..."
"$ROOT_DIR/scripts/verify-zip.sh" "$ZIP_PATH"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required for releases." >&2
  exit 1
fi

if [[ -z "$NOTES_FILE" ]]; then
  mkdir -p "$OUTPUT_DIR"
  NOTES_FILE="$OUTPUT_DIR/release-notes-$TAG.md"
  TARGET_REF="HEAD"
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    TARGET_REF="$TAG"
  fi
  PREV_TAG=$(git describe --tags --abbrev=0 "${TARGET_REF}^" 2>/dev/null || true)
  if [[ -n "$PREV_TAG" ]]; then
    RANGE="$PREV_TAG..$TARGET_REF"
  else
    RANGE="$TARGET_REF"
  fi
  CHANGES=$(git log --no-merges --pretty=format:'- %s (%h)' "$RANGE" || true)
  if [[ -z "$CHANGES" ]]; then
    CHANGES="- No changes."
  fi
  {
    echo "## What's Changed"
    echo "$CHANGES"
    if [[ -n "$PREV_TAG" ]]; then
      REMOTE_URL=$(git config --get remote.origin.url || true)
      if [[ "$REMOTE_URL" =~ github\.com[:/]{1}([^/]+/[^/.]+)(\.git)?$ ]]; then
        echo
        echo "Full Changelog: https://github.com/${BASH_REMATCH[1]}/compare/$PREV_TAG...$TAG"
      fi
    fi
  } > "$NOTES_FILE"
fi

ARGS=(release create "$TAG" "$ZIP_PATH" --title "FlowBar $TAG")
if [[ -n "$NOTES_FILE" ]]; then
  ARGS+=(--notes-file "$NOTES_FILE")
else
  ARGS+=(--generate-notes)
fi

echo "Creating GitHub release $TAG..."
gh "${ARGS[@]}"
echo "Release published with asset: $ZIP_PATH"

if [[ "${PUBLISH_APPCAST:-0}" == "1" ]]; then
  echo "Publishing appcast to GitHub Pages..."
  TAG="$TAG" "$ROOT_DIR/scripts/publish-appcast.sh"
fi
