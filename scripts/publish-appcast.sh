#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APPCAST_PATH="${APPCAST_PATH:-$DIST_DIR/appcast.xml}"
PAGES_DIR="${PAGES_DIR:-$ROOT_DIR/docs}"

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

TAG="$TAG" DIST_DIR="$DIST_DIR" OUTPUT_PATH="$APPCAST_PATH" "$ROOT_DIR/scripts/generate-appcast.sh"

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "Appcast not found at $APPCAST_PATH" >&2
  exit 1
fi

mkdir -p "$PAGES_DIR"
cp "$APPCAST_PATH" "$PAGES_DIR/appcast.xml"

git add "$PAGES_DIR/appcast.xml"
git commit -m "Update appcast for $TAG" >/dev/null

echo "Published appcast to docs/: $PAGES_DIR/appcast.xml"
