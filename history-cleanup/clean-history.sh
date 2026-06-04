#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Multi-Line Block Extractor + Secret Detector
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
#
# Schritt 5 Aktionen:
#   [s] Als Script speichern
#   [i] In History behalten
#   [d] Löschen
#   [m] Nächste 10 Zeilen inline (wiederholbar)
#   [M] Vollständig in less (q zum Beenden, danach Aktion wählen)
#   [q] Abbrechen (restliche Blöcke alle in History behalten)
# =============================================================================

# -----------------------------------------------------------------------------
# SCHRITT 0 — Auto-Pull (immer verbose)
# -----------------------------------------------------------------------------
_SCRIPT_DIR="${${(%):-%x}:A:h}"
if [[ -d "${_SCRIPT_DIR}/../.git" ]]; then
  echo "🔄 Schritt 0 — Auto-Pull..."
  _PULL_OUT=$(git -C "${_SCRIPT_DIR}/.." pull --ff-only 2>&1)
  _PULL_RC=$?
  if [[ ${_PULL_RC} -eq 0 ]]; then
    echo "   ${_PULL_OUT}"
  else
    echo "   ⚠️  git pull fehlgeschlagen:"
    echo "   ${_PULL_OUT}"
    echo "   → Lokale Version wird verwendet"
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
BLOCKS_RAW="/tmp/zsh_hist_blocks_${TIMESTAMP}.raw"
SINGLES_FILE="/tmp/zsh_hist_singles_${TIMESTAMP}.txt"
CLEAN_FILE="/tmp/zsh_hist_clean_${TIMESTAMP}.txt"
SECRET_FILE="/tmp/zsh_hist_secrets_${TIMESTAMP}.txt"
PENDING_BLOCKS_FILE="/tmp/zsh_hist_pending_${TIMESTAMP}.txt"
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
# SCHRITT 1.5 — fc -W (eigenes Terminal sofort, andere via AppleScript)
# -----------------------------------------------------------------------------
echo ""
echo "💾 SCHRITT 1.5 — History auf Disk schreiben (fc -W)"
echo ""
echo "   fc -W schreibt die RAM-History dieses Terminals zuerst selbst,"
echo "   dann optional via AppleScript an alle anderen idle Tabs."
echo ""

fc -W 2>/dev/null && echo "   ✓ fc -W (dieses Terminal) ausgeführt" \
                  || echo "   ⚠️  fc -W (dieses Terminal) fehlgeschlagen — weiter"

echo ""
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │  ⚠️  Andere Tabs brauchen leere Eingabezeile.         │"
echo "   │  Falls nicht sicher: [n] wählen, manuell 'fc -W'.  │"
echo "   └─────────────────────────────────────────────────────────┘"
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
  else
    SENT_N="${${APPLESCRIPT_RESULT#OK:}%%:*}"
    SKIPPED_N="${APPLESCRIPT_RESULT##*:}"
    echo "   ✓ fc -W gesendet an ${SENT_N} Tab(s)"
    [[ "${SKIPPED_N}" -gt 0 ]] && echo "   ℹ️  ${SKIPPED_N} Tab(s) übersprungen (busy)"
    if [[ "${SENT_N}" -gt 0 ]]; then
      echo "   ⏳ Warte 2s..."
      sleep 2
    fi
  fi
else
  echo "   → Andere Tabs übersprungen."
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

iconv -f UTF-8 -t UTF-8 -c "${MERGED_DUMP}" > "${MERGED_DUMP}.utf8" 2>/dev/null && \
  mv "${MERGED_DUMP}.utf8" "${MERGED_DUMP}" || true
echo "   ✓ UTF-8 bereinigt"

# -----------------------------------------------------------------------------
# SCHRITT 2b — Block-Erkennung + Dedup
# BLOCKS_RAW.raw0 = alle Rohblöcke (NUL-separiert)
# BLOCKS_RAW      = nach Dedup (gleicher normalisierter Inhalt = Duplikat)
# -----------------------------------------------------------------------------
echo "   → Blöcke erkennen (>= ${MIN_BLOCK_LINES} Zeilen)..."

LC_ALL=C grep '\\n.*\\n' "${MERGED_DUMP}" \
  | LC_ALL=C sed \
      -e 's/^[[:space:]]*[0-9]*[[:space:]]*//' \
      -e 's/^: [0-9]*:[0-9]*;//' \
      -e 's/\\n$//' \
  | LC_ALL=C tr '\n' '\0' \
  > "${BLOCKS_RAW}.raw0" 2>/dev/null || true

