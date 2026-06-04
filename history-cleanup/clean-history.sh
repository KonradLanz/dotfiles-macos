#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Multi-Line Block Extractor + Secret Detector
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
#
# Block-Format in ~/.zsh_history:
#   Mehrzeilige Befehle werden als eine Zeile mit literalen \n gespeichert.
#   Beispiel: "befehl1\nbefehl2\nbefehl3"
#   Block-Erkennung: Zeilen die mind. 2x literales \n enthalten (= >= 3 Zeilen).
#   Diese werden vor der Normalisierung extrahiert (NUL-separiert).
#   Einzelzeilen bleiben immer in der History.
#
# Schritt 5 — Block-Extraktion:
#   [s] Als Script speichern   [i] In History behalten   [d] Löschen
#   [m] Vollständig in less    [q] Abbrechen
#   Default: [s]
#
# AppleScript fc -W (Schritt 1.5):
#   Schickt fc -W an alle idle Terminal.app Tabs.
#   Benötigt Accessibility-Rechte.
#
# Schritt 7 (fc -R):
#   Nicht automatisch ausgeführt — hängt in nicht-interaktiver Subshell.
#   Hinweis: 'fc -R ~/.zsh_history' in jedem Tab, oder neues Tab öffnen.
# =============================================================================

# -----------------------------------------------------------------------------
# SCHRITT 0 — Auto-Pull
# -----------------------------------------------------------------------------
_SCRIPT_DIR="${${(%):-%x}:A:h}"
if [[ -d "${_SCRIPT_DIR}/../.git" ]]; then
  _PULL_OUT=$(git -C "${_SCRIPT_DIR}/.." pull --ff-only 2>&1)
  _PULL_RC=$?
  if [[ ${_PULL_RC} -eq 0 ]]; then
    if [[ "${_PULL_OUT}" == *"Already up to date"* ]]; then
      echo "✓ Script ist aktuell (git pull)"
    else
      echo "🔄 Script aktualisiert (git pull):"
      echo "${_PULL_OUT}" | sed 's/^/   /'
    fi
  else
    echo "⚠️  git pull fehlgeschlagen — lokale Version wird verwendet"
  fi
fi

_HISTFILE_DEFAULT="${HOME}/.zsh_history"
_HISTFILE="${HISTFILE:-${_HISTFILE_DEFAULT}}"

set -eo pipefail

# --- Config ---
HISTFILE="${_HISTFILE}"
BACKUP_DIR="${HOME}/.zsh_history_backups"
SCRIPTS_DIR="${HOME}/scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MERGED_DUMP="/tmp/zsh_hist_merged_${TIMESTAMP}.txt"
NORM_DUMP="/tmp/zsh_hist_norm_${TIMESTAMP}.txt"
BLOCKS_RAW="/tmp/zsh_hist_blocks_${TIMESTAMP}.raw"   # NUL-separierte Blöcke (>= MIN_BLOCK_LINES)
SINGLES_FILE="/tmp/zsh_hist_singles_${TIMESTAMP}.txt" # Einzelzeilen
CLEAN_FILE="/tmp/zsh_hist_clean_${TIMESTAMP}.txt"
SECRET_FILE="/tmp/zsh_hist_secrets_${TIMESTAMP}.txt"
MIN_BLOCK_LINES=3
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
printf "║         ZSH History Cleanup — %-22s║\n" "$(date '+%Y-%m-%d %H:%M')       "
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------------
# Hilfsfunktion: User-Eingabe immer von /dev/tty
# -----------------------------------------------------------------------------
ask() {
  local _var="$1" _prompt="$2" _reply
  IFS= read -r "_reply?${_prompt}" < /dev/tty
  typeset -g "${_var}"="${_reply}"
}

# -----------------------------------------------------------------------------
# SCHRITT 1 — Terminal-Sessions analysieren
# -----------------------------------------------------------------------------
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
      echo "      → $(basename $f)  [$count Zeilen auf Disk]"
    fi
  done
  echo ""
  if [[ $HAS_RAM_SESSIONS -eq 1 ]]; then
    echo "   ╔──────────────────────────────────────────────────╗"
    echo "   ║  ⚡ DIESES Terminal hat RAM-History (0 auf Disk) ║"
    echo "   ║  → fc -ln liest sie direkt → NICHTS geht        ║"
    echo "   ║    verloren                                      ║"
    echo "   ╚──────────────────────────────────────────────────╝"
  else
    echo "   ✓ Alle Sessions haben ihren RAM bereits auf Disk geschrieben"
  fi
  echo ""
  ask _ "   Enter zum Fortfahren: "
