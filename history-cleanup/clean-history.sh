#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — Einmalige Bereinigung der zsh History auf macOS
# =============================================================================
# Was dieses Script macht:
#   1. Dump der aktuellen In-Memory History (OHNE Nummern, via fc -ln)
#   2. Entfernt Zeilen mit alten History-Nummern am Anfang (fc -l Artefakte)
#   3. Entfernt Bracket Paste Mode Artefakte ([200~)
#   4. Entfernt zu lange Zeilen (>150 Zeichen, typisch: multiline/paste)
#   5. Entfernt leere Zeilen und Duplikate
#   6. Schreibt in ~/.zsh_history und entfernt Session-Dateien
#   7. Lädt die bereinigte History in den Speicher
#
# WICHTIG: Dieses Script nur einmalig ausführen, danach history-tracker.sh verwenden
# =============================================================================

set -euo pipefail

BACKUP_DIR="${HOME}/.zsh_history_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LIVE_DUMP="/tmp/zsh_history_live_${TIMESTAMP}.txt"
CLEAN_FILE="/tmp/zsh_history_clean_${TIMESTAMP}.txt"

echo "=== ZSH History Cleaner ==="
echo "Timestamp: ${TIMESTAMP}"
echo ""

# Backup erstellen
mkdir -p "${BACKUP_DIR}"
if [[ -f "${HISTFILE}" ]]; then
  cp "${HISTFILE}" "${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
  echo "✓ Backup: ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
fi

# Schritt 1: In-Memory History dumpen (OHNE Zeilennummern)
# -n = no numbers, -HISTSIZE = alle Einträge
echo "→ Dumping in-memory history (fc -ln)..."
fc -ln -${HISTSIZE:-50000} > "${LIVE_DUMP}" 2>/dev/null || fc -ln 1 > "${LIVE_DUMP}"
LINE_COUNT=$(wc -l < "${LIVE_DUMP}" | tr -d ' ')
echo "  Einträge in Memory: ${LINE_COUNT}"

# Schritt 2: Bereinigung via awk
# - Entfernt Zeilen die mit Leerzeichen + Zahl + Leerzeichen beginnen (fc -l Artefakte)
# - Entfernt Bracket Paste Mode ([200~ am Anfang)
# - Entfernt zu lange Zeilen (>150 Zeichen)
# - Entfernt leere Zeilen
# - Entfernt führende Leerzeichen (fc -ln gibt manchmal " command" aus)
# - Dedupliziert (preserviert Reihenfolge, letztes Vorkommen gewinnt)
echo "→ Filtering & deduplicating..."
LC_ALL=C awk '
  # Entferne fc -l Nummer-Artefakte: "  123  command"
  /^[[:space:]]+[0-9]+[[:space:]]+/ { next }

  # Entferne Bracket Paste Mode Artefakte
  /^\[200~/ { next }

  # Entferne zu lange Zeilen (wahrscheinlich versehentlich eingefügte Blöcke)
  length($0) > 150 { next }

  # Entferne leere/nur-whitespace Zeilen
  /^[[:space:]]*$/ { next }

  # Führende Leerzeichen entfernen (fc -ln Artefakt)
  { sub(/^[[:space:]]+/, ""); print }
' "${LIVE_DUMP}" | awk '!seen[$0]++' > "${CLEAN_FILE}"

CLEAN_COUNT=$(wc -l < "${CLEAN_FILE}" | tr -d ' ')
echo "  Einträge nach Bereinigung: ${CLEAN_COUNT} (von ${LINE_COUNT})"
echo "  Entfernt: $((LINE_COUNT - CLEAN_COUNT)) Einträge"

# Sicherheitsprüfung: Nicht fortfahren wenn Ergebnis leer
if [[ "${CLEAN_COUNT}" -lt 10 ]]; then
  echo ""
  echo "⚠️  WARNUNG: Zu wenige Einträge (${CLEAN_COUNT}). Abgebrochen."
  echo "   Prüfe: cat ${LIVE_DUMP} | head -20"
  exit 1
fi

# Vorschau
echo ""
echo "=== Vorschau (letzte 10 Einträge nach Bereinigung) ==="
tail -10 "${CLEAN_FILE}"

# Bestätigung
echo ""
read "CONFIRM?→ ${HISTFILE} überschreiben und Sessions löschen? [j/N] "
if [[ "${CONFIRM}" != "j" && "${CONFIRM}" != "J" ]]; then
  echo "Abgebrochen. Temporäre Dateien: ${LIVE_DUMP}, ${CLEAN_FILE}"
  exit 0
fi

# Schritt 3: Session-Dateien löschen (macOS-spezifisch)
echo "→ Lösche ~/.zsh_sessions/*..."
rm -f ~/.zsh_sessions/*.history* 2>/dev/null || true
echo "  ✓ Session-Dateien gelöscht"

# Schritt 4: History-Datei ersetzen
echo "→ Schreibe bereinigte History nach ${HISTFILE}..."
mv "${CLEAN_FILE}" "${HISTFILE}"
chmod 600 "${HISTFILE}"
echo "  ✓ ${HISTFILE} ersetzt"

# Schritt 5: In-Memory History neu laden
echo "→ Lade bereinigte History in den Speicher..."
fc -p "${HISTFILE}" 2>/dev/null || true
echo "  ✓ History neu geladen"

# Aufräumen
rm -f "${LIVE_DUMP}" 2>/dev/null || true

echo ""
echo "=== Fertig ==="
echo "History bereinigt: ${CLEAN_COUNT} Einträge"
echo "Backup unter: ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
echo ""
echo "Öffne ein neues Terminal-Fenster um die bereinigte History zu testen."
