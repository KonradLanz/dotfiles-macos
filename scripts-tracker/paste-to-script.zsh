# =============================================================================
# paste-to-script.zsh — Intelligenter Script-Saver für zsh
# =============================================================================
# Einbinden in ~/.zshrc:
#   source ~/git/dotfiles-macos/scripts-tracker/paste-to-script.zsh
#
# Optional: Paste-Hook aktivieren (>3 Zeilen = Nachfrage)
#   PASTE_TO_SCRIPT_HOOK=1
#
# Bereitgestellte Funktionen:
#   save-script [name]    — aktuellen/letzten Command als Script speichern
#   scripts               — ~/scripts/ auflisten
#   scripts-log           — git log der Scripts
# =============================================================================

SCRIPTS_DIR="${HOME}/scripts"

# -----------------------------------------------------------------------------
# save-script: Speichert einen Block als datiertes Script in ~/scripts/
# -----------------------------------------------------------------------------
save-script() {
  local name="$1"
  local date_prefix=$(date +%Y%m%d)
  local filename
  local filepath

  # Name bestimmen
  if [[ -z "${name}" ]]; then
    # Namensvorschlag aus letztem History-Eintrag ableiten
    local last_cmd=$(fc -ln -1 | sed 's/^[[:space:]]*//' | awk '{print $1}' | tr -cd 'a-z0-9_-')
    local suggestion="${date_prefix}_${last_cmd}_script"
    echo "→ Script speichern in: ~/scripts/"
    echo -n "   Name [${suggestion}]: "
    read name
    name="${name:-${suggestion}}"
  fi

  # .sh suffix sicherstellen
  [[ "${name}" != *.sh ]] && name="${name}.sh"

  # Datumprefix hinzufügen wenn nicht vorhanden
  if [[ ! "${name}" =~ ^[0-9]{8}_ ]]; then
    name="${date_prefix}_${name}"
  fi

  filepath="${SCRIPTS_DIR}/${name}"

  # Ordner anlegen falls nicht vorhanden
  mkdir -p "${SCRIPTS_DIR}"

  # Script-Template
  cat > "${filepath}" << SCRIPTEOF
#!/usr/bin/env zsh
# Created: $(date '+%Y-%m-%d %H:%M')
# Source:  paste-to-script / save-script
# ---------------------------------------------------------------------------
# TODO: Beschreibung hier
# ---------------------------------------------------------------------------

set -euo pipefail

# Hier Script-Inhalt einfügen:

SCRIPTEOF

  chmod +x "${filepath}"

  # In Editor öffnen (BBEdit wenn vorhanden, sonst $EDITOR, sonst nano)
  if command -v bbedit &>/dev/null; then
    bbedit "${filepath}"
  elif [[ -n "${EDITOR:-}" ]]; then
    "${EDITOR}" "${filepath}"
  else
    nano "${filepath}"
  fi

  # Git commit
  if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
    cd "${SCRIPTS_DIR}"
    git add "${name}"
    git commit -m "add: ${name}" --quiet
    echo "✓ Gespeichert: ${filepath}"
    echo "✓ Git commit: add: ${name}"
  fi
}

# -----------------------------------------------------------------------------
# scripts: Listet ~/scripts/ auf
# -----------------------------------------------------------------------------
scripts() {
  if [[ ! -d "${SCRIPTS_DIR}" ]]; then
    echo "~/scripts/ existiert nicht. Run: ~/git/dotfiles-macos/scripts-tracker/setup.sh"
    return 1
  fi
  echo "📂 ~/scripts/ ($(ls ${SCRIPTS_DIR}/*.sh 2>/dev/null | wc -l | tr -d ' ') Scripts)"
  ls -lt "${SCRIPTS_DIR}/"*.sh 2>/dev/null | awk '{print $6, $7, $9}' | sed "s|${SCRIPTS_DIR}/||" || echo "  (noch keine Scripts)"
}

# -----------------------------------------------------------------------------
# scripts-log: Git-History der Scripts
# -----------------------------------------------------------------------------
scripts-log() {
  if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
    git -C "${SCRIPTS_DIR}" log --oneline --all
  else
    echo "git nicht initialisiert. Run: setup.sh"
  fi
}

# -----------------------------------------------------------------------------
# PASTE HOOK (experimentell, opt-in via PASTE_TO_SCRIPT_HOOK=1)
# Erkennt mehrzeilige Paste-Blöcke (>3 Zeilen) und fragt nach
# -----------------------------------------------------------------------------
if [[ "${PASTE_TO_SCRIPT_HOOK:-0}" == "1" ]]; then

  # zsh bracket paste mode: wird bei paste gesetzt
  _paste_to_script_zle_hook() {
    local buf="${BUFFER}"
    local lines=$(echo "${buf}" | wc -l | tr -d ' ')

    if [[ ${lines} -gt 3 ]]; then
      # Nicht sofort ausführen sondern nachfragen
      zle -M "💾  ${lines} Zeilen erkannt. ENTER=normal | s=als Script speichern"

      # Warte auf Tastendruck
      local key
      read -k 1 key

      if [[ "${key}" == "s" ]]; then
        # Block in tmpfile
        local tmpfile=$(mktemp /tmp/paste_XXXX.sh)
        echo "${buf}" > "${tmpfile}"

        # BUFFER leeren (nicht ausführen)
        BUFFER=""
        zle reset-prompt

        # Als Script speichern
        local date_prefix=$(date +%Y%m%d)
        local suggestion="${date_prefix}_pasted_block"
        echo ""
        echo -n "→ Script-Name [${suggestion}]: "
        read name
        name="${name:-${suggestion}}"
        [[ "${name}" != *.sh ]] && name="${name}.sh"

        local filepath="${SCRIPTS_DIR}/${name}"
        mkdir -p "${SCRIPTS_DIR}"
        cat > "${filepath}" << SCRIPTEOF
#!/usr/bin/env zsh
# Created: $(date '+%Y-%m-%d %H:%M')
# Source:  paste-to-script hook
# ---------------------------------------------------------------------------
SCRIPTEOF
        cat "${tmpfile}" >> "${filepath}"
        chmod +x "${filepath}"
        rm -f "${tmpfile}"

        if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
          git -C "${SCRIPTS_DIR}" add "${name}" && \
          git -C "${SCRIPTS_DIR}" commit -m "add: ${name}" --quiet
        fi

        echo "✓ Gespeichert: ${filepath}"
        if command -v bbedit &>/dev/null; then bbedit "${filepath}"; fi
      fi
    fi
  }

  # ZLE widget registrieren
  zle -N _paste_to_script_zle_hook
  # Bracket paste end event (ESC [201~)
  bindkey $'\e[201~' _paste_to_script_zle_hook

fi

# Aliases
alias ss='save-script'
