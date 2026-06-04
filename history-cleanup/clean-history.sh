#!/usr/bin/env zsh
# =============================================================================
# clean-history.sh — ZSH History Cleanup + Long-Entry Extractor + Secret Detector
# =============================================================================
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
#   zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --skip-extract
#
# Format der .historynew Dateien (macOS Terminal.app):
#   Plain-Zeilen ohne Timestamp.
#   Frühere fc-l Dumps können Zeilennummern enthalten: "   11  befehl"
#   Mehrzeiler aus copy-paste: Backslash am Zeilenende, Leerzeile = Block-Ende
#   Mehrzeiler aus fc-l Dumps: literales \n als Trennzeichen
#
# Normalisierungs-Pipeline (Schritt 2b):
#   1. trailing \n entfernen (vermeidet Leerzeilen nach Split)
#   2. literales \n → echter Zeilenumbruch
#   3. Zeilennummer-Prefix entfernen ("   11  " → "")
#   4. zsh extended history Prefix entfernen (": 123:0;" → "")
#   5. Backslash-Continuation Blöcke → auto in ~/scripts/ extrahieren
#
# AppleScript fc -W (Schritt 1.5):
#   Schickt fc -W an alle idle Terminal.app Tabs (busy=false).
#   Benötigt Accessibility-Rechte (Einstellungen > Datenschutz > Bedienungshilfen).
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 0 — Auto-Pull (Script immer aktuell halten)
# Fix: ${(%):-%x} gibt den echten Pfad des laufenden Scripts zurück,
#      unabhängig vom CWD wo der Aufruf stattfindet.
# ─────────────────────────────────────────────────────────────────────────────
_SCRIPT_DIR="${${(%):-%x}:A:h}"
if [[ -d "${_SCRIPT_DIR}/../.git" ]]; then
  _PULL_OUT=$(git -C "${_SCRIPT_DIR}/.." pull --ff-only --quiet 2>&1)
  _PULL_RC=$?
  if [[ ${_PULL_RC} -eq 0 ]]; then
    if [[ -n "${_PULL_OUT}" ]]; then
      echo "🔄 Script aktualisiert (git pull)"
    fi
  else
    echo "⚠️  git pull fehlgeschlagen (offline oder Konflikt) — lokale Version wird verwendet"
  fi
fi

_HISTFILE_DEFAULT="${HOME}/.zsh_history"
if [[ -n "${HISTFILE+x}" ]]; then
  _HISTFILE="${HISTFILE}"
else
  _HISTFILE="${_HISTFILE_DEFAULT}"
fi

set -eo pipefail

# --- Config ---
HISTFILE="${_HISTFILE}"
BACKUP_DIR="${HOME}/.zsh_history_backups"
SCRIPTS_DIR="${HOME}/scripts"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
MERGED_DUMP="/tmp/zsh_hist_merged_${TIMESTAMP}.txt"
NORM_DUMP="/tmp/zsh_hist_norm_${TIMESTAMP}.txt"
BLOCKS_FILE="/tmp/zsh_hist_blocks_${TIMESTAMP}.txt"
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

