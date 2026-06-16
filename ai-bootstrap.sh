#!/usr/bin/env bash
# ai-bootstrap.sh — Meta-context bootstrap for .ai-enabled repos
# Usage: ai-bootstrap.sh [--mode overview|focused|deep] [--root DIR] [--repo DIR]
#                        [--peers] [--depth N] [--since-last] [--no-cycle-check]
set -euo pipefail

MODE="focused"
ROOT="${HOME}/git"
REPO=""
DEPTH=2
PEERS=0
SINCE_LAST=0
CYCLE_CHECK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     MODE="$2";      shift 2 ;;
    --root)     ROOT="$2";      shift 2 ;;
    --repo)     REPO="$2";      shift 2 ;;
    --depth)    DEPTH="$2";     shift 2 ;;
    --peers)    PEERS=1;        shift   ;;
    --since-last) SINCE_LAST=1; shift   ;;
    --no-cycle-check) CYCLE_CHECK=0; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── helpers ──────────────────────────────────────────────────────────────────

_heading() { printf '\n## %s\n\n' "$1"; }
_item()    { printf -- '- %s\n' "$1"; }
_code()    { printf '```\n%s\n```\n' "$1"; }

_canonical() {
  if command -v realpath &>/dev/null; then
    realpath "$1" 2>/dev/null || echo "$1"
  else
    cd "$1" 2>/dev/null && pwd -P
  fi
}

# Global visited set for cycle detection (canonical paths, newline-separated)
VISITED=""

_visited() {
  local canon="$1"
  if [[ "$CYCLE_CHECK" == "1" ]]; then
    if [[ "$VISITED" == *"$canon"* ]]; then return 1; fi
    VISITED="${VISITED}${canon}\n"
  fi
  return 0
}

_print_context_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  printf '```markdown\n'
  cat "$file"
  printf '```\n\n'
}

_print_state() {
  local dir="$1"
  local state="${dir}/.ai/state.json"
  [[ -f "$state" ]] || return 0
  printf '```json\n'
  cat "$state"
  printf '```\n\n'
}