fi

# -----------------------------------------------------------------------------
# SCHRITT 1.5 — fc -W via AppleScript
# -----------------------------------------------------------------------------
echo ""
echo "📲 SCHRITT 1.5 — fc -W in andere Terminal.app Tabs schicken"
echo ""
echo "   Soll fc -W via AppleScript an alle anderen idle Terminal.app"
echo "   Fenster/Tabs geschickt werden? (Tabs mit laufendem Prozess"
echo "   werden automatisch übersprungen.)"
echo ""
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │  ⚠️  Alle anderen Tabs müssen leere Eingabezeile haben. │"
echo "   │  Sonst wird fc -W direkt angehängt → Fehler.           │"
echo "   │  Falls nicht sicher: [n] wählen, manuell 'fc -W'.      │"
echo "   └─────────────────────────────────────────────────────────┘"
echo ""
ask APPLESCRIPT_RUN "   fc -W an alle anderen Tabs schicken? [J/n] "

if [[ "${APPLESCRIPT_RUN}" != "n" && "${APPLESCRIPT_RUN}" != "N" ]]; then
  echo "   → Sende fc -W..."
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
    echo "   → Weiter ohne automatisches fc -W"
  else
    SENT_N="${${APPLESCRIPT_RESULT#OK:}%%:*}"
    SKIPPED_N="${APPLESCRIPT_RESULT##*:}"
    echo "   ✓ fc -W gesendet an ${SENT_N} Tab(s)"
    [[ "${SKIPPED_N}" -gt 0 ]] && echo "   ℹ️  ${SKIPPED_N} Tab(s) übersprungen"
    if [[ "${SENT_N}" -gt 0 ]]; then
      echo "   ⏳ Warte 2s..."
      sleep 2
    fi
  fi
else
  echo "   → Übersprungen."
fi
echo ""

# -----------------------------------------------------------------------------
# SCHRITT 2 — Backup + Merge
# -----------------------------------------------------------------------------
echo ""
echo "💾 SCHRITT 2 — Backup & Merge"
mkdir -p "${BACKUP_DIR}"

if [[ -f "${HISTFILE}" ]]; then
  cp "${HISTFILE}" "${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
  echo "   ✓ Backup: ${BACKUP_DIR}/zsh_history.${TIMESTAMP}.bak"
else
  echo "   ℹ️  ${HISTFILE} existiert noch nicht"
fi

for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  [[ -f "$f" ]] && cp "$f" "${BACKUP_DIR}/$(basename $f).${TIMESTAMP}.bak"
done

echo "   → Merge..."
fc -ln 1 > "${MERGED_DUMP}" 2>/dev/null || true
for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  [[ -f "$f" && -s "$f" ]] && cat "$f" >> "${MERGED_DUMP}" 2>/dev/null || true
done
[[ -f "${HISTFILE}" ]] && cat "${HISTFILE}" >> "${MERGED_DUMP}" 2>/dev/null || true

MERGED_COUNT=$(wc -l < "${MERGED_DUMP}" | tr -d ' ')
echo "   ✓ Gesamt: ${MERGED_COUNT} Rohzeilen"
[[ "${MERGED_COUNT}" -eq 0 ]] && echo "   ❌ Keine Daten!" && exit 1

# -----------------------------------------------------------------------------
# SCHRITT 2a — UTF-8 Sanitize
# -----------------------------------------------------------------------------
iconv -f UTF-8 -t UTF-8 -c "${MERGED_DUMP}" > "${MERGED_DUMP}.utf8" 2>/dev/null && \
  mv "${MERGED_DUMP}.utf8" "${MERGED_DUMP}" || true
echo "   ✓ UTF-8 bereinigt"

# -----------------------------------------------------------------------------
# SCHRITT 2b — Block-Erkennung VOR Normalisierung
# Blöcke = Zeilen mit mind. 2x literalem \n (>= 3 Teilzeilen)
# Diese werden NUL-separiert in BLOCKS_RAW gespeichert.
# Alle anderen Zeilen → SINGLES_FILE (nach vollständiger Normalisierung).
# -----------------------------------------------------------------------------
echo "   → Blöcke erkennen (>= ${MIN_BLOCK_LINES} Zeilen)..."

