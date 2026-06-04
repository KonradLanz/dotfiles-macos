#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Long-Entry Extractor + Secret Detector
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
#
# Über macOS zsh-Sessions:
#   ~/.zsh_sessions/*.historynew  = RAM-Buffer pro offenem Terminal
#   Vor fc -W  → Datei hat 0 Zeilen (History liegt im RAM)
#   Nach fc -W → Datei hat N Zeilen (RAM wurde in Datei geschrieben)
#   Beim Schließen des Terminals → wird in ~/.zsh_history gemerged
#   ⇒ Zeilen können NIE auf 0 fallen solange das Terminal offen ist
#   ⇒ Session-Check ist rein informativ, kein Blocker
# =============================================================================

set -euo pipefail

# --- Config ---
# HISTFILE Fallback: beim Aufruf via "zsh script.sh" ist $HISTFILE nicht gesetzt
HISTFILE="${HISTFILE:-${HOME}/.zsh_history}"
BACKUP_DIR="${HOME}/.zsh_history_backups"
SCRIPTS_DIR="${HOME}/scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MERGED_DUMP="/tmp/zsh_hist_merged_${TIMESTAMP}.txt"
CLEAN_FILE="/tmp/zsh_hist_clean_${TIMESTAMP}.txt"
LONG_FILE="/tmp/zsh_hist_long_${TIMESTAMP}.txt"
SECRET_FILE="/tmp/zsh_hist_secrets_${TIMESTAMP}.txt"
LONG_THRESH=100
DRY_RUN=0
SKIP_EXTRACT=0

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

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1 — Offene Terminal-Sessions (rein informativ, kein Blocker)
# ─────────────────────────────────────────────────────────────────────────────
# Wichtig: Session-Files sind IMMER nicht-leer solange ein Terminal offen ist
# (vor fc -W = 0 Zeilen im RAM; nach fc -W = N Zeilen in der Datei).
# Wir mergen ALLE Quellen sowieso — dieser Schritt informiert nur über
# die Datenmenge die aus anderen Terminals kommt.
# ─────────────────────────────────────────────────────────────────────────────
echo "📋 SCHRITT 1 — Offene Terminal-Sessions (informativ)"

