#!/usr/bin/env zsh
# =============================================================================
# reload-history-all-tabs.sh
# Letztes Backup (oder ~/.zsh_history) via fc -R in ALLE Terminal-Tabs laden.
#
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/reload-history-all-tabs.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/reload-history-all-tabs.sh --backup
#   zsh ~/git/dotfiles-macos/history-cleanup/reload-history-all-tabs.sh /pfad/zur/datei.bak
#
# Ohne Argument:   lädt ~/.zsh_history (aktuellen Stand)
# Mit --backup:    neuestes .bak → nach ~/.zsh_history kopieren → fc -R
# Mit Pfad:        angegebene Datei → nach ~/.zsh_history kopieren → fc -R
# =============================================================================

BACKUP_DIR="${HOME}/.zsh_history_backups"
HISTFILE_TARGET="${HISTFILE:-${HOME}/.zsh_history}"
COPY_TO_HISTFILE=0

# --- Ziel-Datei bestimmen ---
SOURCE_FILE=""

if [[ "$1" == "--backup" ]]; then
  SOURCE_FILE=$(ls -t "${BACKUP_DIR}"/zsh_history.*.bak 2>/dev/null | head -1)
  if [[ -z "${SOURCE_FILE}" ]]; then
    echo "❌ Kein Backup gefunden in ${BACKUP_DIR}/"
    exit 1
  fi
  COPY_TO_HISTFILE=1
elif [[ -n "$1" && -f "$1" ]]; then
  SOURCE_FILE="$1"
  COPY_TO_HISTFILE=1
elif [[ -n "$1" ]]; then
  echo "❌ Datei nicht gefunden: $1"
  exit 1
else
  # Kein Argument — aktuellen HISTFILE nehmen, nichts kopieren
  SOURCE_FILE="${HISTFILE_TARGET}"
  COPY_TO_HISTFILE=0
fi

if [[ ! -s "${SOURCE_FILE}" ]]; then
  echo "❌ Datei leer oder nicht lesbar: ${SOURCE_FILE}"
  exit 1
fi

echo ""
echo "📜 History-Reload an alle Tabs"
echo "   Quelle:  ${SOURCE_FILE}"
echo "   Größe:  $(wc -l < "${SOURCE_FILE}" | tr -d ' ') Zeilen  ($(du -sh "${SOURCE_FILE}" | cut -f1))"
echo ""

# --- Backup nach ~/.zsh_history kopieren (nur bei --backup oder Pfad-Argument) ---
if [[ "${COPY_TO_HISTFILE}" == 1 ]]; then
  echo "   ℹ️  Datei wird nach ${HISTFILE_TARGET} kopiert."
  echo "   (Aktuelles ${HISTFILE_TARGET} wird davor als Safety-Backup gesichert)"
  echo ""
  IFS= read -r "_CONFIRM?   Jetzt kopieren? [J/n] " < /dev/tty
  if [[ "${_CONFIRM}" == "n" || "${_CONFIRM}" == "N" ]]; then
    echo "   → Abgebrochen."
    exit 0
  fi

  # Safety-Backup des aktuellen HISTFILE
  if [[ -s "${HISTFILE_TARGET}" ]]; then
    SAFETY_BAK="${BACKUP_DIR}/zsh_history.safety_$(date +%Y%m%d_%H%M%S).bak"
    mkdir -p "${BACKUP_DIR}"
    cp "${HISTFILE_TARGET}" "${SAFETY_BAK}"
    echo "   ✓ Safety-Backup: ${SAFETY_BAK}"
  fi

  cp "${SOURCE_FILE}" "${HISTFILE_TARGET}"
  echo "   ✓ Kopiert nach: ${HISTFILE_TARGET}"
  echo ""

  # Ab jetzt fc -R auf HISTFILE_TARGET (nicht mehr auf SOURCE_FILE)
  SOURCE_FILE="${HISTFILE_TARGET}"
fi

# --- fc -R im aktuellen Terminal ---
fc -R "${SOURCE_FILE}" 2>/dev/null \
  && echo "   ✓ fc -R (dieses Terminal) — History geladen" \
  || echo "   ⚠️  fc -R fehlgeschlagen — Tipp: manuell 'fc -R ${SOURCE_FILE}'"

# --- fc -R via AppleScript an alle anderen idle Tabs ---
echo ""
echo "   → Sende fc -R an andere Tabs..."

FCR_RESULT=$(osascript 2>&1 << APPLESCRIPT_END
  set sent_count to 0
  set skipped_count to 0
  set error_msg to ""
  try
    tell application "Terminal"
      repeat with w in windows
        repeat with t in tabs of w
          try
            if busy of t is false then
              do script "fc -R ${SOURCE_FILE}" in t
              set sent_count to sent_count + 1
            else
              set skipped_count to skipped_count + 1
            end if
          on error e
            set skipped_count to skipped_count + 1
          end try
        end repeat
      end repeat
    end tell
  on error e
    set error_msg to e
  end try
  if error_msg is not "" then
    return "ERROR:" & error_msg
  else
    return "OK:" & sent_count & ":" & skipped_count
  end if
APPLESCRIPT_END
)

if [[ "${FCR_RESULT}" == ERROR:* ]]; then
  echo "   ⚠️  AppleScript Fehler: ${FCR_RESULT#ERROR:}"
  echo "   → Manuell in anderen Tabs: fc -R ${SOURCE_FILE}"
else
  FCR_SENT="${${FCR_RESULT#OK:}%%:*}"
  FCR_SKIPPED="${FCR_RESULT##*:}"
  echo "   ✓ fc -R gesendet an ${FCR_SENT} Tab(s)"
  [[ "${FCR_SKIPPED}" -gt 0 ]] && \
    echo "   ℹ️  ${FCR_SKIPPED} Tab(s) busy — dort manuell: fc -R ${SOURCE_FILE}"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ Fertig!  History in allen Tabs geladen.           ║"
echo "║  Quelle: $(basename "${SOURCE_FILE}")$(printf '%*s' $((46 - ${#$(basename "${SOURCE_FILE}")})) '')║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