# Blöcke rausziehen: Zeilennummer-Prefix + extended-history-Prefix entfernen, dann NUL-separiert speichern
LC_ALL=C grep '\\n.*\\n' "${MERGED_DUMP}" \
  | LC_ALL=C sed \
      -e 's/^[[:space:]]*[0-9]*[[:space:]]*//' \
      -e 's/^: [0-9]*:[0-9]*;//' \
      -e 's/\\n$//' \
  | LC_ALL=C tr '\n' '\0' \
  > "${BLOCKS_RAW}" 2>/dev/null || true

BLOCK_COUNT=$(python3 -c "
import sys
data = open('${BLOCKS_RAW}', 'rb').read()
blocks = [b for b in data.split(b'\x00') if b.strip()]
print(len(blocks))
" 2>/dev/null || echo 0)

echo "   ✓ Blöcke (>= ${MIN_BLOCK_LINES} Zeilen): ${BLOCK_COUNT}"

# -----------------------------------------------------------------------------
# SCHRITT 2c — Normalisierung der Einzelzeilen
# -----------------------------------------------------------------------------
echo "   → Normalisierung Einzelzeilen..."

LC_ALL=C grep -v '\\n.*\\n' "${MERGED_DUMP}" \
  | LC_ALL=C sed 's/\\n$//' \
  | LC_ALL=C sed 's/\\n/\n/g' \
  | LC_ALL=C awk '
    /^[[:space:]]*$/ { next }
    /^[[:space:]]+[0-9]+[[:space:]]/ {
      sub(/^[[:space:]]+[0-9]+[[:space:]]+/, "")
      if ($0 == "") next
    }
    /^: [0-9]+:[0-9]+;/ {
      sub(/^: [0-9]+:[0-9]+;/, "")
      if ($0 == "") next
    }
    /^\[200~/ { next }
    { print }
  ' \
  | python3 -c "
import sys, unicodedata
for line in sys.stdin:
    s = line.rstrip('\n')
    stripped = s.strip()
    if not stripped: continue
    cats = [unicodedata.category(c) for c in stripped]
    if all(cat in ('Mn','Cc','Cf','Zs','Zl','Zp') for cat in cats): continue
    if all(ord(c) < 0x20 or ord(c) == 0x7f for c in stripped): continue
    print(s)
" 2>/dev/null > "${SINGLES_FILE}" || true

SINGLES_COUNT=$(wc -l < "${SINGLES_FILE}" | tr -d ' ')
echo "   ✓ Einzelzeilen nach Normalisierung: ${SINGLES_COUNT}"

# -----------------------------------------------------------------------------
# SCHRITT 3 — Secret-Erkennung (auf Einzelzeilen)
# -----------------------------------------------------------------------------
echo ""
echo "🔐 SCHRITT 3 — Secret-Erkennung"

export SINGLES_FILE
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
    lines = open(os.environ['SINGLES_FILE']).readlines()
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
  echo "   ⚠️  ${SECRET_COUNT} potenzielle Secrets:"
  echo "   ----------------------------------------------------"
  head -20 "${SECRET_FILE}"
  echo "   ----------------------------------------------------"
  ask SCONT "   Aus History entfernen? [J/n] "
  REMOVE_SECRETS="J"
  [[ "${SCONT}" == "n" || "${SCONT}" == "N" ]] && REMOVE_SECRETS="N"
else
  echo "   ✓ Keine Secrets gefunden"
  REMOVE_SECRETS="N"
fi

# -----------------------------------------------------------------------------
# SCHRITT 4 — Script-Name ableiten (Hilfsfunktion)
# -----------------------------------------------------------------------------
_derive_script_name() {
  local block="$1" date_prefix=$(date +%Y%m%d) name=""
  name=$(echo "${block}" | LC_ALL=C sed 's/\\n/\n/g' | grep '^#' | head -1 \
    | sed 's/^#[[:space:]]*//' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-30)
  if [[ -z "${name}" ]]; then
    name=$(echo "${block}" | LC_ALL=C sed 's/\\n/\n/g' | grep -v '^#' | head -1 \
      | awk '{print $1}' | tr -cd 'a-z0-9_-' | cut -c1-20)
  fi
  [[ -z "${name}" ]] && name="script"
  echo "${date_prefix}_${name}"
}

mkdir -p "${SCRIPTS_DIR}"
if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
  git -C "${SCRIPTS_DIR}" init -b main --quiet 2>/dev/null || git -C "${SCRIPTS_DIR}" init --quiet
fi

# -----------------------------------------------------------------------------
# SCHRITT 5 — Interaktive Block-Extraktion
# Blöcke aus BLOCKS_RAW (NUL-separiert, je >= MIN_BLOCK_LINES Zeilen).
# Literales \n wird für Anzeige und Script-Ausgabe in echte Newlines gewandelt.
# -----------------------------------------------------------------------------
if [[ "${SKIP_EXTRACT}" == 0 && "${BLOCK_COUNT}" -gt 0 ]]; then
  echo ""
  echo "📦 SCHRITT 5 — Mehrzeilige Blöcke extrahieren"
  echo "   Blöcke mit >= ${MIN_BLOCK_LINES} Zeilen: ${BLOCK_COUNT}"
  echo ""

  BLOCK_IDX=0
  EXTRACTED_COUNT=0
  DELETED_COUNT=0
  KEPT_BLOCKS_FILE="/tmp/zsh_hist_kept_${TIMESTAMP}.txt"

  exec 3< "${BLOCKS_RAW}"
  while IFS= read -r -d $'\0' BLOCK_RAW <&3; do
    [[ -z "${BLOCK_RAW// }" ]] && continue

    # Für Anzeige und Script: literales \n → echter Newline
    BLOCK_DISPLAY=$(echo "${BLOCK_RAW}" | LC_ALL=C sed 's/\\n/\n/g')
    BLOCK_LINES=$(echo "${BLOCK_DISPLAY}" | wc -l | tr -d ' ')
    [[ "${BLOCK_LINES}" -lt "${MIN_BLOCK_LINES}" ]] && continue

    BLOCK_IDX=$((BLOCK_IDX + 1))
    SUGGESTED=$(_derive_script_name "${BLOCK_RAW}")

    echo "   +----------------------------------------------------------+"
    printf "   |  [%d/%d]  %d Zeilen\n" "${BLOCK_IDX}" "${BLOCK_COUNT}" "${BLOCK_LINES}"
    echo "   +----------------------------------------------------------+"
    echo "${BLOCK_DISPLAY}" | head -3 | while IFS= read -r ln; do
      printf "   %.90s\n" "${ln}"
    done
    [[ "${BLOCK_LINES}" -gt 3 ]] && echo "   ... (${BLOCK_LINES} Zeilen gesamt)"
    echo ""
    echo "   [s] Als Script   [i] In History behalten   [d] Löschen"
    echo "   [m] In less anzeigen                        [q] Abbrechen"
    ask ACTION "   Aktion [s]: "
    ACTION="${ACTION:-s}"

    if [[ "${ACTION}" == "m" || "${ACTION}" == "M" ]]; then
      echo "${BLOCK_DISPLAY}" | less </dev/tty >/dev/tty 2>/dev/null || \
        echo "${BLOCK_DISPLAY}" | more </dev/tty >/dev/tty 2>/dev/null || true
      echo ""
      echo "   [s] Als Script   [i] In History behalten   [d] Löschen   [q] Abbrechen"
      ask ACTION "   Aktion [s]: "
      ACTION="${ACTION:-s}"
    fi

    case "${ACTION}" in
      s|S)
        ask SNAME "   Name [${SUGGESTED}]: "
        SNAME="${SNAME:-${SUGGESTED}}"
        [[ "${SNAME}" != *.sh ]] && SNAME="${SNAME}.sh"
        [[ ! "${SNAME}" =~ ^[0-9]{8}_ ]] && SNAME="$(date +%Y%m%d)_${SNAME}"
        SPATH="${SCRIPTS_DIR}/${SNAME}"
        if [[ "${DRY_RUN}" == 1 ]]; then
          echo "   [DRY-RUN] Würde speichern: ${SPATH}"
        else
          printf '#!/usr/bin/env zsh\n# Extracted: %s\n# From: zsh history cleanup\n# ---\n\n%s\n' \
            "$(date '+%Y-%m-%d %H:%M')" "${BLOCK_DISPLAY}" > "${SPATH}"
          chmod +x "${SPATH}"
          git -C "${SCRIPTS_DIR}" add "${SNAME}" 2>/dev/null || true
          git -C "${SCRIPTS_DIR}" commit -m "extract: ${SNAME}" --quiet 2>/dev/null || true
          echo "   ✓ Gespeichert: ${SPATH}"
          EXTRACTED_COUNT=$((EXTRACTED_COUNT + 1))
        fi
        ;;
      d|D)
        echo "   → Gelöscht"
        DELETED_COUNT=$((DELETED_COUNT + 1))
        ;;
      q|Q)
        echo "   → Abgebrochen"
        break
        ;;
      *)
        # [i] oder Enter ohne Eingabe: in History behalten
        # Block als Einzelzeilen zurück in SINGLES_FILE schreiben
        echo "${BLOCK_DISPLAY}" >> "${SINGLES_FILE}"
        echo "   → Behalten"
        ;;
    esac
    echo ""
  done
  exec 3<&-

  echo "   ✓ Extrahiert: ${EXTRACTED_COUNT}  |  Gelöscht: ${DELETED_COUNT}"
