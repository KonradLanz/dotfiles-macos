#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-${HOME}/git}"
MAX_DEPTH="${2:-3}"
FOLLOW_SYMLINKS="${FOLLOW_SYMLINKS:-0}"

if [[ ! -d "$ROOT" ]]; then
  echo "Root not found: $ROOT" >&2
  exit 1
fi

find_args=("$ROOT")
if [[ "$FOLLOW_SYMLINKS" == "1" ]]; then
  find_args=(-L "$ROOT")
fi

find "${find_args[@]}" -mindepth 1 -maxdepth "$MAX_DEPTH" -type d \( -name .git -o -name node_modules -o -name .ai -o -name dist -o -name build -o -name .cache \) -prune -o -type d -print | while IFS= read -r dir; do
  if [[ -d "$dir/.ai" ]]; then
    rel="${dir#$ROOT/}"
    printf 'repo\t%s\n' "$rel"
    if [[ -f "$dir/.ai/context.md" ]]; then
      printf 'context\t%s/.ai/context.md\n' "$rel"
    fi
    if [[ -L "$dir" ]]; then
      target="$(readlink "$dir" || true)"
      printf 'symlink\t%s\t%s\n' "$rel" "$target"
    fi
  fi
done
