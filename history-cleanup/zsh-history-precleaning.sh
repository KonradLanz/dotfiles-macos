#!/usr/bin/env zsh
# scripts/zsh-history-precleaning.sh
# Bereinigt zsh history-Dateien vor rdfind oder beim initialen Setup.
# Usage:
#   ./zsh-history-precleaning.sh              # nur Backup-Verzeichnis
#   ./zsh-history-precleaning.sh --all        # auch ~/.zsh_history selbst

set -euo pipefail

BACKUP_DIR="${ZSH_HISTORY_BACKUP_DIR:-$HOME/.zsh_history_backups}"
TARGETS=("$BACKUP_DIR")

if [[ "${1:-}" == "--all" ]]; then
  TARGETS+=("$HOME/.zsh_history")
fi

clean_file() {
  local f="$1"
  [[ -s "$f" ]] || return 0
  LC_ALL=C sed -i '' \
    -e '/^fc -W$/d' \
    -e 's/^[[:space:]]*[0-9]\{1,\}[[:space:]]\{1,\}//' \
    "$f"
}

echo "==> Pre-cleaning gestartet..."

for target in "${TARGETS[@]}"; do
  if [[ -f "$target" ]]; then
    echo "  Cleaning file: $target"
    clean_file "$target"
  elif [[ -d "$target" ]]; then
    echo "  Cleaning dir:  $target"
    find "$target" -name '*.bak' -print0 | xargs -0 -P4 -I{} zsh -c '
      f="$1"
      [[ -s "$f" ]] || exit 0
      LC_ALL=C sed -i "" \
        -e "/^fc -W$/d" \
        -e "s/^[[:space:]]*[0-9]*[[:space:]]*//" \
        "$f"
    ' _ {}
  fi
done

echo "==> Fertig."
