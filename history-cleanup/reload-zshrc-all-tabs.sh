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
echo "↺  zshrc Reload — alle Terminal-Tabs"
echo ""

# -----------------------------------------------------------------------------
# 1. Eigenes Terminal sofort
# -----------------------------------------------------------------------------
if [[ -f "${HOME}/.zshrc" ]]; then
  source "${HOME}/.zshrc"
  echo "   ✓ source ~/.zshrc (dieses Terminal) ausgeführt"
else
  echo "   ⚠️  ~/.zshrc nicht gefunden — übersprungen"
fi

# -----------------------------------------------------------------------------
# 2. Alle anderen Tabs via AppleScript
# Tabs mit laufendem Prozess (busy=true) werden übersprungen.
# -----------------------------------------------------------------------------
echo ""
echo "   ┌─────────────────────────────────────────────────────────┐"
echo "   │  Nur idle Tabs erhalten 'source ~/.zshrc'.         │"
echo "   │  Busy Tabs (laufender Prozess) werden übersprungen. │"
echo "   └─────────────────────────────────────────────────────────┘"
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
              do script "source ~/.zshrc && echo '   \u2713 source ~/.zshrc done'" in t
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

if [[ "${RESULT}" == ERROR:* ]]; then
  echo "   ⚠️  AppleScript Fehler: ${RESULT#ERROR:}"
  echo "   → Bitte 'source ~/.zshrc' in anderen Tabs manuell ausführen."
else
  SENT="${${RESULT#OK:}%%:*}"
  REST="${RESULT#OK:*:}"
  SKIPPED_BUSY="${REST%%:*}"
  SKIPPED_SELF="${REST##*:}"
  echo "   ✓ source ~/.zshrc gesendet an: ${SENT} Tab(s)"
  [[ "${SKIPPED_BUSY}" -gt 0 ]] && \
    echo "   ℹ️  ${SKIPPED_BUSY} Tab(s) übersprungen (busy)"
  [[ "${SKIPPED_SELF}" -gt 0 ]] && \
    echo "   ℹ️  ${SKIPPED_SELF} Tab (dieses) bereits direkt gesourct"
fi

echo ""
echo "   ✔  Fertig."
echo ""
