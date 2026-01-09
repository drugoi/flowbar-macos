#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${TAG:-}"
BRANCH="${BRANCH:-gh-pages}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APPCAST_PATH="${APPCAST_PATH:-$DIST_DIR/appcast.xml}"

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

WORKTREE_DIR="${WORKTREE_DIR:-$ROOT_DIR/build/gh-pages-worktree}"

if git worktree list | rg -q "$WORKTREE_DIR"; then
  git worktree remove --force "$WORKTREE_DIR"
fi
rm -rf "$WORKTREE_DIR"

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git worktree add "$WORKTREE_DIR" "$BRANCH"
else
  git worktree add -b "$BRANCH" "$WORKTREE_DIR"
fi

pushd "$WORKTREE_DIR" >/dev/null

git rm -r --quiet --ignore-unmatch . >/dev/null 2>&1 || true
cp "$APPCAST_PATH" "$WORKTREE_DIR/appcast.xml"
touch "$WORKTREE_DIR/.nojekyll"

git add appcast.xml .nojekyll
git commit -m "Update appcast for $TAG" >/dev/null
git push origin "$BRANCH"

popd >/dev/null
git worktree remove --force "$WORKTREE_DIR"

echo "Published appcast to $BRANCH: appcast.xml"
