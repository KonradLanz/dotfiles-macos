#!/usr/bin/env zsh
# =============================================================================
# clean-history-autopull.sh — Auto-Pull Wrapper für clean-history.sh
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history-autopull.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history-autopull.sh --dry-run
#
# Alias in .zshrc:
#   alias hclean='zsh ~/git/dotfiles-macos/history-cleanup/clean-history-autopull.sh'
#
# Ablauf:
#   1. git pull --ff-only im Repo
#   2. Already up to date → direkt weiter
#   3. Neue Version gezogen → zeigt Änderungen, fragt ob neu starten
#   4. Pull fehlgeschlagen → fragt ob mit lokaler Version weitermachen
#   5. exec zsh clean-history.sh "$@" — ersetzt diesen Prozess (kein doppelter Shell-Stack)
# =============================================================================

_SCRIPT_DIR="${${(%):-%x}:A:h}"
_MAIN_SCRIPT="${_SCRIPT_DIR}/clean-history.sh"
_REPO_DIR="${_SCRIPT_DIR}/.."

# Farben
_C_RESET='\033[0m'
_C_GREEN='\033[0;32m'
_C_YELLOW='\033[1;33m'
_C_RED='\033[0;31m'
_C_BOLD='\033[1m'

echo ""
echo "🔄 Auto-Pull — dotfiles-macos..."

_PULL_OUT=$(git -C "${_REPO_DIR}" pull --ff-only 2>&1)
_PULL_RC=$?

if [[ ${_PULL_RC} -ne 0 ]]; then
  # --- Pull fehlgeschlagen ---
  printf "${_C_RED}   ✗ git pull fehlgeschlagen:${_C_RESET}\n"
  printf '%s\n' "${_PULL_OUT}" | sed 's/^/     /'
  echo ""
  printf "   Mit lokaler Version trotzdem starten? [J/n] "
  IFS= read -r _REPLY < /dev/tty
  if [[ "${_REPLY}" == "n" || "${_REPLY}" == "N" ]]; then
    echo "   → Abgebrochen."
    exit 1
  fi
  echo "   → Starte mit lokaler Version..."
  echo ""
  exec zsh "${_MAIN_SCRIPT}" "$@"
fi

if printf '%s' "${_PULL_OUT}" | grep -q 'Already up to date'; then
  # --- Bereits aktuell ---
  printf "${_C_GREEN}   ✓ Bereits aktuell${_C_RESET}\n"
  echo ""
  exec zsh "${_MAIN_SCRIPT}" "$@"
fi

# --- Neue Version gezogen ---
printf "${_C_GREEN}   ✓ Neue Version gezogen:${_C_RESET}\n"
printf '%s\n' "${_PULL_OUT}" | sed 's/^/     /'

# Zeige was sich im Hauptscript geändert hat (falls vorhanden)
_DIFF_STAT=$(git -C "${_REPO_DIR}" diff HEAD@{1} HEAD -- history-cleanup/clean-history.sh 2>/dev/null \
  | grep '^[+-]' | grep -v '^[+-][+-][+-]' | head -20)
if [[ -n "${_DIFF_STAT}" ]]; then
  echo ""
  printf "   ${_C_BOLD}Änderungen in clean-history.sh:${_C_RESET}\n"
  printf '%s\n' "${_DIFF_STAT}" | head -20 | sed 's/^/     /'
  _MORE=$(printf '%s\n' "${_DIFF_STAT}" | wc -l | tr -d ' ')
  [[ ${_MORE} -ge 20 ]] && echo "     … (git diff HEAD@{1} HEAD -- history-cleanup/clean-history.sh für mehr)"
fi

echo ""
printf "   Jetzt mit neuer Version starten? [J/n] "
IFS= read -r _REPLY < /dev/tty
if [[ "${_REPLY}" == "n" || "${_REPLY}" == "N" ]]; then
  echo "   → Abgebrochen."
  exit 0
fi

echo ""
exec zsh "${_MAIN_SCRIPT}" "$@"
