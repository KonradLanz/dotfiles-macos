#!/usr/bin/env bash
# ai-checksum.sh — CRC32/SHA256 manifest generator and delta checker for .ai repos
# Usage: ai-checksum.sh [--repo DIR] [--algo crc32|sha256] [--check] [--update]
set -euo pipefail

REPO="$(pwd)"
ALGO="sha256"
CHECK=0
UPDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="$2"; shift 2 ;;
    --algo)   ALGO="$2"; shift 2 ;;
    --check)  CHECK=1;   shift   ;;
    --update) UPDATE=1;  shift   ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

AI_DIR="${REPO}/.ai"
MANIFEST="${AI_DIR}/checksums/${ALGO}.tsv"

[[ -d "$AI_DIR" ]] || { echo ".ai directory not found in $REPO" >&2; exit 1; }
mkdir -p "${AI_DIR}/checksums"

_hash_file() {
  local file="$1"
  case "$ALGO" in
    sha256)
      if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | awk '{print $1}'
      else
        shasum -a 256 "$file" | awk '{print $1}'
      fi
      ;;
    crc32)
      if command -v crc32 &>/dev/null; then
        crc32 "$file" | awk '{print $1}'
      elif command -v python3 &>/dev/null; then
        python3 -c "import sys,zlib,struct; data=open(sys.argv[1],'rb').read(); print('%08x' % (zlib.crc32(data)&0xffffffff))" "$file"
      else
        echo "crc32 unavailable" >&2; exit 1
      fi
      ;;
    *) echo "Unknown algo: $ALGO" >&2; exit 1 ;;
  esac
}

_scan() {
  local dir="$1"
  local ignore="${AI_DIR}/ignore"
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
    done < <(printf '.git\n.ai\nnode_modules\nvendor\ndist\nbuild\n.cache\n.venv\n__pycache__\n'; [[ -f "$ignore" ]] && cat "$ignore")
    (( skip == 0 )) && printf '%s\n' "$path"
  done
}

if [[ $CHECK -eq 1 ]]; then
  if [[ ! -f "$MANIFEST" ]]; then
    echo "No manifest found at $MANIFEST. Run --update first." >&2
    exit 1
  fi
  printf '# Checksum delta (%s)\n\n' "$ALGO"
  changed=0
  while IFS=$'\t' read -r stored_hash rel; do
    file="${REPO}/${rel}"
    if [[ ! -f "$file" ]]; then
      printf -- '- DELETED\t%s\n' "$rel"
      (( changed++ )) || true
    else
      current="$(_hash_file "$file")"
      if [[ "$current" != "$stored_hash" ]]; then
        printf -- '- CHANGED\t%s\n' "$rel"
        (( changed++ )) || true
      fi
    fi
  done < "$MANIFEST"
  new_files="$(_scan "$REPO" | while IFS= read -r path; do
    rel="${path#${REPO%/}/}"
    if ! grep -qF $'\t'"$rel" "$MANIFEST" 2>/dev/null; then
      printf -- '- NEW\t%s\n' "$rel"
    fi
  done)"
  [[ -n "$new_files" ]] && printf '%s\n' "$new_files" && (( changed++ )) || true
  printf '\n---\n%d change(s) detected.\n' "$changed"
elif [[ $UPDATE -eq 1 ]]; then
  printf '' > "$MANIFEST"
  while IFS= read -r path; do
    rel="${path#${REPO%/}/}"
    hash="$(_hash_file "$path")"
    printf '%s\t%s\n' "$hash" "$rel" >> "$MANIFEST"
  done < <(_scan "$REPO")
  count=$(wc -l < "$MANIFEST" | tr -d ' ')
  printf 'Manifest updated: %s (%d files)\n' "$MANIFEST" "$count"
else
  echo "Specify --check or --update" >&2
  exit 1
fi
