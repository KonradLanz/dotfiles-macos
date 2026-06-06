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
#
# History-Formate die erkannt werden:
#   EXTENDED  ": TIMESTAMP:0;cmd\ncmd2"  — ZSH EXTENDED_HISTORY, \n-kodiert
#   SIMPLE    "cmd"  (eine oder mehrere Zeilen, Backslash-Continuation möglich)
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
LONG_THRESH=200    # Einzelzeilen >= dieser Zeichenanzahl → Schritt 5 Block-Review
MAX_LINE_LEN=500   # Einzelzeilen (non-backslash) > dieser Zeichenanzahl → in Backup sichern + entfernen

# --- AI Backend Config (local-ai-stack) ---
# Priorität: Ollama → LM Studio → Regex-Fallback
OLLAMA_BASE_URL="http://localhost:11434"
OLLAMA_MODEL="llama3.1:8b"
LMSTUDIO_BASE_URL="http://localhost:1234/v1"
# LMSTUDIO_MODEL wird automatisch ermittelt (erster geladener Slot)

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
# Hilfsfunktion: Ollama-Verfügbarkeit prüfen
# -----------------------------------------------------------------------------
_ollama_available() {
  curl -sf --max-time 2 "${OLLAMA_BASE_URL}/api/tags" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Hilfsfunktion: LM Studio-Verfügbarkeit prüfen
# LM Studio spricht die OpenAI-API auf Port 1234.
# Gibt 0 zurück wenn ein Modell geladen ist (models-Liste nicht leer).
# -----------------------------------------------------------------------------
_lmstudio_available() {
  local models
  models=$(curl -sf --max-time 2 "${LMSTUDIO_BASE_URL}/models" 2>/dev/null)
  [[ -n "${models}" ]] && echo "${models}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('ok' if d.get('data') else '')
except: pass
" 2>/dev/null | grep -q 'ok'
}

# Ermittelt den Namen des ersten geladenen LM Studio-Modells
_lmstudio_model() {
  curl -sf --max-time 2 "${LMSTUDIO_BASE_URL}/models" 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    models = d.get('data', [])
    print(models[0]['id'] if models else '')
except: pass
" 2>/dev/null
}

# -----------------------------------------------------------------------------
# AI-Backend-Status (gecacht, wird einmalig beim ersten Block ermittelt)
# Werte: 0=ungeprüft  1=Ollama  2=LMStudio  3=kein AI
# -----------------------------------------------------------------------------
_AI_BACKEND=0
_AI_BACKEND_LABEL=""

_detect_ai_backend() {
  [[ "${_AI_BACKEND}" -ne 0 ]] && return

  # 1. Ollama prüfen
  if _ollama_available; then
    _AI_BACKEND=1
    _AI_BACKEND_LABEL="Ollama (${OLLAMA_MODEL})"
    echo "   🤖 AI-Backend: ${_AI_BACKEND_LABEL}" >&2
    return
  fi

  # Ollama nicht aktiv → einmalig versuchen zu starten
  echo "   🤖 Ollama nicht aktiv — versuche zu starten..." >&2
  ollama serve >/dev/null 2>&1 &
  local waited=0
  while [[ ${waited} -lt 5 ]]; do
    sleep 1; waited=$(( waited + 1 ))
    if _ollama_available; then
      _AI_BACKEND=1
      _AI_BACKEND_LABEL="Ollama (${OLLAMA_MODEL}) [neu gestartet]"
      echo "   🤖 AI-Backend: ${_AI_BACKEND_LABEL}" >&2
      return
    fi
  done

  # 2. LM Studio prüfen
  if _lmstudio_available; then
    local lm_model
    lm_model=$(_lmstudio_model)
    _AI_BACKEND=2
    _AI_BACKEND_LABEL="LM Studio (${lm_model:-unbekannt})"
    echo "   🤖 AI-Backend: ${_AI_BACKEND_LABEL}" >&2
    return
  fi

  # 3. Kein AI verfügbar
  _AI_BACKEND=3
  echo "   ⚠️  Kein AI-Backend erreichbar — Fallback auf Regex-Namen" >&2
}

# -----------------------------------------------------------------------------
# Hilfsfunktion: AI-Namenvorschlag
# Unterstützt Ollama (/api/generate) und LM Studio (OpenAI /chat/completions).
#
# Prompt-Design: fordert explizit ein einzelnes snake_case-Wort ohne Erklärung.
# Parsing: nimmt nur das erste Whitespace-Token, strippt Backticks/Sonderzeichen,
# sodass auch verbose Modelle ("Here is the name: foo_bar") korrekt geparst werden.
# -----------------------------------------------------------------------------
_derive_script_name_ai() {
  local block="$1"
  _detect_ai_backend

  [[ "${_AI_BACKEND}" -eq 3 ]] && return 1

  local preview
  preview=$(printf '%s' "${block}" | head -8 | \
    python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null) || return 1

  # sys_prompt: klar und restriktiv — erstes Token muss der Name sein
  local sys_prompt="You are a filename generator. Output ONLY a single snake_case identifier (max 4 words joined by underscores, no extension, no date, all lowercase). Nothing else — no explanation, no punctuation, no markdown."
  local name raw_result

  # Gemeinsamer Python-Schnipsel zum robusten Parsen des Modell-Outputs.
  # Nimmt das erste nicht-leere Token, entfernt Backticks/Sonder­zeichen,
  # kürzt auf 40 Zeichen.
  local _parse_name_py
  _parse_name_py='
import sys, re
raw = sys.stdin.read().strip()
# Backticks, Anführungszeichen, Punkte entfernen
raw = raw.replace("`", "").replace("\'", "").replace('"', "").replace(".", "_")
# Erstes Whitespace-Token nehmen (verhindert dass Erklärungen durchkommen)
token = raw.split()[0] if raw.split() else ""
# Nur erlaubte Zeichen
token = re.sub(r"[^a-z0-9_]+", "_", token.lower())
token = re.sub(r"_+", "_", token).strip("_")
print(token[:40] if token else "")
'

  if [[ "${_AI_BACKEND}" -eq 1 ]]; then
    # --- Ollama: /api/generate ---
    raw_result=$(curl -sf --max-time 8 \
      "${OLLAMA_BASE_URL}/api/generate" \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c "
import json
print(json.dumps({
  'model': '${OLLAMA_MODEL}',
  'prompt': ${preview},
  'system': '${sys_prompt}',
  'stream': False,
  'options': {'num_predict': 15, 'temperature': 0.1}
}))
" 2>/dev/null)" 2>/dev/null) || return 1

    name=$(printf '%s' "${raw_result}" | python3 -c "
import sys, json
try:
    s = json.load(sys.stdin).get('response', '')
    sys.stdout.write(s)
except: pass
" 2>/dev/null | python3 -c "${_parse_name_py}" 2>/dev/null)

  elif [[ "${_AI_BACKEND}" -eq 2 ]]; then
    # --- LM Studio: OpenAI /chat/completions ---
    local lm_model
    lm_model=$(_lmstudio_model)
    raw_result=$(curl -sf --max-time 8 \
      "${LMSTUDIO_BASE_URL}/chat/completions" \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c "
import json
print(json.dumps({
  'model': '${lm_model}',
  'messages': [
    {'role': 'system', 'content': '${sys_prompt}'},
    {'role': 'user',   'content': 'Script content: ' + ${preview}}
  ],
  'max_tokens': 20,
  'temperature': 0.1,
  'stream': False
}))
" 2>/dev/null)" 2>/dev/null) || return 1

    name=$(printf '%s' "${raw_result}" | python3 -c "
import sys, json
try:
    s = json.load(sys.stdin)['choices'][0]['message']['content']
    sys.stdout.write(s)
except: pass
" 2>/dev/null | python3 -c "${_parse_name_py}" 2>/dev/null)
  fi

  [[ -n "${name}" ]] && echo "${name}" || return 1
}

# -----------------------------------------------------------------------------
# Hilfsfunktion: Regex-Fallback für Script-Name (acook-Bug gefixt)
# -----------------------------------------------------------------------------
_derive_script_name_fallback() {
  local block="$1" date_prefix=$(date +%Y%m%d) name=""
  name=$(echo "${block}" | LC_ALL=C sed 's/\\n/\n/g' | grep '^#' | head -1 \
    | sed 's/^#[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' ' '-' \
    | tr -cd 'a-z0-9-' \
    | sed 's/-\{2,\}/-/g' \
    | cut -c1-30)
  if [[ -z "${name}" ]]; then
    name=$(echo "${block}" | LC_ALL=C sed 's/\\n/\n/g' | grep -v '^#' | head -1 \
      | awk '{print $1}' \
      | tr '[:upper:]' '[:lower:]' \
      | tr -cd 'a-z0-9_-' \
      | cut -c1-20)
  fi
  [[ -z "${name}" ]] && name="script"
  echo "${date_prefix}_${name}"
}

# -----------------------------------------------------------------------------
# Hilfsfunktion: Script-Name ableiten (AI → Fallback)
# -----------------------------------------------------------------------------
_derive_script_name() {
  local block="$1" date_prefix=$(date +%Y%m%d) ai_name
  ai_name=$(_derive_script_name_ai "${block}" 2>/dev/null) && \
    echo "${date_prefix}_${ai_name}" || \
    _derive_script_name_fallback "${block}"
}

mkdir -p "${SCRIPTS_DIR}"
if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
  git -C "${SCRIPTS_DIR}" init -b main --quiet 2>/dev/null || git -C "${SCRIPTS_DIR}" init --quiet
fi

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
# SCHRITT 2a — History-Format erkennen
# -----------------------------------------------------------------------------
echo "   → History-Format erkennen..."

TOTAL_LINES="${MERGED_COUNT}"
EXTENDED_LINES=$(LC_ALL=C grep -c '^: [0-9][0-9]*:[0-9][0-9]*;' "${MERGED_DUMP}" 2>/dev/null || true)
EXTENDED_LINES=$(printf '%s' "${EXTENDED_LINES}" | tr -d ' \n\r\t')
[[ -z "${EXTENDED_LINES}" || "${EXTENDED_LINES}" == *[!0-9]* ]] && EXTENDED_LINES=0

EXTENDED_RATIO=0
if [[ "${TOTAL_LINES}" -gt 0 && "${EXTENDED_LINES}" -gt 0 ]]; then
  EXTENDED_RATIO=$(( EXTENDED_LINES * 100 / TOTAL_LINES ))
fi

if [[ "${EXTENDED_RATIO}" -ge 10 ]]; then
  HIST_FORMAT="EXTENDED"
  echo "   ✓ Format: EXTENDED (Timestamps, ${EXTENDED_LINES} von ${TOTAL_LINES} Zeilen = ${EXTENDED_RATIO}%)"
  echo "     → Multiline-Blöcke: \\n-kodiert auf einer Zeile"
else
  HIST_FORMAT="SIMPLE"
  echo "   ✓ Format: SIMPLE (keine Timestamps, ${EXTENDED_LINES} von ${TOTAL_LINES} Zeilen = ${EXTENDED_RATIO}%)"
  echo "     → Multiline-Blöcke: echte Zeilenumbrüche + Backslash-Continuation"
fi

# -----------------------------------------------------------------------------
# SCHRITT 2b — Block-Erkennung + Dedup
# -----------------------------------------------------------------------------
echo "   → Blöcke erkennen (>= ${MIN_BLOCK_LINES} Zeilen, oder >= ${LONG_THRESH} Zeichen)..."

touch "${BLOCKS_RAW}.raw0"

if [[ "${HIST_FORMAT}" == "EXTENDED" ]]; then
  LC_ALL=C grep '\\n.*\\n' "${MERGED_DUMP}" \
    | LC_ALL=C sed \
        -e 's/^[[:space:]]*[0-9]*[[:space:]]*//' \
        -e 's/^: [0-9]*:[0-9]*;//' \
        -e 's/\\n$//' \
    | LC_ALL=C tr '\n' '\0' \
    >> "${BLOCKS_RAW}.raw0" 2>/dev/null || true

  LC_ALL=C grep -v '\\n.*\\n' "${MERGED_DUMP}" \
    | LC_ALL=C awk -v thresh="${LONG_THRESH}" 'length >= thresh' \
    | LC_ALL=C sed \
        -e 's/^[[:space:]]*[0-9]*[[:space:]]*//' \
        -e 's/^: [0-9]*:[0-9]*;//' \
    | LC_ALL=C tr '\n' '\0' \
    >> "${BLOCKS_RAW}.raw0" 2>/dev/null || true

else
  export _MERGED_IN="${MERGED_DUMP}"
  export _BLOCKS_OUT="${BLOCKS_RAW}.raw0"
  export _SINGLES_OUT="${SINGLES_FILE}"
  export _LONG_THRESH="${LONG_THRESH}"

  python3 << 'PYEOF_SIMPLE'
import os, sys, re

merged_in   = os.environ['_MERGED_IN']
blocks_out  = os.environ['_BLOCKS_OUT']
singles_out = os.environ['_SINGLES_OUT']
long_thresh = int(os.environ['_LONG_THRESH'])

def strip_prefix(line):
    line = re.sub(r'^: \d+:\d+;', '', line)
    line = re.sub(r'^\s*\d+\s+', '', line)
    return line

try:
    raw_lines = open(merged_in, encoding='utf-8', errors='replace').readlines()
except Exception:
    sys.exit(0)

blocks  = []
singles = []

i = 0
while i < len(raw_lines):
    line = raw_lines[i].rstrip('\n')
    stripped = strip_prefix(line)

    if stripped.endswith('\\'):
        block_lines = [stripped]
        i += 1
        while i < len(raw_lines):
            nxt = raw_lines[i].rstrip('\n')
            nxt_stripped = strip_prefix(nxt)
            block_lines.append(nxt_stripped)
            i += 1
            if not nxt_stripped.endswith('\\'):
                break
        blocks.append('\n'.join(block_lines))
    else:
        if stripped and len(stripped) >= long_thresh:
            blocks.append(stripped)
        elif stripped:
            singles.append(stripped)
        i += 1

with open(blocks_out, 'ab') as f:
    for b in blocks:
        f.write(b.encode('utf-8', errors='replace') + b'\x00')

with open(singles_out, 'a', encoding='utf-8', errors='replace') as f:
    for s in singles:
        f.write(s + '\n')
PYEOF_SIMPLE

  unset _MERGED_IN _BLOCKS_OUT _SINGLES_OUT _LONG_THRESH
fi

export _BLOCKS_RAW_IN="${BLOCKS_RAW}.raw0"
export _BLOCKS_RAW_OUT="${BLOCKS_RAW}"
BLOCK_COUNT=$(python3 << 'PYEOF_DEDUP'
import re, os, sys

try:
    data = open(os.environ['_BLOCKS_RAW_IN'], 'rb').read()
except Exception:
    print(0)
    raise SystemExit

raw_blocks = [b for b in data.split(b'\x00') if b.strip()]
seen = set()
uniq = []
for b in raw_blocks:
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
# SCHRITT 2c — Normalisierung Einzelzeilen (nur EXTENDED-Modus)
# -----------------------------------------------------------------------------
if [[ "${HIST_FORMAT}" == "EXTENDED" ]]; then
  echo "   → Normalisierung Einzelzeilen (EXTENDED)..."

  LC_ALL=C grep -v '\\n.*\\n' "${MERGED_DUMP}" \
    | LC_ALL=C awk -v thresh="${LONG_THRESH}" 'length < thresh' \
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
" 2>/dev/null >> "${SINGLES_FILE}" || true

else
  echo "   → Einzelzeilen bereits durch Python normalisiert (SIMPLE)"
fi

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
# SCHRITT 5 — Interaktive Block-Extraktion
# -----------------------------------------------------------------------------
touch "${PENDING_BLOCKS_FILE}"

if [[ "${SKIP_EXTRACT}" == 0 && "${BLOCK_COUNT}" -gt 0 ]]; then
  echo ""
  echo "📦 SCHRITT 5 — Mehrzeilige Blöcke & lange Einzelbefehle extrahieren"
  [[ "${DRY_RUN}" == 1 ]] && echo "   ⚠️  DRY-RUN: Aktionen simuliert, nichts geschrieben"
  echo "   Blöcke (nach Dedup): ${BLOCK_COUNT}  —  nicht entschiedene kommen in History"
  echo ""

  BLOCK_IDX=0
  EXTRACTED_COUNT=0
  DELETED_COUNT=0
  KEPT_COUNT=0
  ABORT=0

  _show_block_lines() {
    local display="$1" total_lines=$2 idx=$3 total_blocks=$4 from_line=$5 suggested="$6"
    local show_to=$(( from_line + 10 ))
    [[ ${show_to} -gt ${total_lines} ]] && show_to=${total_lines}
    echo "   +----------------------------------------------------------+"
    printf "   |  Block [%d/%d] — %d Zeilen  (Zeilen %d–%d)\n" \
      ${idx} ${total_blocks} ${total_lines} $(( from_line + 1 )) ${show_to}
    # Namensvorschlag direkt im Header anzeigen (schon bereit wenn du [s] drückst)
    [[ -n "${suggested}" ]] && printf "   |  🏷  Vorschlag: %s\n" "${suggested}"
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
    # AI-Vorschlag VOR dem Anzeigen berechnen → ist schon im Header sichtbar
    SUGGESTED=$(_derive_script_name "${BLOCK_RAW}")
    PREVIEW_FROM=0

    _show_block_lines "${BLOCK_DISPLAY}" ${BLOCK_LINES} \
      ${BLOCK_IDX} ${BLOCK_COUNT} ${PREVIEW_FROM} "${SUGGESTED}"
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
              ${BLOCK_IDX} ${BLOCK_COUNT} ${PREVIEW_FROM} "${SUGGESTED}"
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
# SCHRITT 6 — Dedup + Secret-Entfernung + sehr lange Zeilen sichern & entfernen
# -----------------------------------------------------------------------------
echo ""
echo "🧹 SCHRITT 6 — History bereinigen"

if [[ -s "${PENDING_BLOCKS_FILE}" ]]; then
  cat "${PENDING_BLOCKS_FILE}" >> "${SINGLES_FILE}"
  echo "   ℹ️  Pending-Blöcke eingemischt: $(wc -l < "${PENDING_BLOCKS_FILE}" | tr -d ' ') Zeilen"
fi

ENTRIES_TO_DELETE="/tmp/zsh_hist_delete_${TIMESTAMP}.txt"
LONGLINES_BACKUP="${BACKUP_DIR}/zsh_hist_longlines.${TIMESTAMP}.txt"
touch "${ENTRIES_TO_DELETE}"

[[ "${REMOVE_SECRETS}" == "J" ]] && \
  LC_ALL=C grep '^\[.*\] ' "${SECRET_FILE}" | LC_ALL=C sed 's/^\[.*\] //' >> "${ENTRIES_TO_DELETE}"

LC_ALL=C awk \
  -v maxlen="${MAX_LINE_LEN}" \
  -v longbak="${LONGLINES_BACKUP}" \
  '
  /^[[:space:]]*$/ { next }
  /\\$/ {
    print
    next
  }
  length > maxlen {
    print > longbak
    next
  }
  !seen[$0]++ {
    print
  }
  ' "${SINGLES_FILE}" > "${CLEAN_FILE}"

LONGLINES_COUNT=0
[[ -f "${LONGLINES_BACKUP}" ]] && LONGLINES_COUNT=$(wc -l < "${LONGLINES_BACKUP}" | tr -d ' ')
if [[ "${LONGLINES_COUNT}" -gt 0 ]]; then
  echo "   ℹ️  ${LONGLINES_COUNT} sehr lange Zeilen (> ${MAX_LINE_LEN} Zeichen) gesichert:"
  echo "      → ${LONGLINES_BACKUP}"
fi

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