# Python-Dedup: Heredoc GEQUOTET ('PYEOF') damit zsh keine Expansion macht.
# Dateipfade via Umgebungsvariablen übergeben.
export _BLOCKS_RAW_IN="${BLOCKS_RAW}.raw0"
export _BLOCKS_RAW_OUT="${BLOCKS_RAW}"
BLOCK_COUNT=$(python3 << 'PYEOF_DEDUP'
import re, os, sys

try:
    data = open(os.environ['_BLOCKS_RAW_IN'], 'rb').read()
except Exception as e:
    print(0, file=sys.stderr)
    print(0)
    raise SystemExit

raw_blocks = [b for b in data.split(b'\x00') if b.strip()]

seen = set()
uniq = []
for b in raw_blocks:
    # Normalisierungsschlüssel: \n-Escape expandieren, Leerzeilen + Whitespace strippen
    key = re.sub(rb'\\n', b'\n', b)
    key = b'\n'.join(ln.strip() for ln in key.splitlines() if ln.strip())
    if key in seen:
        continue
    seen.add(key)
    uniq.append(b)

with open(os.environ['_BLOCKS_RAW_OUT'], 'wb') as f:
    for b in uniq:
        f.write(b + b'\x00')

print(len(uniq))
PYEOF_DEDUP
)

unset _BLOCKS_RAW_IN _BLOCKS_RAW_OUT
rm -f "${BLOCKS_RAW}.raw0"
echo "   ✓ Blöcke nach Dedup: ${BLOCK_COUNT}"

# -----------------------------------------------------------------------------
# SCHRITT 2c — Normalisierung Einzelzeilen
# -----------------------------------------------------------------------------
echo "   → Normalisierung Einzelzeilen..."

LC_ALL=C grep -v '\\n.*\\n' "${MERGED_DUMP}" \
  | LC_ALL=C sed -e 's/\\n$//' -e 's/\\n/\n/g' \
  | LC_ALL=C awk '
    /^[[:space:]]*$/  { next }
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
echo "   ✓ Einzelzeilen: ${SINGLES_COUNT}"

# -----------------------------------------------------------------------------
# SCHRITT 3 — Secret-Erkennung
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
    r'(?i)(password|passwd|--password)\s*[=:\s]\s*\S+',
    r'(?i)(token|secret|apikey|api_key|api-key)\s*[=:]\s*\S{8,}',
    r'(?i)export\s+(\w*(SECRET|TOKEN|KEY|PASS|PWD)\w*)\s*=\s*\S+',
    r'(?i)Authorization:\s*(Bearer|Basic)\s+\S+',
    r'-----BEGIN\s+(RSA|EC|OPENSSH|PGP)',
    r'(?i)curl.*-u\s+\w+:\S+',
    r'(?i)(aws_access_key|aws_secret)',
]
FALSE_POSITIVE_PATTERNS = [
    r'^ssh\s+',
    r'^scp\s+',
    r'^\.zsh_sessions/',
    r'historynew$',
]
TOKEN_WHITELIST = [
    r'^[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}$',
    r'[0-9]{8}',
    r'^[A-Za-z]+[0-9]{4,}',
]

try:
    lines = open(os.environ['SINGLES_FILE']).readlines()
except:
    sys.exit(0)

for line in lines:
    line = line.rstrip()
    if not line or len(line) < 10: continue
    if any(re.search(p, line) for p in FALSE_POSITIVE_PATTERNS): continue
    matched = False
    for pat in SECRET_PATTERNS:
        if re.search(pat, line):
            print(f'[PATTERN] {line[:200]}')
            matched = True
            break
    if not matched:
        for tok in re.findall(r'[A-Za-z0-9+/=_\-]{20,}', line):
            if any(re.search(wp, tok) for wp in TOKEN_WHITELIST): continue
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
# SCHRITT 4 — Script-Name ableiten
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
# Nicht entschiedene Blöcke → PENDING_BLOCKS_FILE → kommen in History.
# [M] less: tmp-Datei über /dev/tty als Vordergrundprozess.
# -----------------------------------------------------------------------------
touch "${PENDING_BLOCKS_FILE}"

