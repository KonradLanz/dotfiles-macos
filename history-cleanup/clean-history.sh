#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Long-Entry Extractor + Secret Detector
# =============================================================================
# Was dieses Script macht:
#   1. Backup der aktuellen ~/.zsh_history
#   2. Sammelt History aus ALLEN offenen Terminal-Sessions (macOS-aware)
#   3. Zeigt lange Einträge (>100 Zeichen) zur interaktiven Extraktion als Script
#   4. Erkennt potenzielle Passwörter/Secrets via Entropie-Heuristik
#   5. Filtert/bereinigt: Nummern, Artefakte, zu lange Zeilen, Duplikate
#   6. Schreibt saubere History nach ~/.zsh_history
#   7. Löscht macOS Session-Dateien (verhindert Duplikate nach Neustart)
#   8. Lädt bereinigte History in den Speicher
#
# macOS-Eigenheiten die wir berücksichtigen:
#   - ~/.zsh_sessions/*.historynew: pro Terminal-Fenster eigene Session-Datei
#   - Andere offene Terminals haben ihre History noch NICHT in ~/.zsh_history geschrieben
#   - fc -W in anderen Fenstern wäre nötig um deren History zu sichern
#   - Wir mergen ALLE Session-Dateien vor dem Cleanup
#
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
# =============================================================================

set -euo pipefail

# --- Config ---
BACKUP_DIR="${HOME}/.zsh_history_backups"
SCRIPTS_DIR="${HOME}/scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MERGED_DUMP="/tmp/zsh_hist_merged_${TIMESTAMP}.txt"
CLEAN_FILE="/tmp/zsh_hist_clean_${TIMESTAMP}.txt"
LONG_FILE="/tmp/zsh_hist_long_${TIMESTAMP}.txt"
SECRET_FILE="/tmp/zsh_hist_secrets_${TIMESTAMP}.txt"
LONG_THRESH=100   # Zeichen: ab hier als "lang" betrachtet
DRY_RUN=0
SKIP_EXTRACT=0

# Argumente
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --skip-extract) SKIP_EXTRACT=1 ;;
  esac
done