# Rahmen-Hilfsfunktion: Zeile mit padding auf feste Breite bringen
# Breite = 54 Zeichen innen (zwischen ║ und ║)
_box_line() {
  local text="$1"
  local width=54
  # Zeichen zählen (nicht Bytes) für korrekte Padding-Berechnung
  local textlen=${#text}
  local pad=$(( width - textlen ))
  [[ $pad -lt 0 ]] && pad=0
  printf "   ║  %s%${pad}s║\n" "${text}" ""
}

echo ""
echo "╔══════════════════════════════════════════════════════╗"
printf "║         ZSH History Cleanup — %-22s║\n" "$(date '+%Y-%m-%d %H:%M')       "
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1 — Offene Terminal-Sessions analysieren
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
  read "?   Enter zum Fortfahren: "
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 1.5 — fc -W in alle anderen Terminal.app Tabs schicken (optional)
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📲 SCHRITT 1.5 — fc -W in andere Terminal.app Tabs schicken"
echo ""
echo "   Soll fc -W via AppleScript an alle anderen idle Terminal.app"
echo "   Fenster/Tabs geschickt werden? (Tabs mit laufendem Prozess"
echo "   werden automatisch übersprungen.)"
echo ""
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │  ⚠️  VORAUSSETZUNG: Alle anderen Terminal-Tabs müssen   │"
echo "   │  eine LEERE Eingabezeile haben (kein halbfertiger       │"
echo "   │  Befehl!). Sonst wird fc -W direkt angehängt und        │"
echo "   │  verursacht einen Fehler (z.B. «fc: bad option: -c»).   │"
echo "   │                                                         │"
echo "   │  Falls nicht sicher: [n] wählen und manuell             │"
echo "   │  'fc -W' in jedem anderen Tab eingeben.                 │"
echo "   └─────────────────────────────────────────────────────────┘"
echo ""
echo "   Voraussetzung: Terminal.app hat Accessibility-Rechte"
echo "   (Einstellungen > Datenschutz > Bedienungshilfen)"
echo ""
read "APPLESCRIPT_RUN?   fc -W an alle anderen Tabs schicken? [J/n] "

if [[ "${APPLESCRIPT_RUN}" != "n" && "${APPLESCRIPT_RUN}" != "N" ]]; then
  echo ""
  echo "   → Sende fc -W an alle idle Terminal.app Tabs..."

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
    echo "   → Weiter ohne automatisches fc -W"
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

# Quelle 1: In-Memory History dieses Terminals
fc -ln 1 > "${MERGED_DUMP}" 2>/dev/null || true

# Quelle 2: Session-Files
for f in ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
  if [[ -f "$f" && -s "$f" ]]; then
    cat "$f" >> "${MERGED_DUMP}" 2>/dev/null || true
  fi
done

# Quelle 3: ~/.zsh_history
if [[ -f "${HISTFILE}" ]]; then
  cat "${HISTFILE}" >> "${MERGED_DUMP}" 2>/dev/null || true
fi

MERGED_COUNT=$(wc -l < "${MERGED_DUMP}" | tr -d ' ')
echo "   ✓ Gesamt gesammelt: ${MERGED_COUNT} Rohzeilen"

if [[ "${MERGED_COUNT}" -eq 0 ]]; then
  echo ""
  echo "   ❌ FEHLER: Keine History-Daten gefunden!"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2b — Normalisierung
# ─────────────────────────────────────────────────────────────────────────────
echo "   → Normalisierung..."

LC_ALL=C sed 's/\\n$//' "${MERGED_DUMP}" \
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
  ' > "${NORM_DUMP}"

NORM_COUNT=$(wc -l < "${NORM_DUMP}" | tr -d ' ')
echo "   ✓ Normalisiert: ${NORM_COUNT} Zeilen"

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 2c — Backslash-Continuation Blöcke extrahieren
# ─────────────────────────────────────────────────────────────────────────────
# Blöcke: Zeile endet auf \ → sammeln bis Leerzeile oder Zeile ohne \
# Ausgabe: NUL-separierte Blöcke in .raw, plain Zeilen in BLOCKS_FILE
# Block-Zählung: via python3 (macOS awk \x00-Matching unzuverlässig)
# Block-Loop: liest .raw über fd 3 → stdin bleibt frei für interactive read
# ─────────────────────────────────────────────────────────────────────────────
echo "   → Blöcke erkennen..."
mkdir -p "${SCRIPTS_DIR}"

if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
  git -C "${SCRIPTS_DIR}" init -b main --quiet 2>/dev/null || \
  git -C "${SCRIPTS_DIR}" init --quiet
fi

_derive_script_name() {
  local block="$1"
  local date_prefix=$(date +%Y%m%d)
  local name=""
  name=$(echo "${block}" | grep '^#' | head -1 | sed 's/^#[[:space:]]*//' | tr ' ' '-' | tr -cd 'a-z0-9-' | cut -c1-30)
  if [[ -z "${name}" ]]; then
    name=$(echo "${block}" | grep -v '^#' | head -1 | awk '{print $1}' | tr -cd 'a-z0-9_-' | cut -c1-20)
  fi
  [[ -z "${name}" ]] && name="script"
  echo "${date_prefix}_${name}"
}

# Blöcke → .raw (NUL-separiert), plain Zeilen → BLOCKS_FILE
LC_ALL=C awk '
/\\$/ {
  sub(/\\$/, "")
  block = (block == "") ? $0 : block "\n" $0
  next
}
/^[[:space:]]*$/ {
  if (block != "") { printf "%s\x00", block; block = "" }
  next
}
{
  if (block != "") { printf "%s\x00", block; block = "" }
  print $0
}
END { if (block != "") printf "%s\x00", block }
' "${NORM_DUMP}" > "${BLOCKS_FILE}.raw"

LC_ALL=C awk '
/\\$/ {
  sub(/\\$/, "")
  block = (block == "") ? $0 : block "\n" $0
  next
}
/^[[:space:]]*$/ {
  if (block != "") { block = "" }
  next
}
{
  if (block != "") { block = ""; next }
  print $0
}
' "${NORM_DUMP}" > "${BLOCKS_FILE}"

# Block-Zählung via python3 — macOS awk \x00 unzuverlässig
BLOCK_COUNT=$(python3 -c "
import sys
data = open('${BLOCKS_FILE}.raw', 'rb').read()
print(data.count(b'\\x00'))
" 2>/dev/null || echo 0)

PLAIN_COUNT=$(wc -l < "${BLOCKS_FILE}" | tr -d ' ')
echo "   ✓ Blöcke erkannt: ${BLOCK_COUNT} (→ ~/scripts/)"
echo "   ✓ Einzelzeilen:   ${PLAIN_COUNT}"

if [[ "${BLOCK_COUNT}" -gt 0 && "${SKIP_EXTRACT}" == 0 ]]; then
  echo ""
  echo "📦 Blöcke werden automatisch nach ${SCRIPTS_DIR}/ extrahiert..."
  echo ""

  BLOCK_IDX=0
  # fd 3 → stdin bleibt frei für read (interaktive Eingabe im Loop)
  exec 3< "${BLOCKS_FILE}.raw"
  while IFS= read -r -d $'\0' BLOCK <&3; do
    BLOCK_IDX=$((BLOCK_IDX + 1))
    SUGGESTED=$(_derive_script_name "${BLOCK}")
    PREVIEW=$(echo "${BLOCK}" | head -3)

    echo "   [${BLOCK_IDX}/${BLOCK_COUNT}] Vorgeschlagener Name: ${SUGGESTED}"
    echo "   Preview:"
    echo "${PREVIEW}" | sed 's/^/     /'
    echo ""

    if [[ "${SUGGESTED}" == *"_script" && $(echo "${BLOCK}" | grep -c '^#') -eq 0 ]]; then
      read "BNAME?   Name (Enter = ${SUGGESTED}, d = löschen, s = überspringen): "
    else
      read "BNAME?   Enter = ${SUGGESTED}, anderer Name, d = löschen, s = überspringen: "
    fi

    case "${BNAME}" in
      d|D)
        echo "   → Gelöscht (nicht extrahiert)"
        continue
        ;;
      s|S)
        echo "   → Übersprungen (bleibt in History)"
        echo "${BLOCK}" >> "${BLOCKS_FILE}"
        continue
        ;;
      "")
        FINAL_NAME="${SUGGESTED}"
        ;;
      *)
        FINAL_NAME="${BNAME}"
        ;;
    esac

    [[ "${FINAL_NAME}" != *.sh ]] && FINAL_NAME="${FINAL_NAME}.sh"
    [[ ! "${FINAL_NAME}" =~ ^[0-9]{8}_ ]] && FINAL_NAME="$(date +%Y%m%d)_${FINAL_NAME}"

    SPATH="${SCRIPTS_DIR}/${FINAL_NAME}"

    if [[ "${DRY_RUN}" == 1 ]]; then
      echo "   [DRY-RUN] Würde speichern: ${SPATH}"
    else
      printf '#!/usr/bin/env zsh\n# Extracted: %s\n# From: zsh history cleanup\n# ---\n\n%s\n' \
        "$(date '+%Y-%m-%d %H:%M')" "${BLOCK}" > "${SPATH}"
      chmod +x "${SPATH}"
      git -C "${SCRIPTS_DIR}" add "${FINAL_NAME}" 2>/dev/null || true
      git -C "${SCRIPTS_DIR}" commit -m "extract: ${FINAL_NAME}" --quiet 2>/dev/null || true
      echo "   ✓ Gespeichert + committed: ${SPATH}"
    fi
    echo ""
  done
  exec 3<&-