if [[ "${SKIP_EXTRACT}" == 0 && "${BLOCK_COUNT}" -gt 0 ]]; then
  echo ""
  echo "📦 SCHRITT 5 — Mehrzeilige Blöcke extrahieren"
  [[ "${DRY_RUN}" == 1 ]] && echo "   ⚠️  DRY-RUN: Aktionen simuliert, nichts geschrieben"
  echo "   Blöcke (nach Dedup): ${BLOCK_COUNT}  —  nicht entschiedene kommen in History"
  echo ""

  BLOCK_IDX=0
  EXTRACTED_COUNT=0
  DELETED_COUNT=0
  KEPT_COUNT=0
  ABORT=0

  _show_block_lines() {
    local display="$1" total_lines=$2 idx=$3 total_blocks=$4 from_line=$5
    local show_to=$(( from_line + 10 ))
    [[ ${show_to} -gt ${total_lines} ]] && show_to=${total_lines}
    echo "   +----------------------------------------------------------+"
    printf "   |  Block [%d/%d] — %d Zeilen  (Zeilen %d–%d)\n" \
      ${idx} ${total_blocks} ${total_lines} $(( from_line + 1 )) ${show_to}
    echo "   +----------------------------------------------------------+"
    printf '%s\n' "${display}" \
      | tail -n +$(( from_line + 1 )) \
      | head -n 10 \
      | while IFS= read -r ln; do printf "   | %.88s\n" "${ln}"; done
    [[ ${show_to} -lt ${total_lines} ]] && \
      echo "   | ... (noch $(( total_lines - show_to )) Zeilen)"
    echo "   +----------------------------------------------------------+"
  }

  set +e
  exec 3< "${BLOCKS_RAW}"
  while IFS= read -r -d $'\0' BLOCK_RAW <&3; do
    [[ -z "${BLOCK_RAW// }" ]] && continue

    BLOCK_DISPLAY=$(printf '%s' "${BLOCK_RAW}" | LC_ALL=C sed 's/\\n/\n/g')
    BLOCK_LINES=$(printf '%s' "${BLOCK_DISPLAY}" | wc -l | tr -d ' ')
    [[ "${BLOCK_LINES}" -lt "${MIN_BLOCK_LINES}" ]] && \
      printf '%s\n' "${BLOCK_DISPLAY}" >> "${PENDING_BLOCKS_FILE}" && continue

    BLOCK_IDX=$(( BLOCK_IDX + 1 ))
    SUGGESTED=$(_derive_script_name "${BLOCK_RAW}")
    PREVIEW_FROM=0

    _show_block_lines "${BLOCK_DISPLAY}" ${BLOCK_LINES} \
      ${BLOCK_IDX} ${BLOCK_COUNT} ${PREVIEW_FROM}
    PREVIEW_FROM=10
    echo ""

    while true; do
      echo "   [s] Script  [i] Behalten  [d] Löschen  [m] +10 Zeilen  [M] less  [q] Stop"
      ask ACTION "   Aktion [s]: "
      ACTION="${ACTION:-s}"

      case "${ACTION}" in

        m)
          if [[ ${PREVIEW_FROM} -ge ${BLOCK_LINES} ]]; then
            echo "   (alle ${BLOCK_LINES} Zeilen gezeigt)"
          else
            _show_block_lines "${BLOCK_DISPLAY}" ${BLOCK_LINES} \
              ${BLOCK_IDX} ${BLOCK_COUNT} ${PREVIEW_FROM}
            PREVIEW_FROM=$(( PREVIEW_FROM + 10 ))
          fi
          echo ""
          continue
          ;;

        M)
          _LESS_TMP="/tmp/zsh_hist_less_${TIMESTAMP}_${BLOCK_IDX}.txt"
          printf '%s\n' "${BLOCK_DISPLAY}" > "${_LESS_TMP}"
          LESSSECURE=1 less "${_LESS_TMP}" </dev/tty >/dev/tty
          rm -f "${_LESS_TMP}"
          echo ""
          continue
          ;;

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
          fi
          EXTRACTED_COUNT=$(( EXTRACTED_COUNT + 1 ))
          echo ""
          break
          ;;

        d|D)
          echo "   → Gelöscht"
          DELETED_COUNT=$(( DELETED_COUNT + 1 ))
          echo ""
          break
          ;;

        q|Q)
          printf '%s\n' "${BLOCK_DISPLAY}" >> "${PENDING_BLOCKS_FILE}"
          ABORT=1
          echo "   → Stop — restliche Blöcke kommen unverändert in die History"
          echo ""
          break 2
          ;;

        *)
          if [[ "${DRY_RUN}" != 1 ]]; then
            printf '%s\n' "${BLOCK_DISPLAY}" >> "${SINGLES_FILE}"
          fi
          echo "   → In History behalten"
          KEPT_COUNT=$(( KEPT_COUNT + 1 ))
          echo ""
          break
          ;;

      esac
    done

  done

  if [[ ${ABORT} -eq 1 ]]; then
    while IFS= read -r -d $'\0' BLOCK_RAW <&3; do
      [[ -z "${BLOCK_RAW// }" ]] && continue
      BLOCK_DISPLAY=$(printf '%s' "${BLOCK_RAW}" | LC_ALL=C sed 's/\\n/\n/g')
      printf '%s\n' "${BLOCK_DISPLAY}" >> "${PENDING_BLOCKS_FILE}"
    done
  fi

  exec 3<&-
  set -e

  PENDING_COUNT=$(wc -l < "${PENDING_BLOCKS_FILE}" | tr -d ' ')
  echo "   ✓ Script: ${EXTRACTED_COUNT}  Löschen: ${DELETED_COUNT}  Behalten: ${KEPT_COUNT}  Pending: ${PENDING_COUNT} Zeilen"

