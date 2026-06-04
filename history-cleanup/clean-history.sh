#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Long-Entry Extractor + Secret Detector
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
#
# Über macOS zsh-Sessions & das "0-Zeilen-Problem":
#   ~/.zsh_sessions/*.historynew  = RAM-Buffer pro offenem Terminal
#   fc -W noch NICHT ausgeführt   → Datei hat 0 Zeilen, History liegt im RAM
#   fc -W ausgeführt              → Datei hat N Zeilen (RAM → Datei geschrieben)
#   Terminal schließen            → wird automatisch in ~/.zsh_history gemerged
#
#   ⚠️  0 Zeilen = NICHT leer — sondern History liegt noch im RAM!
#   ⇒ Dieses Script liest mit fc -ln direkt aus dem RAM (Quelle 1)
#   ⇒ Session-Check ist informativ; fc -ln rettet RAM-History immer
#
# AppleScript fc -W (Schritt 1.5):
#   Schickt fc -W an alle idle Terminal.app Tabs (busy=false).
#   Tabs mit laufendem Prozess werden übersprungen (kein Chaos in stdin).
#   Funktioniert nur mit Terminal.app — für iTerm2 etc. manuell fc -W eingeben.
#   Benötigt Accessibility-Rechte (Einstellungen > Datenschutz > Bedienungshilfen).
# =============================================================================

# WICHTIG: HISTFILE MUSS vor set -u gesetzt sein, sonst crash bei -u Flag
# Beim Aufruf via "zsh script.sh" ist $HISTFILE in der neuen Shell nicht gesetzt
_HISTFILE_DEFAULT="${HOME}/.zsh_history"
if [[ -n "${HISTFILE+x}" ]]; then
  _HISTFILE="${HISTFILE}"
else
  _HISTFILE="${_HISTFILE_DEFAULT}"
fi

# Jetzt erst set -eo pipefail — HISTFILE ist nun sicher
set -eo pipefail
# Kein -u hier — zu viele zsh-interne Variablen können ungesetzt sein

# --- Config ---
HISTFILE="${_HISTFILE}"
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
# SCHRITT 1 — Offene Terminal-Sessions analysieren
# ─────────────────────────────────────────────────────────────────────────────
# ⚠️  "0 Zeilen" ist NICHT leer — History liegt noch im RAM!
#    fc -ln (Schritt 2) liest direkt aus dem RAM → nichts geht verloren.
#    Andere Terminals: deren RAM-History kann nur via "fc -W" gerettet werden.
# ─────────────────────────────────────────────────────────────────────────────
echo "📋 SCHRITT 1 — Terminal-Sessions (informativ)"

