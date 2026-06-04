# =============================================================================
# bracket-paste-guard.zsh
# =============================================================================
# Verhindert, dass versehentlich eingefügter Text sofort ausgeführt wird.
#
# Problem: Wenn du Text aus dem Browser/Editor in ein Terminal kopierst,
# sendet das Terminal Bracket Paste Escape-Sequenzen (ESC[200~ ... ESC[201~).
# Ohne diesen Guard wird mehrzeiliger Text Zeile für Zeile ausgeführt —
# gefährlich bei Passwörtern, langen Kommando-Ketten, etc.
#
# Was dieser Guard tut:
#   1. Aktiviert Bracket Paste Mode (zsh-bracketed-paste Widget)
#   2. Überschreibt bracketed-paste mit einem sicheren Handler:
#      - Eingefügter Text landet im Eingabepuffer, wird NICHT ausgeführt
#      - Mehrzeilige Pastes werden zu einer Zeile zusammengefasst
#        (Newlines → Semikolon, damit der Nutzer prüfen kann)
#      - Zeigt Warnung wenn Paste >3 Zeilen oder >200 Zeichen enthält
#   3. Verhindert dass [200~ Artefakte in die History gelangen
#
# Installation:
#   In ~/.zshrc einfügen:
#     source ~/git/dotfiles-macos/history-cleanup/bracket-paste-guard.zsh
# =============================================================================

# Bracket Paste Mode aktivieren (zsh 5.1+)
if autoload -Uz bracketed-paste-url-magic 2>/dev/null; then
  zle -N bracketed-paste bracketed-paste-url-magic
fi

# Sicherer Paste-Handler
_safe_paste() {
  local paste_content
  zle -R "Paste wird gelesen..."

  # Lese den eingefügten Inhalt
  local buf=""
  while IFS= read -r -t 0.1 line; do
    buf+="${line}\n"
  done

  # Alternativ: Standard zsh bracketed-paste Buffer-Mechanismus
  # (funktioniert zuverlässiger als read)
  if [[ -n "$POSTDISPLAY" ]]; then
    buf="$POSTDISPLAY"
    POSTDISPLAY=""
  fi

  paste_content="${CUTBUFFER}"
  [[ -z "$paste_content" ]] && paste_content="$buf"

  local line_count=$(echo -n "$paste_content" | wc -l | tr -d ' ')
  local char_count=${#paste_content}

  if [[ $line_count -gt 2 || $char_count -gt 200 ]]; then
    # Warnung anzeigen
    zle -M "⚠️  Großer Paste: ${line_count} Zeilen, ${char_count} Zeichen — Enter zum Ausführen nötig!"
    # Newlines zu Semikolons (verhindert sofortige Ausführung)
    paste_content=$(echo -n "$paste_content" | tr '\n' ';' | sed 's/;$//')
  fi

  # In den Eingabepuffer schreiben (NICHT ausführen)
  LBUFFER+="$paste_content"
}

# Hinweis: Der zuverlässigste Weg auf macOS mit zsh ist das eingebaute
# bracketed-paste Widget zu nutzen (verfügbar seit zsh 5.1 / macOS 10.15+)
#
# Die einfachste und robusteste Lösung:
bracketedpaste_safe() {
  local i lbuf rbuf
  read -r -d $'\e[201~' -u 0 i
  lbuf=$LBUFFER
  rbuf=$RBUFFER

  local linecount=$(printf '%s' "$i" | wc -l | tr -d ' ')
  local charcount=${#i}

  # Warnung bei großem Paste
  if [[ $linecount -gt 2 || $charcount -gt 200 ]]; then
    printf '\r\n⚠️  Paste: %d Zeilen, %d Zeichen\n' "$linecount" "$charcount"
    printf '   Mehrzeilig → Newlines als Semikolon (prüfen vor Enter!)\n\r'
    # Newlines durch Semikolon ersetzen — verhindert sofortige Ausführung
    i=$(printf '%s' "$i" | tr '\n' ';' | sed 's/;;*/;/g; s/;$//')
  else
    # Einfacher Paste: direkt, aber Newlines trotzdem entschärfen
    i=$(printf '%s' "$i" | tr '\n' ' ')
  fi

  LBUFFER=${lbuf}${i}
  RBUFFER=$rbuf
}

# Widget registrieren
if [[ -n "$ZLE_VERSION" ]] || true; then
  zle -N bracketed-paste bracketedpaste_safe
fi

# History-Filter: [200~ Artefakte aus der History entfernen
# Wird nach jedem Kommando geprüft (zshaddhistory Hook)
zshaddhistory_no_paste_artifacts() {
  local cmd="$1"
  # Kommandos die mit [200~ beginnen nicht in History speichern
  [[ "$cmd" == $'\e[200~'* ]] && return 1
  [[ "$cmd" == '[200~'* ]]   && return 1
  # Kommandos die reine Zeilennummern sind nicht speichern (fc -l Artefakt)
  [[ "$cmd" =~ ^[[:space:]]+[0-9]+[[:space:]] ]] && return 1
  return 0
}
add-zsh-hook zshaddhistory zshaddhistory_no_paste_artifacts