fi

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 3 — Lange Einträge finden
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "📏 SCHRITT 3 — Lange Einträge analysieren (>${LONG_THRESH} Zeichen)"

LC_ALL=C awk -v thresh="${LONG_THRESH}" '
  length($0) > thresh { print }
' "${BLOCKS_FILE}" | LC_ALL=C sort -u > "${LONG_FILE}"

LONG_COUNT=$(wc -l < "${LONG_FILE}" | tr -d ' ')
echo "   Gefunden: ${LONG_COUNT} lange Einträge (>${LONG_THRESH} Zeichen)"

# ─────────────────────────────────────────────────────────────────────────────
# SCHRITT 4 — Secret-Erkennung
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "🔐 SCHRITT 4 — Secret-Erkennung"

export BLOCKS_FILE
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
    with open(os.environ.get('BLOCKS_FILE', '/tmp/blocks.txt')) as f:
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

  INDEX=0
  while IFS= read -r ENTRY; do
    INDEX=$((INDEX + 1))
    # LC_ALL=C für cut → keine "Illegal byte sequence" bei non-ASCII
    PREVIEW=$(echo "${ENTRY}" | LC_ALL=C cut -c1-80)
    echo ""
    echo "   [$INDEX/${LONG_COUNT}] (${#ENTRY} Zeichen)"
    echo "   ${PREVIEW}..."
    echo ""
    echo "   [s] Als Script   [i] In History behalten   [d] Löschen   [q] Abbrechen"
    read "ACTION?   Aktion: "

    case "${ACTION}" in
      s|S)
        DATE_PREFIX=$(date +%Y%m%d)
        SUGGESTION=$(echo "${ENTRY}" | awk '{print $1}' | tr -cd 'a-z0-9_-' | LC_ALL=C cut -c1-20)
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
        git -C "${SCRIPTS_DIR}" add "${SNAME}" 2>/dev/null || true
        git -C "${SCRIPTS_DIR}" commit -m "extract: ${SNAME}" --quiet 2>/dev/null || true
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
  /^[[:space:]]*$/ { next }
  !seen[$0]++      { print }
' "${BLOCKS_FILE}" > "${CLEAN_FILE}"

if [[ -s "${ENTRIES_TO_DELETE}" ]]; then
  TEMP_FILTERED="/tmp/zsh_hist_filtered_${TIMESTAMP}.txt"
  grep -vxFf "${ENTRIES_TO_DELETE}" "${CLEAN_FILE}" > "${TEMP_FILTERED}" 2>/dev/null \
    || cp "${CLEAN_FILE}" "${TEMP_FILTERED}"
  mv "${TEMP_FILTERED}" "${CLEAN_FILE}"
fi

CLEAN_COUNT=$(wc -l < "${CLEAN_FILE}" | tr -d ' ')
echo "   ✓ Bereinigt: ${CLEAN_COUNT} Einträge (war: ${MERGED_COUNT} Rohzeilen)"

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

rm -f "${MERGED_DUMP}" "${NORM_DUMP}" "${BLOCKS_FILE}" "${BLOCKS_FILE}.raw" \
      "${CLEAN_FILE}" "${LONG_FILE}" "${LONG_FILE}.delete" \
      "${SECRET_FILE}" "${ENTRIES_TO_DELETE}" 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ Fertig!  Backup: ~/.zsh_history_backups/         ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