[[ "$DRY_RUN" == 1 ]] && echo "⚠️  DRY-RUN Modus: keine Änderungen werden gespeichert"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║         ZSH History Cleanup — $(date '+%Y-%m-%d %H:%M')        ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 1: Hinweis auf andere offene Terminals
# ──────────────────────────────────────────────────────────────────────────────
echo "📋 SCHRITT 1 — Offene Terminal-Sessions"
SESSION_FILES=(~/.zsh_sessions/*.historynew(N))
if [[ ${#SESSION_FILES[@]} -gt 0 ]]; then
  echo "   ⚠️  Folgende Sessions haben noch nicht gespeicherte History:"
  for f in "${SESSION_FILES[@]}"; do
    COUNT=$(wc -l < "$f" | tr -d ' ')
    echo "   → $f ($COUNT Zeilen)"
  done
  echo ""
  echo "   💡 Tipp: In allen anderen offenen Terminal-Fenstern eintippen:"
  echo "      fc -W   # schreibt Session-History in die gemeinsame Datei"
  echo ""
  read "CONT?   Weiter ohne die anderen Fenster zu sichern? [j/N] "
  [[ "${CONT}" != "j" && "${CONT}" != "J" ]] && { echo "Abgebrochen."; exit 0; }
else
  echo "   ✓ Keine offenen Session-Dateien gefunden"
fi

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 2: Backup + Merge aller Quellen
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "💾 SCHRITT 2 — Backup & Merge"
mkdir -p "${BACKUP_DIR}"

# Backup der aktuellen History-Datei
if [[ -f "${HISTFILE}" ]]; then
  cp "${HISTFILE}" "${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
  echo "   ✓ Backup: ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
fi

# Backup aller Session-Dateien
for f in ~/.zsh_sessions/*.history*(N) ~/.zsh_sessions/*.historynew(N); do
  [[ -f "$f" ]] && cp "$f" "${BACKUP_DIR}/$(basename $f).${TIMESTAMP}.bak"
done

# Merge: In-Memory (aktuelles Terminal) + alle Session-Dateien + ~/.zsh_history
echo "   → Merge aller History-Quellen..."

# Aktuelle In-Memory History
fc -ln -${HISTSIZE:-100000} > "${MERGED_DUMP}" 2>/dev/null || fc -ln 1 > "${MERGED_DUMP}" || true

# Session-Dateien anhängen (enthalten oft History anderer Fenster)
for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  if [[ -f "$f" ]]; then
    # Session-Dateien haben Format ": timestamp:0;command" — nur den Command-Teil extrahieren
    grep -v '^[[:space:]]*$' "$f" | sed 's/^: [0-9]*:[0-9]*;//' >> "${MERGED_DUMP}" 2>/dev/null || true
  fi
done

# Auch die gespeicherte ~/.zsh_history einbeziehen
if [[ -f "${HISTFILE}" ]]; then
  cat "${HISTFILE}" >> "${MERGED_DUMP}" 2>/dev/null || true
fi

MERGED_COUNT=$(wc -l < "${MERGED_DUMP}" | tr -d ' ')
echo "   ✓ Gesamt gesammelt: ${MERGED_COUNT} Zeilen (inkl. Duplikate)"

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 3: Lange Einträge identifizieren (zur Script-Extraktion)
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "📏 SCHRITT 3 — Lange Einträge analysieren (>${LONG_THRESH} Zeichen)"

LC_ALL=C awk -v thresh="${LONG_THRESH}" '
  /^[[:space:]]*$/ { next }
  /^[[:space:]]+[0-9]+[[:space:]]+/ { next }
  /^\[200~/ { next }
  /^: [0-9]+:[0-9]+;/ { next }
  length($0) > thresh { print }
' "${MERGED_DUMP}" | sort -u > "${LONG_FILE}"

LONG_COUNT=$(wc -l < "${LONG_FILE}" | tr -d ' ')
echo "   Gefunden: ${LONG_COUNT} lange Einträge"

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 4: Entropie-basierte Secret-Erkennung
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔐 SCHRITT 4 — Secret-Erkennung"

# Python für Shannon-Entropie (zuverlässiger als awk für diesen Zweck)
python3 - << 'PYEOF' > "${SECRET_FILE}" 2>/dev/null
import sys, math, re

def shannon_entropy(s):
    if not s: return 0
    freq = {}
    for c in s: freq[c] = freq.get(c, 0) + 1
    return -sum((f/len(s)) * math.log2(f/len(s)) for f in freq.values())

# Patterns die auf Secrets hinweisen (unabhängig von Entropie)
SECRET_PATTERNS = [
    r'(?i)(password|passwd|--pass|\-p\s+\S{4,}|\-P\s+\S{4,})\s*[=:\s]\s*\S+',
    r'(?i)(token|secret|apikey|api_key|api-key)\s*[=:]\s*\S{8,}',
    r'(?i)export\s+(\w*(SECRET|TOKEN|KEY|PASS|PWD)\w*)\s*=\s*\S+',
    r'(?i)Authorization:\s*(Bearer|Basic)\s+\S+',
    r'-----BEGIN\s+(RSA|EC|OPENSSH|PGP)',
    r'(?i)curl.*-u\s+\w+:\S+',
    r'(?i)(aws_access_key|aws_secret)',
]

import os
merged = os.environ.get('MERGED_DUMP', '/tmp/merged.txt')

try:
    with open(merged) as f:
        lines = f.readlines()
except: sys.exit(0)

found = []
for line in lines:
    line = line.rstrip()
    if not line or len(line) < 10: continue
    
    # Pattern-Match
    for pat in SECRET_PATTERNS:
        if re.search(pat, line):
            found.append(('PATTERN', line))
            break
    else:
        # Entropie-Check: Token-ähnliche Strings (>20 Zeichen, hohe Entropie)
        tokens = re.findall(r'[A-Za-z0-9+/=_\-]{20,}', line)
        for tok in tokens:
            e = shannon_entropy(tok)
            # Entropie > 4.2 bei Länge > 20 deutet auf zufälligen String hin
            if e > 4.2 and len(tok) > 20:
                found.append(('ENTROPY', line))
                break

for typ, line in found:
    print(f'[{typ}] {line[:200]}')
PYEOF
export MERGED_DUMP

SECRET_COUNT=$(wc -l < "${SECRET_FILE}" | tr -d ' ')
if [[ "${SECRET_COUNT}" -gt 0 ]]; then
  echo "   ⚠️  ${SECRET_COUNT} potenzielle Secrets gefunden:"
  echo "   ─────────────────────────────────────────────────────"
  cat "${SECRET_FILE}" | head -20
  echo "   ─────────────────────────────────────────────────────"
  echo ""
  read "SCONT?   Diese Einträge aus der History entfernen? [J/n] "
  REMOVE_SECRETS="J"
  [[ "${SCONT}" == "n" || "${SCONT}" == "N" ]] && REMOVE_SECRETS="N"
else
  echo "   ✓ Keine offensichtlichen Secrets gefunden"
  REMOVE_SECRETS="N"
fi

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 5: Interaktive Extraktion langer Einträge als Scripts
# ──────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_EXTRACT}" == 0 && "${LONG_COUNT}" -gt 0 ]]; then
  echo ""
  echo "📝 SCHRITT 5 — Lange Einträge als Scripts speichern"
  mkdir -p "${SCRIPTS_DIR}"

  # Git init falls nötig
  if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
    git -C "${SCRIPTS_DIR}" init -b main --quiet 2>/dev/null || \
    git -C "${SCRIPTS_DIR}" init --quiet
  fi

  INDEX=0
  while IFS= read -r ENTRY; do
    INDEX=$((INDEX + 1))
    PREVIEW=$(echo "${ENTRY}" | cut -c1-80)
    echo ""
    echo "   [$INDEX/${LONG_COUNT}] (${#ENTRY} Zeichen)"
    echo "   ${PREVIEW}..."
    echo ""
    echo "   [s] Als Script speichern  [i] Ignorieren (in History behalten)"
    echo "   [d] Löschen (aus History entfernen)  [q] Abbrechen"
    read "ACTION?   Aktion: "

    case "${ACTION}" in
      s|S)
        DATE_PREFIX=$(date +%Y%m%d)
        # Namensvorschlag aus erstem Wort des Eintrags
        SUGGESTION=$(echo "${ENTRY}" | awk '{print $1}' | tr -cd 'a-z0-9_-' | cut -c1-20)
        SUGGESTION="${DATE_PREFIX}_${SUGGESTION}_script"
        echo -n "   Name [${SUGGESTION}]: "
        read SNAME
        SNAME="${SNAME:-${SUGGESTION}}"
        [[ "${SNAME}" != *.sh ]] && SNAME="${SNAME}.sh"
        [[ ! "${SNAME}" =~ ^[0-9]{8}_ ]] && SNAME="${DATE_PREFIX}_${SNAME}"

        SPATH="${SCRIPTS_DIR}/${SNAME}"
        printf '#!/usr/bin/env zsh\n# Extracted: %s\n# From: history cleanup\n# ---------------------------------------------------------------------------\n\n%s\n' \
          "$(date '+%Y-%m-%d %H:%M')" "${ENTRY}" > "${SPATH}"
        chmod +x "${SPATH}"

        if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
          git -C "${SCRIPTS_DIR}" add "${SNAME}"
          git -C "${SCRIPTS_DIR}" commit -m "extract: ${SNAME}" --quiet
        fi
        echo "   ✓ Gespeichert: ${SPATH}"
        # Markieren zum Löschen aus History
        echo "${ENTRY}" >> "${LONG_FILE}.delete"
        ;;
      d|D)
        echo "   ✓ Wird aus History entfernt"
        echo "${ENTRY}" >> "${LONG_FILE}.delete"
        ;;
      q|Q)
        echo "   → Extraktion abgebrochen"
        break
        ;;
      *)
        echo "   → In History behalten"
        ;;
    esac
  done < "${LONG_FILE}"
else
  [[ "${SKIP_EXTRACT}" == 1 ]] && echo "   → Extraktion übersprungen (--skip-extract)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 6: Bereinigung & Filter
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "🧹 SCHRITT 6 — Bereinigung"

# Zu löschende Einträge sammeln
DELETE_FILE="/tmp/zsh_hist_delete_${TIMESTAMP}.txt"
touch "${DELETE_FILE}"
[[ -f "${LONG_FILE}.delete" ]] && cat "${LONG_FILE}.delete" >> "${DELETE_FILE}" || true
[[ "${REMOVE_SECRETS}" == "J" ]] && cat "${SECRET_FILE}" | sed 's/^\[.*\] //' >> "${DELETE_FILE}" || true

LC_ALL=C awk -v thresh="${LONG_THRESH}" '
  # Entferne fc -l Nummer-Artefakte
  /^[[:space:]]+[0-9]+[[:space:]]+/ { next }

  # Entferne Bracket Paste Mode
  /^\[200~/ { next }

  # Entferne zsh extended history Timestamps
  /^: [0-9]+:[0-9]+;/ { next }

  # Entferne zu lange Zeilen (wurden als Script gespeichert oder gelöscht)
  length($0) > thresh { next }

  # Entferne Cursor-Integration (macOS/Cursor Artefakte)
  /shellIntegration/ { next }
  /^source.*\.cursor\/.*\.zsh/ { next }

  # Entferne leere/whitespace Zeilen
  /^[[:space:]]*$/ { next }

  # Führende Leerzeichen entfernen
  { sub(/^[[:space:]]+/, ""); print }
' "${MERGED_DUMP}" | awk '!seen[$0]++' > "${CLEAN_FILE}"

# Zu löschende Einträge noch mal rausfiltern
if [[ -s "${DELETE_FILE}" ]]; then
  TEMP_CLEAN="/tmp/zsh_hist_clean2_${TIMESTAMP}.txt"
  grep -vxFf "${DELETE_FILE}" "${CLEAN_FILE}" > "${TEMP_CLEAN}" 2>/dev/null || cp "${CLEAN_FILE}" "${TEMP_CLEAN}"
  mv "${TEMP_CLEAN}" "${CLEAN_FILE}"
fi

CLEAN_COUNT=$(wc -l < "${CLEAN_FILE}" | tr -d ' ')
echo "   Einträge nach Bereinigung: ${CLEAN_COUNT} (von ${MERGED_COUNT})"
echo "   Entfernt: $((MERGED_COUNT - CLEAN_COUNT)) Zeilen"

# Sicherheitsprüfung
if [[ "${CLEAN_COUNT}" -lt 10 ]]; then
  echo ""
  echo "⚠️  WARNUNG: Nur ${CLEAN_COUNT} Einträge übrig. Etwas stimmt nicht."
  echo "   Prüfe: head -30 ${MERGED_DUMP}"
  exit 1
fi

# Vorschau
echo ""
echo "   Vorschau (letzte 10 Einträge):"
tail -10 "${CLEAN_FILE}" | sed 's/^/   /'

# ──────────────────────────────────────────────────────────────────────────────
# SCHRITT 7: Schreiben + Aktivieren
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "💿 SCHRITT 7 — Speichern & Aktivieren"

if [[ "${DRY_RUN}" == 1 ]]; then
  echo "   DRY-RUN: Würde ${HISTFILE} mit ${CLEAN_COUNT} Einträgen überschreiben"
  echo "   DRY-RUN: Würde ${#SESSION_FILES[@]} Session-Dateien löschen"
else
  read "FINAL?→ ${HISTFILE} überschreiben und Session-Dateien löschen? [j/N] "
  if [[ "${FINAL}" != "j" && "${FINAL}" != "J" ]]; then
    echo "Abgebrochen. Temp-Dateien bleiben erhalten:"
    echo "  ${MERGED_DUMP}  ${CLEAN_FILE}"
    exit 0
  fi

  # Session-Dateien löschen (verhindert Duplikate nach Neustart!)
  rm -f ~/.zsh_sessions/*.history  2>/dev/null || true
  rm -f ~/.zsh_sessions/*.historynew 2>/dev/null || true
  echo "   ✓ Session-Dateien gelöscht"

  # History-Datei schreiben
  mv "${CLEAN_FILE}" "${HISTFILE}"
  chmod 600 "${HISTFILE}"
  echo "   ✓ ${HISTFILE} geschrieben (${CLEAN_COUNT} Einträge)"

  # In aktuellem Terminal-Speicher neu laden
  # fc -p lädt eine Datei als History (ohne Session-Logik)
  fc -p "${HISTFILE}" 2>/dev/null && echo "   ✓ In-Memory History neu geladen" || \
    echo "   ⚠️  fc -p fehlgeschlagen — bitte neues Terminal öffnen"
fi

# ──────────────────────────────────────────────────────────────────────────────
# AUFRÄUMEN
# ──────────────────────────────────────────────────────────────────────────────
rm -f "${MERGED_DUMP}" "${LONG_FILE}" "${LONG_FILE}.delete" \
       "${SECRET_FILE}" "${DELETE_FILE}" 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Cleanup abgeschlossen                             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo "   History: ${CLEAN_COUNT} Einträge"
echo "   Scripts: ${SCRIPTS_DIR}/"
echo "   Backup:  ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
echo ""
if [[ "${DRY_RUN}" == 0 ]]; then
  echo "   ⚡ Tipp: Andere offene Terminals neu starten für saubere History!"
fi
