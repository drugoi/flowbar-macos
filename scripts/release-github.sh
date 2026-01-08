#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-}"
NOTES_FILE="${NOTES_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"

if [[ -z "$TAG" ]]; then
  echo "Set TAG (e.g. TAG=v0.1.0) before running." >&2
  exit 1
fi

"$ROOT_DIR/scripts/build-release.sh"

ZIP_PATH=$(ls -t "$OUTPUT_DIR"/LongPlay-*.zip | head -n 1 || true)
if [[ -z "$ZIP_PATH" ]]; then
  echo "No release zip found in $OUTPUT_DIR" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required for releases." >&2
  exit 1
fi

ARGS=(release create "$TAG" "$ZIP_PATH" --title "LongPlay $TAG")
if [[ -n "$NOTES_FILE" ]]; then
  ARGS+=(--notes-file "$NOTES_FILE")
else
  ARGS+=(--generate-notes)
fi

echo "Creating GitHub release $TAG..."
gh "${ARGS[@]}"
echo "Release published with asset: $ZIP_PATH"
