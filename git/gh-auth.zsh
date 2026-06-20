# =============================================================================
# git/gh-auth.zsh — gh CLI Auth-Absicherung
# =============================================================================
# Einbinden in ~/.zshrc:
#   source ~/git/dotfiles-macos/git/gh-auth.zsh
#
# Stellt sicher dass:
#   1. credential.helper korrekt auf 'gh auth git-credential' gesetzt ist
#   2. gh-Auth beim git push/pull automatisch geprüft wird
#   3. Bei abgelaufenem Token interaktiver Re-Login ausgelöst wird
# =============================================================================

# -----------------------------------------------------------------------------
# gh-auth-check — Prüft ob gh CLI authentifiziert ist
#
# Gibt 0 zurück wenn OK, 1 wenn Auth fehlt oder Token abgelaufen.
# Kein Output im Erfolgsfall (silent check).
# -----------------------------------------------------------------------------
gh-auth-check() {
  command -v gh &>/dev/null || return 0  # gh nicht installiert — skip
  gh auth status &>/dev/null
}

# -----------------------------------------------------------------------------
# gh-auth-ensure — Stellt Auth sicher, löst Login aus wenn nötig
#
# Verwendung:
#   gh-auth-ensure          → prüft + meldet Status
#   gh-auth-ensure --quiet  → nur Fehler ausgeben
# -----------------------------------------------------------------------------
gh-auth-ensure() {
  local quiet=0
  [[ "${1}" == "--quiet" ]] && quiet=1

  command -v gh &>/dev/null || {
    (( quiet )) || echo "[gh-auth] gh CLI nicht installiert — skip"
    return 0
  }

  # credential.helper prüfen und ggf. korrigieren
  local helper
  helper=$(git config --global credential.helper 2>/dev/null)
  if [[ "${helper}" != "!gh auth git-credential" ]]; then
    echo "[gh-auth] WARNUNG: credential.helper ist '${helper}'"
    echo "[gh-auth] Korrigiere auf '!gh auth git-credential'..."
    git config --global credential.helper '!gh auth git-credential'
  fi

  # Token-Validität prüfen
  if ! gh auth status &>/dev/null; then
    echo "[gh-auth] Token abgelaufen oder ungültig — starte Re-Login..."
    gh auth login -h github.com -p https
    if ! gh auth status &>/dev/null; then
      echo "[gh-auth] FEHLER: Login fehlgeschlagen"
      return 1
    fi
    echo "[gh-auth] Erfolgreich authentifiziert als $(gh api user --jq .login 2>/dev/null)"
  else
    (( quiet )) || echo "[gh-auth] OK — $(gh auth status 2>&1 | grep 'Logged in' | sed 's/^ *//')"
  fi
}

# -----------------------------------------------------------------------------
# gp / gpush — gh-gesicherter git push
#
# Prüft Auth vor jedem Push — löst bei Bedarf Re-Login aus.
# Wrapper um 'git push' mit allen üblichen Flags.
# -----------------------------------------------------------------------------
gpush() {
  gh-auth-ensure --quiet || return 1
  git push "$@"
}

# gp als Alias (nur wenn noch nicht belegt)
if ! command -v gp &>/dev/null && [[ -z "${aliases[gp]}" ]]; then
  alias gp='gpush'
fi

# -----------------------------------------------------------------------------
# gup-safe — gh-gesichertes gup (rebase + push)
#
# Erweitert gup aus aliases.zsh um Auth-Check.
# Voraussetzung: aliases.zsh muss vorher gesourct sein.
# -----------------------------------------------------------------------------
gup-safe() {
  gh-auth-ensure --quiet || return 1
  if typeset -f gup &>/dev/null; then
    gup "$@"
  else
    echo "[gh-auth] WARNUNG: gup nicht definiert — fälle zurück auf git pull --rebase + push"
    git pull --rebase && git push "$@"
  fi
}
