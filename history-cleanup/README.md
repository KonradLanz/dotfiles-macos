# ZSH History Cleanup — Analyse & Plan

Dieser Ordner dokumentiert alle bisherigen Versuche, die zsh-History auf macOS zu bereinigen, erklärt was schiefgelaufen ist, und enthält einen sauberen Plan für die Zukunft.

---

## Was wir bisher probiert haben (und was schiefging)

### Versuch 1 — `fc -l` ohne `-n` Flag
```bash
fc -l -10000 > ~/.zsh_history.live
```
**Problem:** `fc -l` gibt die Zeilennummern mit aus (z.B. `  987  ssh klanz@...`).  
Diese Nummern wurden direkt in die History-Datei gespeichert — alle Einträge hatten dann eine Nummer am Anfang.

### Versuch 2 — `fc -ln` mit zu großem `-n` Wert
```bash
fc -ln -10000 > ~/.zsh_history.live
LC_ALL=C awk 'NF>0 && length($0)<=150' ~/.zsh_history.live > ~/.zsh_history.clean
mv ~/.zsh_history.clean ~/.zsh_history
rm -rf ~/.zsh_sessions/* 2>/dev/null
fc -R ~/.zsh_history
```
**Problem:** Teils funktioniert, aber:
- Einige History-Blöcke wurden durch macOS Session-Dateien (`~/.zsh_sessions/*.historynew`) dupliziert
- Die History wird beim Schließen des Terminals erneut aus der Session-Datei eingelesen → Duplikate nach Neustart
- Einzelne Zeilen hatten nach dem Reload wieder Nummern am Anfang (von alten Session-Dateien)
- `awk length()` zählt Bytes, nicht Zeichen → Probleme bei UTF-8/Unicode (Umlaute, Emojis)

### Was wir im `cat ~/.zsh_history` sehen
- Zeilen wie `   29  brew install wireguard-tools` → Nummern vom `fc -l` Dump
- Zeilen mit eingebetteten `\n` → mehrere Befehle als eine Zeile gespeichert (macOS zsh speichert Multiline-Commands so)
- Encoding-Artefakte: `GröÃ?e` statt `Größe` → UTF-8 Corruption beim `awk` ohne `LC_ALL=C`
- `[200~` am Anfang einer Zeile → Bracket Paste Mode artefact (Terminal hat Paste-Code nicht gefiltert)
- Wiederholte Blöcke → Mehrfach durch verschiedene Session-Dateien eingelesen

### Root Cause: macOS zsh Session-Management
macOS verwendet `~/.zsh_sessions/` um pro Terminal-Session eine eigene History-Datei zu führen.
Beim Öffnen eines neuen Terminals wird die Session-Datei **zusätzlich** zu `~/.zsh_history` geladen.
Beim Schließen wird die Session-Datei mit `~/.zsh_history` zusammengeführt.
→ Solange alte Session-Dateien existieren, werden sie beim Reload/Neustart neu eingelesen.

---

## Sauberer Plan: History Tracker für zsh (macOS)

### Ziel
- Eine **saubere, deduplizierte** History ohne Passwörter, ohne `\n`-Artefakte, ohne Nummern
- History in einem **lokalen git** versioniert (Forgejo-ready)
- Bewusste Commits mit Kommentaren möglich
- Passwörter/Secrets werden herausgefiltert (ähnlich wie `git-secrets` / `truffleHog`)
- Später: Branching-Strategie für verschiedene Kontexte (ETSI, local-ai, privat)

### Schritt 1 — Einmalige Bereinigung (clean-history.sh)
Siehe `clean-history.sh` in diesem Ordner.

### Schritt 2 — Laufender Tracker (history-tracker.sh)
```
history-cleanup/
├── README.md              ← dieser Plan
├── clean-history.sh       ← einmalige Bereinigung
├── history-tracker.sh     ← regelmäßiger Export + git commit (TODO)
├── filter-secrets.awk     ← Passwort/Secret-Filter (TODO)
└── .gitignore             ← Verhindert echte History-Dateien im Repo
```

### Schritt 3 — Git-Struktur
```
~/history-git/
├── .git/
├── history.log            ← exportierte, bereinigte History
└── sessions/
    ├── etsi.log           ← nach Kontext gefiltert
    ├── local-ai.log
    └── private.log
```

### Schritt 4 — Secret-Filter (Patterns)
Diese Patterns sollten vor dem Commit herausgefiltert werden:
- `--password`, `-p <wert>`, `-P <wert>`
- `export SECRET=`, `export TOKEN=`, `export KEY=`
- `curl ... -u user:pass`
- `Authorization: Bearer ...`
- Private Keys / `-----BEGIN`
- IP-Adressen aus privatem Netz (optional: 192.168.x.x, 10.x.x.x)

### Nächste Schritte
- [ ] `filter-secrets.awk` schreiben
- [ ] `history-tracker.sh` schreiben (cronjob oder shell-hook `precmd`)
- [ ] Forgejo-Repo anlegen + pushen
- [ ] `.zshrc` Hook: `fc -W` vor jedem Commit um aktuelle Session zu sichern