else
  set +e
  exec 3< "${BLOCKS_RAW}"
  while IFS= read -r -d $'\0' BLOCK_RAW <&3; do
    [[ -z "${BLOCK_RAW// }" ]] && continue
    BLOCK_DISPLAY=$(printf '%s' "${BLOCK_RAW}" | LC_ALL=C sed 's/\\n/\n/g')
    printf '%s\n' "${BLOCK_DISPLAY}" >> "${PENDING_BLOCKS_FILE}"
  done
  exec 3<&-
  set -e
  [[ "${SKIP_EXTRACT}" == 1 ]] && echo "" && echo "   → Schritt 5 übersprungen — alle Blöcke in History"
  [[ "${BLOCK_COUNT}" -eq 0 ]] && echo "" && echo "   ℹ️  Keine Blöcke >= ${MIN_BLOCK_LINES} Zeilen"
fi

# -----------------------------------------------------------------------------
# SCHRITT 6 — Dedup + Secret-Entfernung
# SINGLES_FILE + PENDING_BLOCKS_FILE → Dedup → CLEAN_FILE
# -----------------------------------------------------------------------------
echo ""
echo "🧹 SCHRITT 6 — History bereinigen"

if [[ -s "${PENDING_BLOCKS_FILE}" ]]; then
  cat "${PENDING_BLOCKS_FILE}" >> "${SINGLES_FILE}"
  echo "   ℹ️  Pending-Blöcke eingemischt: $(wc -l < "${PENDING_BLOCKS_FILE}" | tr -d ' ') Zeilen"
fi

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
  echo "   [DRY-RUN] Keine Änderungen geschrieben."
else
  ask CONFIRM "   Jetzt ${CLEAN_COUNT} Einträge in ${HISTFILE} schreiben? [J/n] "
  if [[ "${CONFIRM}" == "n" || "${CONFIRM}" == "N" ]]; then
    echo "   → Abgebrochen. Backup: ${BACKUP_DIR}/"
    exit 0
  fi

  for f in ~/.zsh_sessions/*.historynew(N) ~/.zsh_sessions/*.history(N); do
    [[ -f "$f" ]] && truncate -s 0 "$f" 2>/dev/null || true
  done
  echo "   ✓ Session-Dateien geleert"

  cp "${CLEAN_FILE}" "${HISTFILE}"
  echo "   ✓ ${HISTFILE} aktualisiert (${CLEAN_COUNT} Einträge)"
fi

rm -f "${MERGED_DUMP}" "${BLOCKS_RAW}" "${BLOCKS_RAW}.raw0" \
      "${SINGLES_FILE}" "${CLEAN_FILE}" "${SECRET_FILE}" \
      "${ENTRIES_TO_DELETE}" "${PENDING_BLOCKS_FILE}" \
      "/tmp/zsh_hist_filtered_${TIMESTAMP}.txt" \
      /tmp/zsh_hist_less_${TIMESTAMP}_*.txt 2>/dev/null || true

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