else
  [[ "${SKIP_EXTRACT}" == 1 ]] && echo "" && echo "   → Schritt 5 übersprungen (--skip-extract)"
  [[ "${BLOCK_COUNT}" -eq 0 ]] && echo "" && echo "   ℹ️  Keine Blöcke >= ${MIN_BLOCK_LINES} Zeilen"
fi

# -----------------------------------------------------------------------------
# SCHRITT 6 — Dedup + Secret-Entfernung
# -----------------------------------------------------------------------------
echo ""
echo "🧹 SCHRITT 6 — History bereinigen"

ENTRIES_TO_DELETE="/tmp/zsh_hist_delete_${TIMESTAMP}.txt"
touch "${ENTRIES_TO_DELETE}"

[[ "${REMOVE_SECRETS}" == "J" ]] && \
  LC_ALL=C grep '^\[.*\] ' "${SECRET_FILE}" | LC_ALL=C sed 's/^\[.*\] //' >> "${ENTRIES_TO_DELETE}"

LC_ALL=C awk '/^[[:space:]]*$/{next} !seen[$0]++{print}' "${SINGLES_FILE}" > "${CLEAN_FILE}"

if [[ -s "${ENTRIES_TO_DELETE}" ]]; then
  TEMP_FILTERED="/tmp/zsh_hist_filtered_${TIMESTAMP}.txt"
  LC_ALL=C grep -vxFf "${ENTRIES_TO_DELETE}" "${CLEAN_FILE}" > "${TEMP_FILTERED}" 2>/dev/null \
    || cp "${CLEAN_FILE}" "${TEMP_FILTERED}"
  mv "${TEMP_FILTERED}" "${CLEAN_FILE}"
