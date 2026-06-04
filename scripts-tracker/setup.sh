#!/usr/bin/env zsh
# =============================================================================
# setup.sh — Scripts Tracker einrichten
# =============================================================================
# Legt ~/scripts/ an, initialisiert git, fügt paste-to-script.zsh in .zshrc ein
# =============================================================================

set -euo pipefail
SCRIPTS_DIR="${HOME}/scripts"
ZSHRC="${HOME}/.zshrc"
DOTFILES_DIR="${HOME}/git/dotfiles-macos"

echo "=== Scripts Tracker Setup ==="

# Ordner anlegen
if [[ ! -d "${SCRIPTS_DIR}" ]]; then
  mkdir -p "${SCRIPTS_DIR}"
  echo "✓ ${SCRIPTS_DIR} erstellt"
else
  echo "  ${SCRIPTS_DIR} existiert bereits"
fi

# .gitignore
cat > "${SCRIPTS_DIR}/.gitignore" << 'EOF'
# Keine temporären Dateien
*.tmp
*.bak
*.log

# Keine Credentials
*secret*
*password*
*token*
*key*
EOF
echo "✓ .gitignore erstellt"

# Git init
if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
  cd "${SCRIPTS_DIR}"
  git init -b main
  git add .gitignore
  git commit -m "init: scripts tracker"
  echo "✓ git init in ${SCRIPTS_DIR}"
else
  echo "  git bereits initialisiert"
fi

# ~/bin in PATH sicherstellen (für fertige Tools)
if [[ ! -d "${HOME}/bin" ]]; then
  mkdir -p "${HOME}/bin"
fi

# find-safe installieren
FIND_SAFE_SRC="${DOTFILES_DIR}/history-cleanup/find-safe.sh"
FIND_SAFE_DST="${HOME}/bin/find-safe"
if [[ -f "${FIND_SAFE_SRC}" ]]; then
  cp "${FIND_SAFE_SRC}" "${FIND_SAFE_DST}"
  chmod +x "${FIND_SAFE_DST}"
  echo "✓ find-safe installiert nach ${FIND_SAFE_DST}"
fi

# .zshrc einträge hinzufügen (idempotent)
SOURCE_LINE="source ${DOTFILES_DIR}/scripts-tracker/paste-to-script.zsh"
PATH_LINE="export PATH=\"\${HOME}/bin:\${PATH}\""

if ! grep -qF "paste-to-script.zsh" "${ZSHRC}" 2>/dev/null; then
  echo "" >> "${ZSHRC}"
  echo "# Scripts Tracker" >> "${ZSHRC}"
  echo "${PATH_LINE}" >> "${ZSHRC}"
  echo "${SOURCE_LINE}" >> "${ZSHRC}"
  echo "✓ .zshrc erweitert"
else
  echo "  .zshrc bereits konfiguriert"
fi

echo ""
echo "=== Fertig ==="
echo "  ~/scripts/      ← dein Script-Ordner (git-getrackt)"
echo "  ~/bin/          ← fertige Tools (im PATH)"
echo "  find-safe       ← find mit komprimierter Fehlerausgabe"
echo ""
echo "Jetzt: source ~/.zshrc (oder neues Terminal öffnen)"
echo "Dann:  save-script mein-script-name"