SESSION_FILES=(~/.zsh_sessions/*.historynew(N))
TOTAL_LINES=0
SESSION_COUNT=${#SESSION_FILES[@]}

if [[ $SESSION_COUNT -eq 0 ]]; then
  echo "   ✓ Keine Session-Dateien gefunden"
else
  echo "   ℹ️  ${SESSION_COUNT} offene Terminal-Session(s):"
  for f in "${SESSION_FILES[@]}"; do
    count=$(wc -l < "$f" | tr -d ' ')
    TOTAL_LINES=$((TOTAL_LINES + count))
    if [[ $count -eq 0 ]]; then
      echo "      → $(basename $f)  (0 Zeilen — History liegt im RAM, wird via fc-ln gemerged)"
    else
      echo "      → $(basename $f)  ($count Zeilen — bereits mit fc -W gesichert)"
    fi
  done
  echo ""
  echo "   💡 Falls du History aus anderen Terminals sichern willst:"
  echo "      In jedem anderen Terminal: fc -W  (einmalig, dann hier Enter)"
  echo ""
  read "?   Enter zum Fortfahren (oder warte bis fc -W überall erledigt): "
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2 — Backup + Merge
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "💾 SCHRITT 2 — Backup & Merge"
mkdir -p "${BACKUP_DIR}"

if [[ -f "${HISTFILE}" ]]; then
  cp "${HISTFILE}" "${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
  echo "   ✓ Backup: ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
else
  echo "   ℹ️  ${HISTFILE} existiert noch nicht — wird neu erstellt"
fi

for f in ~/.zsh_sessions/*.history*(N) ~/.zsh_sessions/*.historynew(N); do
  [[ -f "$f" ]] && cp "$f" "${BACKUP_DIR}/$(basename $f).${TIMESTAMP}.bak"
done

echo "   → Merge aller History-Quellen..."

# Quelle 1: In-Memory History dieses Terminals (fc -ln ohne Zeilennummern)
fc -ln -${HISTSIZE:-100000} > "${MERGED_DUMP}" 2>/dev/null \
  || fc -ln 1 > "${MERGED_DUMP}" 2>/dev/null \
  || true

# Quelle 2: Alle Session-Files (andere Terminals, egal ob 0 oder N Zeilen)
for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  if [[ -f "$f" && -s "$f" ]]; then
    # Format ": timestamp:0;command" → nur Command-Teil
    grep -v '^[[:space:]]*$' "$f" \
      | sed 's/^: [0-9]*:[0-9]*;//' \
      >> "${MERGED_DUMP}" 2>/dev/null || true
  fi
done

# Quelle 3: Gespeicherte ~/.zsh_history (enthält History aus geschlossenen Terminals)
if [[ -f "${HISTFILE}" ]]; then
  # Auch hier Extended-History-Format bereinigen
  grep -v '^[[:space:]]*$' "${HISTFILE}" \
    | sed 's/^: [0-9]*:[0-9]*;//' \
    >> "${MERGED_DUMP}" 2>/dev/null || true
fi

MERGED_COUNT=$(wc -l < "${MERGED_DUMP}" | tr -d ' ')
echo "   ✓ Gesamt gesammelt: ${MERGED_COUNT} Zeilen (inkl. Duplikate)"

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3 — Lange Einträge
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📏 SCHRITT 3 — Lange Einträge analysieren (>${LONG_THRESH} Zeichen)"

LC_ALL=C awk -v thresh="${LONG_THRESH}" '
  /^[[:space:]]*$/                  { next }
  /^[[:space:]]+[0-9]+[[:space:]]+/ { next }
  /^\[200~/                         { next }
  /^: [0-9]+:[0-9]+;/               { next }
  length($0) > thresh               { print }
' "${MERGED_DUMP}" | sort -u > "${LONG_FILE}"

LONG_COUNT=$(wc -l < "${LONG_FILE}" | tr -d ' ')
echo "   Gefunden: ${LONG_COUNT} lange Einträge"

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 4 — Secret-Erkennung
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔐 SCHRITT 4 — Secret-Erkennung"

export MERGED_DUMP
python3 - << 'PYEOF' > "${SECRET_FILE}" 2>/dev/null
import sys, math, re, os

def shannon_entropy(s):
    if not s: return 0
    freq = {}
    for c in s: freq[c] = freq.get(c, 0) + 1
    return -sum((f/len(s)) * math.log2(f/len(s)) for f in freq.values())

SECRET_PATTERNS = [
    r'(?i)(password|passwd|--pass|\-p\s+\S{4,}|\-P\s+\S{4,})\s*[=:\s]\s*\S+',
    r'(?i)(token|secret|apikey|api_key|api-key)\s*[=:]\s*\S{8,}',
    r'(?i)export\s+(\w*(SECRET|TOKEN|KEY|PASS|PWD)\w*)\s*=\s*\S+',
    r'(?i)Authorization:\s*(Bearer|Basic)\s+\S+',
    r'-----BEGIN\s+(RSA|EC|OPENSSH|PGP)',
    r'(?i)curl.*-u\s+\w+:\S+',
    r'(?i)(aws_access_key|aws_secret)',
]

try:
    with open(os.environ.get('MERGED_DUMP', '/tmp/merged.txt')) as f:
        lines = f.readlines()
except:
    sys.exit(0)

for line in lines:
    line = line.rstrip()
    if not line or len(line) < 10: continue
    for pat in SECRET_PATTERNS:
        if re.search(pat, line):
            print(f'[PATTERN] {line[:200]}')
            break
    else:
        for tok in re.findall(r'[A-Za-z0-9+/=_\-]{20,}', line):
            if shannon_entropy(tok) > 4.2:
                print(f'[ENTROPY] {line[:200]}')
                break
PYEOF

SECRET_COUNT=$(wc -l < "${SECRET_FILE}" | tr -d ' ')
if [[ "${SECRET_COUNT}" -gt 0 ]]; then
  echo "   ⚠️  ${SECRET_COUNT} potenzielle Secrets gefunden:"
  echo "   ────────────────────────────────────────────────────"
  head -20 "${SECRET_FILE}"
  echo "   ────────────────────────────────────────────────────"
  echo ""
  read "SCONT?   Diese Einträge aus der History entfernen? [J/n] "
  REMOVE_SECRETS="J"
  [[ "${SCONT}" == "n" || "${SCONT}" == "N" ]] && REMOVE_SECRETS="N"
else
  echo "   ✓ Keine offensichtlichen Secrets gefunden"
  REMOVE_SECRETS="N"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 5 — Interaktive Extraktion langer Einträge als Scripts
# ─────────────────────────────────────────────────────────────────────────────
if [[ "${SKIP_EXTRACT}" == 0 && "${LONG_COUNT}" -gt 0 ]]; then
  echo ""
  echo "📝 SCHRITT 5 — Lange Einträge als Scripts speichern"
  mkdir -p "${SCRIPTS_DIR}"

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
    echo "   [s] Als Script   [i] In History behalten   [d] Löschen   [q] Abbrechen"
    read "ACTION?   Aktion: "

    case "${ACTION}" in
      s|S)
        DATE_PREFIX=$(date +%Y%m%d)
        SUGGESTION=$(echo "${ENTRY}" | awk '{print $1}' | tr -cd 'a-z0-9_-' | cut -c1-20)
        SUGGESTION="${DATE_PREFIX}_${SUGGESTION}_script"
        echo -n "   Name [${SUGGESTION}]: "
        read SNAME
        SNAME="${SNAME:-${SUGGESTION}}"
        [[ "${SNAME}" != *.sh ]] && SNAME="${SNAME}.sh"
        [[ ! "${SNAME}" =~ ^[0-9]{8}_ ]] && SNAME="${DATE_PREFIX}_${SNAME}"
        SPATH="${SCRIPTS_DIR}/${SNAME}"
        printf '#!/usr/bin/env zsh\n# Extracted: %s\n# From: history cleanup\n# ---\n\n%s\n' \
          "$(date '+%Y-%m-%d %H:%M')" "${ENTRY}" > "${SPATH}"
        chmod +x "${SPATH}"
        if [[ -d "${SCRIPTS_DIR}/.git" ]]; then
          git -C "${SCRIPTS_DIR}" add "${SNAME}"
          git -C "${SCRIPTS_DIR}" commit -m "extract: ${SNAME}" --quiet
        fi
        echo "   ✓ Gespeichert: ${SPATH}"
        echo "${ENTRY}" >> "${LONG_FILE}.delete"
        ;;
      d|D)
        echo "   ✓ Wird entfernt"
        echo "${ENTRY}" >> "${LONG_FILE}.delete"
        ;;
      q|Q)
        echo "   → Abgebrochen"
        break
        ;;
      *)
        echo "   → Behalten"
        ;;
    esac
  done < "${LONG_FILE}"
else
  [[ "${SKIP_EXTRACT}" == 1 ]] && echo "   → Übersprungen (--skip-extract)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 6 — Bereinigung
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "🧹 SCHRITT 6 — History bereinigen"

ENTRIES_TO_DELETE="/tmp/zsh_hist_delete_${TIMESTAMP}.txt"
touch "${ENTRIES_TO_DELETE}"
[[ -f "${LONG_FILE}.delete" ]] && cat "${LONG_FILE}.delete" >> "${ENTRIES_TO_DELETE}"

if [[ "${REMOVE_SECRETS}" == "J" ]]; then
  grep '^\[.*\] ' "${SECRET_FILE}" | sed 's/^\[.*\] //' >> "${ENTRIES_TO_DELETE}"
fi

LC_ALL=C awk '
  /^[[:space:]]*$/                  { next }
  /^[[:space:]]+[0-9]+[[:space:]]+/ { next }
  /^\[200~/                         { next }
  /^: [0-9]+:[0-9]+;/ {
    sub(/^: [0-9]+:[0-9]+;/, "")
    if ($0 == "") next
  }
  length($0) > 500 { next }
  !seen[$0]++      { print }
' "${MERGED_DUMP}" > "${CLEAN_FILE}"

if [[ -s "${ENTRIES_TO_DELETE}" ]]; then
  TEMP_FILTERED="/tmp/zsh_hist_filtered_${TIMESTAMP}.txt"
  grep -vxFf "${ENTRIES_TO_DELETE}" "${CLEAN_FILE}" > "${TEMP_FILTERED}" 2>/dev/null \
    || cp "${CLEAN_FILE}" "${TEMP_FILTERED}"
  mv "${TEMP_FILTERED}" "${CLEAN_FILE}"
fi

CLEAN_COUNT=$(wc -l < "${CLEAN_FILE}" | tr -d ' ')
echo "   ✓ Bereinigt: ${CLEAN_COUNT} Einträge (war: ${MERGED_COUNT})"

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 7 — Schreiben + Reload
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "💿 SCHRITT 7 — History schreiben"

if [[ "${DRY_RUN}" == 1 ]]; then
  echo "   [DRY-RUN] Würde ${CLEAN_COUNT} Einträge nach ${HISTFILE} schreiben"
  echo "   [DRY-RUN] Preview (letzte 10):"
  tail -10 "${CLEAN_FILE}" | sed 's/^/     /'
else
  for f in ~/.zsh_sessions/*.historynew(N) ~/.zsh_sessions/*.history(N); do
    [[ -f "$f" ]] && > "$f"
  done
  echo "   ✓ Session-Dateien geleert"
  cp "${CLEAN_FILE}" "${HISTFILE}"
  echo "   ✓ ${HISTFILE} aktualisiert (${CLEAN_COUNT} Einträge)"
  fc -R "${HISTFILE}" 2>/dev/null || true
  echo "   ✓ In-Memory History reloaded"
fi

rm -f "${MERGED_DUMP}" "${CLEAN_FILE}" "${LONG_FILE}" "${LONG_FILE}.delete" \
      "${SECRET_FILE}" "${ENTRIES_TO_DELETE}" 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ Fertig!  Backup: ~/.zsh_history_backups/         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