fi

CLEAN_COUNT=$(wc -l < "${CLEAN_FILE}" | tr -d ' ')
echo "   ✓ Bereinigt: ${CLEAN_COUNT} Einträge (war: ${MERGED_COUNT} Rohzeilen)"

# -----------------------------------------------------------------------------
# SCHRITT 7 — Schreiben
# -----------------------------------------------------------------------------
echo ""
echo "💿 SCHRITT 7 — History schreiben"

if [[ "${DRY_RUN}" == 1 ]]; then
  echo "   [DRY-RUN] Würde ${CLEAN_COUNT} Einträge nach ${HISTFILE} schreiben"
  echo "   [DRY-RUN] Preview (letzte 10):"
  tail -10 "${CLEAN_FILE}" | sed 's/^/     /'
  echo "   [DRY-RUN] Keine Änderungen."
else
  ask CONFIRM "   Jetzt ${CLEAN_COUNT} Einträge in ${HISTFILE} schreiben? [J/n] "
  if [[ "${CONFIRM}" == "n" || "${CONFIRM}" == "N" ]]; then
    echo "   → Abgebrochen. Backup: ${BACKUP_DIR}/"
    exit 0
  fi

  # Session-Files leeren — truncate statt > (verhindert Hänger bei gelockten Files)
  for f in ~/.zsh_sessions/*.historynew(N) ~/.zsh_sessions/*.history(N); do
    [[ -f "$f" ]] && truncate -s 0 "$f" 2>/dev/null || true
  done
  echo "   ✓ Session-Dateien geleert"

  cp "${CLEAN_FILE}" "${HISTFILE}"
  echo "   ✓ ${HISTFILE} aktualisiert (${CLEAN_COUNT} Einträge)"
fi

rm -f "${MERGED_DUMP}" "${NORM_DUMP}" "${BLOCKS_RAW}" "${SINGLES_FILE}" \
      "${CLEAN_FILE}" "${SECRET_FILE}" "${ENTRIES_TO_DELETE}" \
      "/tmp/zsh_hist_kept_${TIMESTAMP}.txt" 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ Fertig!  Backup: ~/.zsh_history_backups/         ║"
if [[ "${DRY_RUN}" != 1 ]]; then
  echo "║                                                      ║"
  echo "║  ℹ️  History noch nicht aktuell in diesem Tab.       ║"
  echo "║  → fc -R ~/.zsh_history  oder neues Tab öffnen      ║"
fi
echo "╚══════════════════════════════════════════════════════╝"
echo ""
