#!/usr/bin/env zsh
# =============================================================================
# reload-zshrc-all-tabs.sh
# Sendet 'source ~/.zshrc' via AppleScript an alle idle macOS Terminal-Tabs.
# Eigenes Terminal wird direkt gesourct.
#
# Usage:
#   zsh ~/git/dotfiles-macos/history-cleanup/reload-zshrc-all-tabs.sh
# =============================================================================

echo ""
echo "  zshrc Reload -- alle Terminal-Tabs"
echo ""

# -----------------------------------------------------------------------------
# 1. Eigenes Terminal sofort
# -----------------------------------------------------------------------------
if [[ -f "${HOME}/.zshrc" ]]; then
  source "${HOME}/.zshrc"
  echo "   OK: source ~/.zshrc (dieses Terminal) ausgefuehrt"
else
  echo "   WARN: ~/.zshrc nicht gefunden -- uebersprungen"
fi

# -----------------------------------------------------------------------------
# 2. Alle anderen Tabs via AppleScript
# Kein Unicode-Escape im do-script String (AppleScript kennt keine \uXXXX).
# Rueckgabe: "OK:SENT:BUSY:SELF" oder "ERROR:..."
# Parsing: lokale Variablen statt verschachtelter ${...}-Expansion.
# -----------------------------------------------------------------------------
echo ""
echo "   Sende 'source ~/.zshrc' an alle idle Tabs..."
echo ""

RESULT=$(osascript 2>&1 << 'APPLESCRIPT_EOF'
  set sent_count to 0
  set skipped_busy to 0
  set skipped_self to 0
  set err_msg to ""

  try
    tell application "Terminal"
      set front_tab to selected tab of front window
      repeat with w in windows
        repeat with t in tabs of w
          try
            if t is front_tab then
              set skipped_self to skipped_self + 1
            else if busy of t is false then
              do script "source ~/.zshrc" in t
              set sent_count to sent_count + 1
            else
              set skipped_busy to skipped_busy + 1
            end if
          on error e
            set skipped_busy to skipped_busy + 1
          end try
        end repeat
      end repeat
    end tell
  on error e
    set err_msg to e
  end try

  if err_msg is not "" then
    return "ERROR:" & err_msg
  else
    return "OK:" & sent_count & ":" & skipped_busy & ":" & skipped_self
  end if
APPLESCRIPT_EOF
)

# Robustes Parsing ohne verschachtelte ${...}-Expansion
# Format erwartet: OK:SENT:SKIPPED_BUSY:SKIPPED_SELF
if [[ "${RESULT}" == ERROR:* ]]; then
  echo "   FEHLER AppleScript: ${RESULT#ERROR:}"
  echo "   -> Bitte 'source ~/.zshrc' in anderen Tabs manuell ausfuehren."
else
  _r="${RESULT#OK:}"
  _SENT="${_r%%:*}"         ; _r="${_r#*:}"
  _BUSY="${_r%%:*}"         ; _r="${_r#*:}"
  _SELF="${_r%%:*}"

  # Numerisch validieren bevor -gt verwendet wird
  [[ "${_SENT}" =~ ^[0-9]+$ ]] || _SENT=0
  [[ "${_BUSY}" =~ ^[0-9]+$ ]] || _BUSY=0
  [[ "${_SELF}" =~ ^[0-9]+$ ]] || _SELF=0

  echo "   OK: source ~/.zshrc gesendet an ${_SENT} Tab(s)"
  [[ ${_BUSY} -gt 0 ]] && echo "   INFO: ${_BUSY} Tab(s) uebersprungen (busy)"
  [[ ${_SELF} -gt 0 ]] && echo "   INFO: ${_SELF} Tab (dieses) direkt gesourct"
fi

echo ""
echo "   Fertig."
echo ""
