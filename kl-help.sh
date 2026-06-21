#!/bin/sh
# kl-help.sh — Übersicht aller kl/nas/* Befehle und Aliases
#
# Einbinden in ~/.zshrc:
#   alias kl='bash ~/git/dotfiles-macos/kl-help.sh'
#
# Oder direkt aufrufen:
#   bash ~/git/dotfiles-macos/kl-help.sh
#   bash ~/git/dotfiles-macos/kl-help.sh git
#   bash ~/git/dotfiles-macos/kl-help.sh ssh

FILTER="${1:-}"

section() {
    [ -z "$FILTER" ] || [ "$FILTER" = "$1" ] || return 0
    printf '\n\033[1;34m══════════════════════════════════════\033[0m\n'
    printf '\033[1;34m  %s\033[0m\n' "$2"
    printf '\033[1;34m══════════════════════════════════════\033[0m\n'
}

cmd() {
    [ -z "$FILTER" ] || [ "$FILTER" = "$_section" ] || return 0
    printf '  \033[1;32m%-28s\033[0m %s\n' "$1" "$2"
}

sub() {
    [ -z "$FILTER" ] || [ "$FILTER" = "$_section" ] || return 0
    printf '  \033[0;33m  %-26s\033[0m %s\n' "$1" "$2"
}

note() {
    [ -z "$FILTER" ] || [ "$FILTER" = "$_section" ] || return 0
    printf '  \033[0;90m%s\033[0m\n' "$1"
}

printf '\n\033[1;37m kl — Projektübersicht & Befehle\033[0m'
printf '  \033[0;90m(Stand: 2026-06-21)\033[0m\n'
printf '\033[0;90m Filtere mit: kl <section>  z.B. kl git, kl ssh, kl nas, kl cache\033[0m\n'

# ---------------------------------------------------------------------------
_section="git"
section git "GIT — Repos & Remotes"
# ---------------------------------------------------------------------------
cmd "gup [msg]"          "Rebase + push. Optional: commit mit Nachricht zuerst"
cmd "gpull"              "Fetch + rebase origin (kein Merge-Commit)"
cmd "gpush"              "Push aktuellen Branch nach origin"
cmd "nas-setup"          "git remote 'nas' in allen NAS-Repos setzen"
cmd "nas-status"         "Remote-Konfiguration aller Repos anzeigen"
cmd "nas-pull [repo]"    "Alle (oder einen) Repo via SSH vom NAS pullen"
cmd "nas-add <r> <pfad>" "Einzelnen NAS-Remote manuell setzen"
note "Script: ~/git/dotfiles-macos/git/nas-remotes.sh"
note "WICHTIG: Niemals git push/pull auf SMB-Mount -- nur SSH!"

# ---------------------------------------------------------------------------
_section="ssh"
section ssh "SSH — NAS Zugang"
# ---------------------------------------------------------------------------
cmd "ssh nas <befehl>"   "Headless SSH auf NAS (kein Passwort, kein Q/Y-Menü)"
cmd "ssh nas-shell"      "Interaktive Shell auf NAS"
cmd "bash .../nas-ssh-setup.sh" "Einmaliger SSH-Key Setup (Key generieren + deployen)"
note "Config: ~/.ssh/config (eingebunden aus dotfiles-macos/ssh/config.nas)"
note "Key: ~/.ssh/id_nas (ed25519, kein Passwort nötig nach Setup)"
note "Auth-Progression: Passwort → Vaultwarden → SSH-Key → MFA"
note "Doku: github.com/KonradLanz/credential-vault/AUTH-METHODS.md"

# ---------------------------------------------------------------------------
_section="nas"
section nas "NAS — QNAP Verwaltung"
# ---------------------------------------------------------------------------
cmd "nas-pull"            "Alle NAS-Repos pullen (via SSH)"
cmd "ssh nas 'git -C /pfad pull'" "Direkt auf NAS pullen"
note "NAS-Pfad: /share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git/"
note "SMB-Mount nur zum Browsen: /Volumes/home oder ~/git/nw/nas"
note "SMB-Safeguard: nas-pull blockt automatisch wenn SMB-Mount erkannt"

