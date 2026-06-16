#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-${HOME}/git}"
IGNORE_FILE="${2:-${ROOT%/}/.mcpignore}"
CONTEXT_FILE="${3:-${ROOT%/}/.mcp-context.md}"

if [[ ! -d "$ROOT" ]]; then
  echo "Root not found: $ROOT" >&2
  exit 1
fi

TMP_IGNORE="$(mktemp)"
TMP_FILES="$(mktemp)"
trap 'rm -f "$TMP_IGNORE" "$TMP_FILES"' EXIT

cat > "$TMP_IGNORE" <<'EOF'
.git
node_modules
vendor
.dist
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
.ai
EOF

if [[ -f "$IGNORE_FILE" ]]; then
  cat "$IGNORE_FILE" >> "$TMP_IGNORE"
fi

while IFS= read -r path; do
  rel="${path#${ROOT%/}/}"
  skip=0
  while IFS= read -r raw; do
    rule="${raw%%#*}"
    rule="$(printf '%s' "$rule" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$rule" ]] && continue
    rule="${rule#**/}"
    rule="${rule%/}"
    [[ -z "$rule" ]] && continue
    if [[ "$rel" == "$rule" || "$rel" == "$rule"/* || "$rel" == */"$rule" || "$rel" == */"$rule"/* ]]; then
      skip=1
      break
    fi
    if [[ "$path" == *"/$rule" || "$path" == *"/$rule/"* ]]; then
      skip=1
      break
    fi
  done < "$TMP_IGNORE"
  (( skip == 0 )) && printf '%s\n' "$path" >> "$TMP_FILES"
done < <(find "$ROOT" -type f)

filecount=$(wc -l < "$TMP_FILES" | tr -d ' ')

printf '# MCP file access context\n\n'
printf -- '- Root: `%s`\n' "$ROOT"
printf -- '- Ignore file: `%s`\n' "$IGNORE_FILE"
printf -- '- Context file hint: `%s`\n' "$CONTEXT_FILE"
printf -- '- Generated: `%s`\n' "$(date -Iseconds)"
printf -- '- Files after ignore filtering: `%s`\n\n' "$filecount"

printf '## Suggested watch file types\n\n'
awk '
function ext(path, n, a, f) {
  n=split(path,a,"/");
  f=a[n];
  if (f ~ /^\.[^.]+$/) return f;
  if (f ~ /\./) { sub(/^.*\./, "", f); return "." f }
  return "[no extension]"
}
{ print ext($0) }
' "$TMP_FILES" | sort | uniq -c | sort -nr | awk '$2 !~ /^\[no extension\]$/ { print $2 }' | paste -sd ',' - | awk '{ printf "`%s`\n\n", $0 }'

printf '## Extension histogram\n\n'
printf '```text\n'
awk '
function ext(path, n, a, f) {
  n=split(path,a,"/");
  f=a[n];
  if (f ~ /^\.[^.]+$/) return f;
  if (f ~ /\./) { sub(/^.*\./, "", f); return "." f }
  return "[no extension]"
}
{ print ext($0) }
' "$TMP_FILES" | sort | uniq -c | sort -nr
printf '```\n\n'

printf '## Priority files\n\n'
printf '```text\n'
grep -E '(^|/)(README|CLAUDE|AGENTS)(\.[^/]+)?$|(^|/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|Makefile|justfile|docker-compose(\.override)?\.ya?ml|compose\.ya?ml|flake\.nix|shell\.nix)$' "$TMP_FILES" || true
printf '```\n\n'

printf '## Watch recommendations\n\n'
printf -- '- Watch: source, docs, config, scripts.\n'
printf -- '- Do not watch: VCS metadata, dependency/vendor trees, build artifacts, caches, generated outputs, binaries.\n'
printf -- '- Start with repo root docs/config, then current project source tree.\n\n'

if [[ -f "$CONTEXT_FILE" ]]; then
  printf '## Cached context note\n\n'
  printf 'Use `%s` as the human-maintained summary for chat bootstrap and watch policy.\n\n' "$CONTEXT_FILE"
fi

printf '## Ignore rules in effect\n\n'
printf '```text\n'
cat "$TMP_IGNORE"
printf '```\n'
