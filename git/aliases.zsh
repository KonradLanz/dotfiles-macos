# =============================================================================
# git/aliases.zsh — Git-Aliases für dotfiles-macos
# =============================================================================
# Einbinden in ~/.zshrc:
#   source ~/git/dotfiles-macos/git/aliases.zsh
# =============================================================================

# -----------------------------------------------------------------------------
# gup — Fast-Forward Rebase + Push
#
# Holt remote-Änderungen via rebase (kein Merge-Commit),
# dann pusht die lokalen Commits.
#
# Verwendung:
#   gup              → rebase + push auf aktuellen Branch
#   gup "Nachricht"  → staged changes committen, dann rebase + push
# -----------------------------------------------------------------------------
gup() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -z "${branch}" ]]; then
    echo "❌ gup: kein git-Branch gefunden" >&2
    return 1
  fi

  # Optional: commit wenn Argument übergeben
  if [[ -n "$1" ]]; then
    git add -A
    git commit -m "$1" || return 1
  fi

  echo "🔄 gup: rebase origin/${branch}..."
  git fetch origin "${branch}" || return 1
  git rebase "origin/${branch}" || {
    echo "⚠️  Rebase-Konflikt — löse auf und führe 'git rebase --continue' aus"
    return 1
  }

  echo "🚀 gup: push origin/${branch}"
  git push origin "${branch}" || return 1
  echo "✅ gup: fertig (${branch})"
}

# Kurzform ohne Commit-Nachricht
alias gpull='git fetch origin && git rebase origin/$(git symbolic-ref --short HEAD)'
alias gpush='git push origin $(git symbolic-ref --short HEAD)'