# ---------------------------------------------------------------------------
_section="cache"
section cache "CACHE — .enterHo / kl_read_cached"
# ---------------------------------------------------------------------------
cmd "kl_read_cached"      "Eingabe einmal cachen, danach Enter drücken reicht"
sub "VAR KEY PROMPT DEFAULT SENSITIVITY" ""
sub "sensitivity=plain"   "Sichtbare Eingabe (URLs, Usernamen)"
sub "sensitivity=auto"    "Versteckte Eingabe (Passwort, Token) — read -s"
sub "sensitivity=gpg"     "GPG-verschlüsselt gecacht"
sub "sensitivity=keepassxc" "In KeePassXC-Datenbank gespeichert"
note "Cache-Pfad: ~/.cache/kl-input-cache/<repo-hash>/"
note "Lib: ~/git/bootstrap-foundation/lib/input-cache.sh"
note "WICHTIG: sensitivity!=plain → Terminal zeigt Eingabe NICHT an (read -s)"

# ---------------------------------------------------------------------------
_section="dotai"
section dotai ".ai / dotAI — KI-Kontext"
# ---------------------------------------------------------------------------
cmd "~/git/dotAI/"        "Globales dotAI-Projekt (cross-repo Architektur)"
cmd "<repo>/.ai/"         "Repo-lokaler KI-Kontext"
cmd "<repo>/.ai/timemachine/" "Dated-Folder-Backend (kein git nötig)"
note "Dual-Backend: Dated Folders (immer) + Forgejo/Git (wenn vorhanden)"
note "Dated Folders = Einstieg, Reflexion, Meilenstein-Snapshots"
note "Git-Tags = Meilensteine mit git checkout <tag>"

# ---------------------------------------------------------------------------
_section="auth"
section auth "AUTH — Credential Backends"
# ---------------------------------------------------------------------------
cmd "bw login"            "Vaultwarden/Bitwarden CLI einloggen"
cmd "bw get password <n>" "Passwort aus Vault holen"
cmd "bw unlock"           "Vault entsperren (Session-Token)"
cmd "keepassxc-cli"       "KeePassXC CLI (lokal, offline)"
note "Doku: github.com/KonradLanz/credential-vault/AUTH-METHODS.md"
note "Progression: Passwort → Vaultwarden → SSH-Key → SSH+Agent → MFA"
note "Backends: github.com/KonradLanz/bootstrap-foundation/CREDENTIAL-BACKENDS.md"

# ---------------------------------------------------------------------------
_section="repos"
section repos "REPOS — Übersicht ~/git/"
# ---------------------------------------------------------------------------
cmd "bootstrap-foundation" "Core-Scripts: lib/, services/, kl_read_cached"
cmd "dotfiles-macos"       "macOS-Config: SSH, git-Aliases, NAS-Remotes"
cmd "dotAI"                "Globaler KI-Kontext (cross-repo)"
cmd "credential-vault"     "Auth-Methoden, Hygiene, Rotation, Recovery"
cmd "local-ai-stack"       "Lokaler AI-Stack (Ollama etc.)"
cmd "paperless-qnap"       "Paperless-NGX auf QNAP"
cmd "dotfiles"             "Allgemeine Dotfiles"
cmd "hotkey-asr-assistant" "Hotkey + Speech-Recognition Overlay"

# ---------------------------------------------------------------------------
_section="meta"
section meta "META — Dieses Hilfesystem"
# ---------------------------------------------------------------------------
cmd "kl"                  "Diese Übersicht anzeigen"
cmd "kl git"              "Nur Git-Befehle"
cmd "kl ssh"              "Nur SSH-Befehle"
cmd "kl nas"              "Nur NAS-Befehle"
cmd "kl cache"            "Nur Cache-Befehle"
cmd "kl auth"             "Nur Auth/Credential-Befehle"
cmd "kl repos"            "Repo-Übersicht"
note "Script: ~/git/dotfiles-macos/kl-help.sh"
note "Alias 'kl' in ~/.zshrc eintragen:"
note "  alias kl='bash ~/git/dotfiles-macos/kl-help.sh'"

printf '\n'
