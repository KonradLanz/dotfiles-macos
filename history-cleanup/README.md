# ZSH History Cleanup — Analyse & Plan

Dieser Ordner dokumentiert alle bisherigen Versuche, die zsh-History auf macOS zu bereinigen,
erklärt was schiefgelaufen ist, und enthält einen sauberen Plan für die Zukunft.

---

## Schnellstart

```bash
# Repo pullen
cd ~/git/dotfiles-macos && git pull

# Setup (einmalig)
zsh ~/git/dotfiles-macos/scripts-tracker/setup.sh

# History cleanup (interaktiv)
zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh

# Nur anschauen ohne Änderungen
zsh ~/git/dotfiles-macos/history-cleanup/clean-history.sh --dry-run
```

---

## Was wir bisher probiert haben (und was schiefging)

### Versuch 1 — `fc -l` ohne `-n` Flag
```bash
fc -l -10000 > ~/.zsh_history.live
```
**Problem:** `fc -l` gibt Zeilennummern mit aus (z.B. `  987  ssh klanz@...`).  
Diese Nummern wurden direkt in die History-Datei gespeichert.

### Versuch 2 — `fc -ln` + awk
```bash
fc -ln -10000 > ~/.zsh_history.live
LC_ALL=C awk 'NF>0 && length($0)<=150' ~/.zsh_history.live > ~/.zsh_history.clean
mv ~/.zsh_history.clean ~/.zsh_history
rm -rf ~/.zsh_sessions/* && fc -R
```
**Problem:** macOS Session-Dateien (`~/.zsh_sessions/*.historynew`) haben Duplikate nach Neustart
erzeugt, weil sie beim Schließen des Terminals erneut in `~/.zsh_history` eingemischt wurden.

### Root Cause: macOS zsh Session-Management
macOS führt pro Terminal-Fenster eine eigene `~/.zsh_sessions/*.historynew` Datei.  
Beim Schließen wird diese in `~/.zsh_history` gemergt.  
Solange alte Session-Dateien existieren, werden sie beim Reload/Neustart neu eingelesen → Duplikate.

**Lösung:** Alle Session-Dateien nach dem Cleanup löschen.

---

## macOS-Eigenheiten

| Problem | Ursache | Lösung im Script |
|---|---|---|
| Duplikate nach Neustart | `~/.zsh_sessions/*.historynew` | Alle Session-Files nach Cleanup löschen |
| Andere offene Terminals verlieren History | Session-Files noch nicht gespeichert | Hinweis + `fc -W` in anderen Fenstern |
| History-Nummern in Datei | `fc -l` statt `fc -ln` | `fc -ln` verwenden |
| `[200~` Artefakte | Bracket Paste Mode | awk-Filter |
| UTF-8 Corruption | awk ohne `LC_ALL=C` | `LC_ALL=C awk` |
| Cursor-Integration in History | Cursor fügt `shellIntegration-rc.zsh` Source-Befehl ein | awk-Filter |

---

## Script-Übersicht

```
history-cleanup/
├── README.md              ← dieser Plan
├── clean-history.sh       ← Haupt-Script (interaktiv, macOS-aware)
├── find-safe.sh           ← find mit komprimierter Fehlerausgabe
└── .gitignore

scripts-tracker/
├── README.md              ← Scripts Tracker Dokumentation
├── setup.sh               ← Einmaliges Setup (~/scripts/ + ~/bin/)
└── paste-to-script.zsh    ← save-script Funktion für .zshrc
```

---

## clean-history.sh — Was es macht

1. **Zeigt offene Terminal-Sessions** — Hinweis wenn andere Fenster noch unsaved History haben
2. **Merged alle Quellen** — In-Memory + `~/.zsh_sessions/*` + `~/.zsh_history`
3. **Lange Einträge** (>100 Zeichen) interaktiv als Scripts in `~/scripts/` speicherbar
4. **Secret-Erkennung** via Shannon-Entropie + Pattern-Matching
5. **Bereinigung**: Nummern, Artefakte, Duplikate, Cursor-Integration
6. **Schreibt** `~/.zsh_history` + löscht Session-Files
7. **Lädt** History in aktuellen Terminal-Speicher neu

---

## Zukünftige Erweiterungen (TODO)

- [ ] `history-tracker.sh` — automatischer Export + git commit (via `precmd` Hook)
- [ ] Forgejo-Sync für `~/scripts/`
- [ ] Context-Filter: ETSI / local-ai / privat Branches
- [ ] `.zshrc` Hook: `fc -W` vor jedem Terminal-Schließen automatisch