_print_filetype_summary() {
  local dir="$1"
  local ignore="${dir}/.ai/ignore"
  local tmpf tmpig
  tmpf="$(mktemp)" tmpig="$(mktemp)"
  trap 'rm -f "$tmpf" "$tmpig"' RETURN

  # collect default + repo ignore
  printf '.git\n.ai\nnode_modules\nvendor\ndist\nbuild\ncoverage\n.cache\n.next\n.venv\nvenv\n__pycache__\nDerivedData\n' > "$tmpig"
  [[ -f "$ignore" ]] && cat "$ignore" >> "$tmpig"

  find "$dir" -type f | while IFS= read -r path; do
    local rel="${path#${dir%/}/}"
    local skip=0
    while IFS= read -r rule; do
      rule="${rule%%#*}"
      rule="$(printf '%s' "$rule" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$rule" ]] && continue
      rule="${rule#**/}" ; rule="${rule%/}"
      [[ -z "$rule" ]] && continue
      if [[ "$rel" == "$rule" || "$rel" == "$rule"/* || "$rel" == */"$rule" || "$rel" == */"$rule"/* ]]; then
        skip=1; break
      fi
    done < "$tmpig"
    (( skip == 0 )) && printf '%s\n' "$path" >> "$tmpf"
  done

  awk '
  function ext(p,   n,a,f) {
    n=split(p,a,"/"); f=a[n];
    if (f~/^\.[^.]+$/) return f
    if (f~/\./) { sub(/^.*\./,"",f); return "."f }
    return "[none]"
  }
  { print ext($0) }
  ' "$tmpf" | sort | uniq -c | sort -nr | awk 'NR<=12 { printf "  %4d  %s\n", $1, $2 }'
}

_print_priority_files() {
  local dir="$1"
  find "$dir" -maxdepth 3 -type f 2>/dev/null | \
    grep -E '(^|/)(README|CLAUDE|AGENTS)(\.[^/]+)?$|(^|/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|Makefile|justfile|docker-compose(\.override)?\.ya?ml|compose\.ya?ml|flake\.nix)$' 2>/dev/null | \
    sed "s|^${dir%/}/||" | head -n 10 || true
}

_delta_since_last() {
  local dir="$1"
  local state="${dir}/.ai/state.json"
  if [[ ! -f "$state" ]]; then
    printf '(no state.json, full scan)\n'
    return
  fi
  local last
  last="$(grep -o '"last_bootstrap"[[:space:]]*:[[:space:]]*"[^"]*"' "$state" 2>/dev/null | grep -o '"[^"]*"$' | tr -d '"' || true)"
  if [[ -z "$last" || "$last" == "null" ]]; then
    printf '(no previous bootstrap recorded)\n'
    return
  fi
  printf 'Changed since %s:\n' "$last"
  find "$dir" -newer "$state" -type f \
    -not -path '*/.git/*' -not -path '*/.ai/cache/*' -not -path '*/node_modules/*' -not -path '*/dist/*' \
    | sed "s|^${dir%/}/||" | head -n 30 || true
}

_peer_repos() {
  local dir="$1"
  local depth="$2"
  local scan_root
  scan_root="$(dirname "$dir")"

  find "$scan_root" -mindepth 1 -maxdepth "$depth" -type d \( -name .git -o -name node_modules -o -name .ai -o -name dist -o -name build \) -prune \
    -o -type d -name '.ai' -print 2>/dev/null | while IFS= read -r ai_dir; do
    local peer_repo
    peer_repo="$(dirname "$ai_dir")"
    [[ "$peer_repo" == "$dir" ]] && continue
    local canon
    canon="$(_canonical "$peer_repo")"
    _visited "$canon" || continue
    rel="${peer_repo#${scan_root}/}"
    printf '  - %s' "$rel"
    if [[ -L "$peer_repo" ]]; then
      printf ' → symlink: %s' "$(readlink "$peer_repo")"
    fi
    printf '\n'
    if [[ -f "${peer_repo}/.ai/context.md" ]]; then
      printf '    (context: %s/.ai/context.md)\n' "$rel"
    fi
  done
}

_overview() {
  printf '# AI Workspace overview\n\n'
  _item "Root: \`${ROOT}\`"
  _item "Mode: overview"
  _item "Depth: ${DEPTH}"
  _item "Generated: $(date -Iseconds)"
  printf '\n'

  _heading 'Repos with .ai layer'
  find "$ROOT" -mindepth 1 -maxdepth "$DEPTH" -type d \( -name .git -o -name node_modules -o -name dist -o -name build \) -prune \
    -o -type d -name '.ai' -print 2>/dev/null | while IFS= read -r ai_dir; do
    local repo_dir
    repo_dir="$(dirname "$ai_dir")"
    local canon
    canon="$(_canonical "$repo_dir")"
    _visited "$canon" || continue
    local rel="${repo_dir#${ROOT%/}/}"
    local ctx_note=""
    [[ -f "${repo_dir}/.ai/context.md" ]] && ctx_note=" (context)"
    if [[ -L "$repo_dir" ]]; then
      _item "\`${rel}\`${ctx_note} → symlink: $(readlink "$repo_dir")"
    else
      _item "\`${rel}\`${ctx_note}"
    fi
  done
}

_focused() {
  local dir="${REPO:-${ROOT}}"
  local canon
  canon="$(_canonical "$dir")"
  _visited "$canon"

  printf '# AI Focused context: %s\n\n' "$(basename "$dir")"
  _item "Repo: \`${dir}\`"
  _item "Mode: focused"
  _item "Generated: $(date -Iseconds)"
  printf '\n'

  if [[ -f "${dir}/.ai/context.md" ]]; then
    _heading 'context.md'
    _print_context_file "${dir}/.ai/context.md"
  fi

  if [[ -f "${dir}/.ai/state.json" ]]; then
    _heading 'State'
    _print_state "$dir"
  fi

  _heading 'Priority files'
  _code "$(_print_priority_files "$dir")"

  _heading 'File type summary (top 12)'
  printf '```text\n'
  _print_filetype_summary "$dir"
  printf '```\n\n'

  if [[ $PEERS -eq 1 ]]; then
    _heading 'Peer repos'
    _peer_repos "$dir" "$DEPTH"
  fi
}

_deep() {
  local dir="${REPO:-${ROOT}}"
  local canon
  canon="$(_canonical "$dir")"
  _visited "$canon"

  printf '# AI Deep context: %s\n\n' "$(basename "$dir")"
  _item "Repo: \`${dir}\`"
  _item "Mode: deep"
  _item "Generated: $(date -Iseconds)"
  printf '\n'

  if [[ -f "${dir}/.ai/context.md" ]]; then
    _heading 'context.md'
    _print_context_file "${dir}/.ai/context.md"
  fi

  _heading 'State'
  _print_state "$dir"

  _heading 'Priority files'
  _code "$(_print_priority_files "$dir")"

  _heading 'File type summary (top 12)'
  printf '```text\n'
  _print_filetype_summary "$dir"
  printf '```\n\n'

  if [[ $SINCE_LAST -eq 1 ]]; then
    _heading 'Delta since last bootstrap'
    printf '```text\n'
    _delta_since_last "$dir"
    printf '```\n\n'
  fi

  if [[ -d "${dir}/.ai/checksums" ]]; then
    local manifests
    manifests="$(ls "${dir}/.ai/checksums/" 2>/dev/null | head -n 5)"
    if [[ -n "$manifests" ]]; then
      _heading 'Checksum manifests'
      printf '```text\n%s\n```\n\n' "$manifests"
    fi
  fi

  if [[ -d "${dir}/.ai/sessions" ]]; then
    local sessions
    sessions="$(ls -t "${dir}/.ai/sessions/" 2>/dev/null | head -n 5)"
    if [[ -n "$sessions" ]]; then
      _heading 'Recent sessions'
      printf '```text\n%s\n```\n\n' "$sessions"
    fi
  fi

  if [[ $PEERS -eq 1 ]]; then
    _heading 'Peer repos'
    _peer_repos "$dir" "$DEPTH"
  fi
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$MODE" in
  overview) _overview ;;
  focused)  _focused  ;;
  deep)     _deep     ;;
  *) echo "Unknown mode: $MODE (use overview|focused|deep)" >&2; exit 1 ;;
esac
