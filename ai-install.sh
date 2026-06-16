#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="${1:-$(pwd)}"
TEMPLATE_SOURCE="${2:-/Users/koni/git/dotfiles-macos/ai-template}"

if [[ ! -d "$TARGET_REPO" ]]; then
  echo "Target repo not found: $TARGET_REPO" >&2
  exit 1
fi

mkdir -p "$TARGET_REPO/.ai"
mkdir -p "$TARGET_REPO/.ai/sessions" "$TARGET_REPO/.ai/checksums" "$TARGET_REPO/.ai/manifests" "$TARGET_REPO/.ai/cache"

if [[ -d "$TEMPLATE_SOURCE" ]]; then
  cp -R "$TEMPLATE_SOURCE"/. "$TARGET_REPO/.ai/"
fi

cat > "$TARGET_REPO/.ai/context.md" <<'EOF'
# Repo context

Describe the repo purpose, main entry points, active work areas, and what an AI helper should inspect first.
EOF

cat > "$TARGET_REPO/.ai/ignore" <<'EOF'
.git
.ai/cache
node_modules
vendor
dist
build
coverage
.cache
.next
.nuxt
.venv
venv
__pycache__
DerivedData
EOF

cat > "$TARGET_REPO/.ai/watch-policy.json" <<'EOF'
{
  "watch_extensions": ["md", "adoc", "asciidoc", "sh", "zsh", "swift", "py", "js", "ts", "json", "yaml", "yml"],
  "ignore_paths": [".git", ".ai/cache", "node_modules", "vendor", "dist", "build", "coverage", ".cache", ".next", ".nuxt", ".venv", "venv", "__pycache__", "DerivedData"],
  "notes": "Prefer source, docs, config, and scripts. Avoid generated outputs and VCS internals."
}
EOF

cat > "$TARGET_REPO/.ai/state.json" <<'EOF'
{
  "last_bootstrap": null,
  "last_focus": null,
  "last_summary": null,
  "peers": [],
  "visited": []
}
EOF

cat > "$TARGET_REPO/.ai/README.md" <<'EOF'
# .ai

Local AI helper state for repo bootstrap, context reuse, ignore rules, watch policy, checksums, and session notes.
EOF

echo "Installed .ai scaffold in $TARGET_REPO/.ai"