SESSION_FILES=(~/.zsh_sessions/*.historynew(N))
SESSION_COUNT=${#SESSION_FILES[@]}
HAS_RAM_SESSIONS=0

if [[ $SESSION_COUNT -eq 0 ]]; then
  echo "   ✓ Keine Session-Dateien gefunden"
else
  echo "   ℹ️  ${SESSION_COUNT} offene Terminal-Session(s):"
  for f in "${SESSION_FILES[@]}"; do
    count=$(wc -l < "$f" | tr -d ' ')
    if [[ $count -eq 0 ]]; then
      echo "      → $(basename $f)  [⚡ 0 Zeilen auf Disk — History liegt im RAM]"
      HAS_RAM_SESSIONS=1
    else
      echo "      → $(basename $f)  [$count Zeilen auf Disk — bereits mit fc -W geschrieben]"
    fi
  done
  echo ""

  if [[ $HAS_RAM_SESSIONS -eq 1 ]]; then
    echo "   ╔─────────────────────────────────────────────────────╗"
    echo "   ║  ⚡ DIESES Terminal hat RAM-History (0 auf Disk)    ║"
    echo "   ║  → fc -ln liest sie direkt → NICHTS geht verloren  ║"
    echo "   ╚─────────────────────────────────────────────────────╝"
  else
    echo "   ✓ Alle Sessions haben ihren RAM bereits auf Disk geschrieben"
  fi

  echo ""
  read "?   Enter zum Fortfahren: "
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1.5 — fc -W in alle anderen Terminal.app Tabs schicken (optional)
# ─────────────────────────────────────────────────────────────────────────────
# Schickt "fc -W" via AppleScript an alle idle Tabs (busy=false).
# Tabs mit laufendem Prozess werden automatisch übersprungen.
# Benötigt Accessibility-Rechte; bei Fehler: Warnung, kein Abbruch.
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📲 SCHRITT 1.5 — fc -W in andere Terminal.app Tabs schicken"
echo ""
echo "   Soll fc -W via AppleScript an alle anderen idle Terminal.app"
echo "   Fenster/Tabs geschickt werden? (Tabs mit laufendem Prozess"
echo "   werden automatisch übersprungen.)"
echo ""
echo "   Voraussetzung: Terminal.app hat Accessibility-Rechte"
echo "   (Einstellungen > Datenschutz > Bedienungshilfen)"
echo ""
read "APPLESCRIPT_RUN?   fc -W an alle anderen Tabs schicken? [J/n] "

if [[ "${APPLESCRIPT_RUN}" != "n" && "${APPLESCRIPT_RUN}" != "N" ]]; then
  echo ""
  echo "   → Sende fc -W an alle idle Terminal.app Tabs..."

  # AppleScript: iteriert über alle Fenster und alle Tabs darin.
  # busy=true  → Prozess läuft (vim, ssh, etc.) → überspringen
  # busy=false → Shell wartet auf Input (idle) → fc -W schicken
  APPLESCRIPT_RESULT=$(osascript 2>&1 << 'APPLESCRIPT_EOF'
    set sent_count to 0
    set skipped_count to 0
    set error_msg to ""

    try
      tell application "Terminal"
        repeat with w in windows
          repeat with t in tabs of w
            try
              if busy of t is false then
                do script "fc -W" in t
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
APPLESCRIPT_EOF
  )

  if [[ "${APPLESCRIPT_RESULT}" == ERROR:* ]]; then
    echo "   ⚠️  AppleScript Fehler: ${APPLESCRIPT_RESULT#ERROR:}"
    echo "   ⚠️  Accessibility-Rechte prüfen:"
    echo "      Einstellungen > Datenschutz > Bedienungshilfen > Terminal.app ✓"
    echo "   → Weiter ohne automatisches fc -W (manuell in anderen Tabs eingeben)"
  else
    SENT="${APPLESCRIPT_RESULT#OK:}"
    SENT_N="${SENT%%:*}"
    SKIPPED_N="${SENT##*:}"
    echo "   ✓ fc -W gesendet an ${SENT_N} Tab(s)"
    [[ "${SKIPPED_N}" -gt 0 ]] && \
      echo "   ℹ️  ${SKIPPED_N} Tab(s) übersprungen (laufender Prozess)"
    echo ""

    if [[ "${SENT_N}" -gt 0 ]]; then
      echo "   ⏳ Kurz warten damit fc -W abgeschlossen wird..."
      sleep 2
      echo "   ✓ Bereit"
    fi
  fi

  # Im Dry-Run: Meldung dass fc -W trotzdem ausgeführt wurde
  # (fc -W ist schreibend aber akzeptabel im Dry-Run, da es nur
  #  RAM auf Disk schreibt — kein Datenverlust möglich)
  [[ "${DRY_RUN}" == 1 ]] && \
    echo "   ℹ️  [DRY-RUN] fc -W wurde trotzdem ausgeführt (nur RAM→Disk, sicher)"
else
  echo "   → Übersprungen. Ggf. manuell 'fc -W' in anderen Terminals eingeben."
fi

echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2 — Backup + Merge aller History-Quellen
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

for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  [[ -f "$f" ]] && cp "$f" "${BACKUP_DIR}/$(basename $f).${TIMESTAMP}.bak"
done

echo "   → Merge aller History-Quellen..."

# Quelle 1: In-Memory History dieses Terminals (fc -ln ohne Zeilennummern)
# -ln = keine Nummern, sicher auch wenn HISTSIZE nicht gesetzt
fc -ln 1 > "${MERGED_DUMP}" 2>/dev/null || true

# Quelle 2: Alle Session-Files (andere Terminals, jetzt nach fc -W vollständig)
for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  if [[ -f "$f" && -s "$f" ]]; then
    grep -v '^[[:space:]]*$' "$f" \
      | sed 's/^: [0-9]*:[0-9]*;//' \
      >> "${MERGED_DUMP}" 2>/dev/null || true
  fi
done

# Quelle 3: Gespeicherte ~/.zsh_history (History aus geschlossenen Terminals)
if [[ -f "${HISTFILE}" ]]; then
  grep -v '^[[:space:]]*$' "${HISTFILE}" \
    | sed 's/^: [0-9]*:[0-9]*;//' \
    >> "${MERGED_DUMP}" 2>/dev/null || true
fi

MERGED_COUNT=$(wc -l < "${MERGED_DUMP}" | tr -d ' ')
echo "   ✓ Gesamt gesammelt: ${MERGED_COUNT} Zeilen (inkl. Duplikate)"

if [[ "${MERGED_COUNT}" -eq 0 ]]; then
  echo ""
  echo "   ❌ FEHLER: Keine History-Daten gefunden!"
  echo "      Stelle sicher dass du das Script im selben Terminal"
  echo "      ausführst wo die History liegt, oder führe erst fc -W aus."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3 — Lange Einträge
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📏 SCHRITT 3 — Lange Einträge analysieren (>${LONG_THRESH} Zeichen)"

LC_ALL=C awk -v thresh="${LONG_THRESH}" '
  /^[[:space:]]*$/                  { next }
  /^[[:space:]]+[0-9]+[[:space:]]/ { next }
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
  /^[[:space:]]+[0-9]+[[:space:]]/ { next }
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
  echo ""
  echo "   [DRY-RUN] Keine Änderungen vorgenommen."
else
  read "CONFIRM?   Jetzt ${CLEAN_COUNT} Einträge in ${HISTFILE} schreiben? [J/n] "
  if [[ "${CONFIRM}" == "n" || "${CONFIRM}" == "N" ]]; then
    echo "   → Abgebrochen. Backup bleibt unter ${BACKUP_DIR}/"
    exit 0
  fi

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
