#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TAG="${TAG:-}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
OUTPUT_PATH="${OUTPUT_PATH:-$DIST_DIR/appcast.xml}"

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

REMOTE_URL=$(git config --get remote.origin.url || true)
if [[ "$REMOTE_URL" =~ github\.com[:/]{1}([^/]+/[^/.]+)(\.git)?$ ]]; then
  REPO="${REPO:-${BASH_REMATCH[1]}}"
else
  REPO="${REPO:-}"
fi

if [[ -z "$REPO" ]]; then
  echo "Unable to infer GitHub repo; set REPO=owner/name." >&2
  exit 1
fi

SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"
"$ROOT_DIR/scripts/fetch-sparkle-tools.sh" >/dev/null
TOOLS_BIN="$ROOT_DIR/build/sparkle-tools/$SPARKLE_VERSION/bin"

DOWNLOAD_URL_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

ARGS=()
if [[ -z "${SPARKLE_ED25519_PRIVATE_KEY:-}" ]]; then
  if [[ "${ALLOW_UNSIGNED_APPCAST:-0}" != "1" ]]; then
    echo "Missing SPARKLE_ED25519_PRIVATE_KEY; required for signed Sparkle updates." >&2
    echo "Set ALLOW_UNSIGNED_APPCAST=1 to generate an unsigned appcast (not recommended)." >&2
    exit 1
  fi
else
  TMP_KEY="$(mktemp)"
  trap 'rm -f "$TMP_KEY"' EXIT
  printf "%s" "$SPARKLE_ED25519_PRIVATE_KEY" > "$TMP_KEY"
  chmod 600 "$TMP_KEY"
  ARGS+=(--ed-key-file "$TMP_KEY")
fi

if [[ ! -d "$DIST_DIR" ]]; then
  echo "dist/ not found at $DIST_DIR; run scripts/build-release.sh first." >&2
  exit 1
fi

echo "Generating appcast for $REPO ($TAG)..."
ARGS+=(--download-url-prefix "$DOWNLOAD_URL_PREFIX")
ARGS+=(-o "$OUTPUT_PATH")
ARGS+=("$DIST_DIR")

"$TOOLS_BIN/generate_appcast" "${ARGS[@]}"

echo "Wrote: $OUTPUT_PATH"
