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
# Mit --backup:    lädt das neueste .bak aus ~/.zsh_history_backups
# Mit Pfad:        lädt die angegebene Datei
# =============================================================================

BACKUP_DIR="${HOME}/.zsh_history_backups"
HISTFILE_DEFAULT="${HISTFILE:-${HOME}/.zsh_history}"

# --- Ziel-Datei bestimmen ---
TARGET_FILE=""

if [[ "$1" == "--backup" ]]; then
  # Neuestes .bak suchen
  TARGET_FILE=$(ls -t "${BACKUP_DIR}"/zsh_history.*.bak 2>/dev/null | head -1)
  if [[ -z "${TARGET_FILE}" ]]; then
    echo "❌ Kein Backup gefunden in ${BACKUP_DIR}/"
    exit 1
  fi
elif [[ -n "$1" && -f "$1" ]]; then
  TARGET_FILE="$1"
elif [[ -n "$1" ]]; then
  echo "❌ Datei nicht gefunden: $1"
  exit 1
else
  TARGET_FILE="${HISTFILE_DEFAULT}"
fi

if [[ ! -s "${TARGET_FILE}" ]]; then
  echo "❌ Datei leer oder nicht lesbar: ${TARGET_FILE}"
  exit 1
fi

echo ""
echo "📜 History-Reload an alle Tabs"
echo "   Datei: ${TARGET_FILE}"
echo "   Größe: $(wc -l < "${TARGET_FILE}" | tr -d ' ') Zeilen  ($(du -sh "${TARGET_FILE}" | cut -f1))"
echo ""

# --- fc -R im aktuellen Terminal ---
fc -R "${TARGET_FILE}" 2>/dev/null \
  && echo "   ✓ fc -R (dieses Terminal) — History geladen" \
  || echo "   ⚠️  fc -R fehlgeschlagen — Tipp: 'source' statt direkt ausführen"

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
              do script "fc -R ${TARGET_FILE}" in t
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
  echo "   → Manuell in anderen Tabs ausführen:"
  echo "     fc -R ${TARGET_FILE}"
else
  FCR_SENT="${${FCR_RESULT#OK:}%%:*}"
  FCR_SKIPPED="${FCR_RESULT##*:}"
  echo "   ✓ fc -R gesendet an ${FCR_SENT} Tab(s)"
  [[ "${FCR_SKIPPED}" -gt 0 ]] && \
    echo "   ℹ️  ${FCR_SKIPPED} Tab(s) busy — dort manuell: fc -R ${TARGET_FILE}"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ History in allen Tabs geladen                     ║"
echo "║  $(basename "${TARGET_FILE}")$(printf '%*s' $((47 - ${#$(basename "${TARGET_FILE}"):-0})) '')║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
