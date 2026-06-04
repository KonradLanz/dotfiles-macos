# Scripts Tracker

Lokal-git-getrackter Ordner für "mal eben" Scripts — alles was zu lang ist für die History.

---

## Konzept

Der Standardordner für schnell gemachte Scripts auf macOS ist `~/bin/` oder `~/scripts/`.
Wir verwenden **`~/scripts/`** weil:
- `~/bin/` ist traditionell für fertige Binaries/Tools (wird auch im `$PATH` ergänzt)
- `~/scripts/` ist klar als Work-in-Progress erkennbar
- Passend zum Pattern von brew-tracker, dotfiles-tracker etc.

Die Scripts bekommen Datumsprefixe: `20260604_clean_history_tryout.sh`

---

## Ordnerstruktur

```
~/scripts/
├── .git/                    ← lokales git (kein Remote nötig, Forgejo optional)
├── .gitignore
├── 20260604_clean_history_tryout.sh
├── 20260604_wireguard_check.sh
└── 20260610_etsi_pdf_rename.sh
```

---

## Setup

Einmalig:
```bash
~/git/dotfiles-macos/scripts-tracker/setup.sh
```

Dann in `~/.zshrc` einbinden:
```bash
source ~/git/dotfiles-macos/scripts-tracker/paste-to-script.zsh
```

---

## paste-to-script — Was es macht

### Option A: Manuell (immer verfügbar)
```bash
save-script         # fragt nach Namen, öffnet Editor
save-script mein-script   # direkt mit Name
```

### Option B: Automatisch beim History-Cleanup
Beim nächsten `clean-history.sh` Lauf werden lange Einträge (>150 Zeichen)  
aufgelistet und du kannst sie einzeln als Script speichern.

### Option C: ZSH Bracket Paste Hook (experimentell)
Wenn `PASTE_TO_SCRIPT_HOOK=1` in `~/.zshrc` gesetzt ist,  
wird beim Einfügen von mehr als 3 Zeilen automatisch gefragt ob du es als Script speichern willst.

**Achtung:** Der Paste-Hook funktioniert nur im interaktiven Terminal, nicht in Cursor/IDE Terminals.

---

## Namenskonvention

```
YYYYMMDD_kurzbeschreibung_kontext.sh

20260604_clean_history_tryout.sh     ← einmalige Bereinigung
20260604_wireguard_debug.sh          ← Netz-Debug
20260610_etsi_pdf_batch_rename.sh    ← ETSI-Arbeit
20260615_k8s_cluster_reset.sh        ← Cluster
```

---

## Git Workflow

```bash
# Manueller Commit
cd ~/scripts && git add -A && git commit -m "Add YYYYMMDD_name.sh"

# Optional: zu Forgejo pushen
git remote add origin http://192.168.1.201:3000/koni/scripts.git
git push -u origin main
```
