#!/usr/bin/env zsh
# =============================================================================
# find-safe — find mit komprimierter Fehlerausgabe
# =============================================================================
# Standard-find: jede Permission-Error erscheint als eigene Zeile auf stderr
# find-safe: sammelt alle blocked Pfade und zeigt sie kompakt am Ende
#
# Usage:
#   find-safe [find-argumente]  (dieselbe Syntax wie find)
#   find-safe . -iname "*.sh"
#   find-safe ~ -name "*.conf" -type f
#
# Output:
#   ./git/bootstrap-foundation/macos/brew-tracker/setup.sh
#   ./git/bootstrap-foundation/macos/brew-tracker/brew-diff.sh
#   ...
#   ⚠️  find: Operation not permitted (3 Pfade):
#        [d: ./Pictures/Photos\ Library.photoslibrary  d: ./Desktop  d: ./Library/Group\ Containers/...]
# =============================================================================

# Temporäre Datei für gesammelte Fehler
ERR_TMP=$(mktemp /tmp/find_blocked_XXXX)

# find ausführen, stderr in Temp-Datei
find "$@" 2>"${ERR_TMP}"
FIND_EXIT=$?

# Fehler verarbeiten
if [[ -s "${ERR_TMP}" ]]; then
  # Extrahiere die blockierten Pfade aus find-Fehlermeldungen
  # Format: "find: ./path: Operation not permitted"
  BLOCKED=$(grep -o 'find: .*: Operation not permitted' "${ERR_TMP}" | \
    sed 's/find: //; s/: Operation not permitted//' | \
    while read -r p; do
      # Prüfe ob Verzeichnis oder Datei
      if [[ -d "$p" ]] 2>/dev/null; then
        printf 'd: %s  ' "$(printf '%q' "$p")"
      else
        printf 'f: %s  ' "$(printf '%q' "$p")"
      fi
    done)
  COUNT=$(grep -c 'Operation not permitted' "${ERR_TMP}" || echo 0)

  # Andere Fehler (nicht nur Permission)
  OTHER_ERRORS=$(grep -v 'Operation not permitted' "${ERR_TMP}" || true)

  # Kompakte Ausgabe auf stderr
  echo "⚠️  find: Operation not permitted (${COUNT} Pfade):" >&2
  echo "     [${BLOCKED}]" >&2

  if [[ -n "${OTHER_ERRORS}" ]]; then
    echo "     Weitere Fehler:" >&2
    echo "${OTHER_ERRORS}" >&2
  fi
fi

rm -f "${ERR_TMP}"
exit ${FIND_EXIT}
