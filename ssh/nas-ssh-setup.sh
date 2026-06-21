#!/bin/sh
# ssh/nas-ssh-setup.sh
#
# Einmaliger Setup fuer passwortlose SSH-Verbindung zum QNAP NAS.
#
# Was dieses Script tut:
#   1. SSH-Key generieren (ed25519, sicher, klein)
#   2. Key auf NAS deployen via ssh-copy-id (einmalig Passwort noetig)
#   3. ~/.ssh/config aus config.nas einbinden
#   4. SSH-Passwort in .enterHo-Cache (via kl_read_cached) speichern
#      damit das Passwort bei Bedarf (Vaultwarden-Sync etc.) verfuegbar ist
#   5. Vorschlag: SSH-Keys auf weiteren Plattformen einrichten
#
# Nach dem Setup: ssh nas <befehl> -- ohne Passwort, ohne Q/Y-Menue

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Bootstrap-Foundation fuer kl_read_cached
# ---------------------------------------------------------------------------
BOOTSTRAP_ROOT=""
for candidate in \
    "$HOME/git/bootstrap-foundation" \
    "${KL_BOOTSTRAP_ROOT:-__unset__}"
do
    [ -f "$candidate/lib/input-cache.sh" ] && BOOTSTRAP_ROOT="$candidate" && break
done

HAS_CACHE=0
if [ -n "$BOOTSTRAP_ROOT" ]; then
    # shellcheck source=/dev/null
    . "$BOOTSTRAP_ROOT/lib/input-cache.sh"
    HAS_CACHE=1
fi

ask_cached() {
    local var="$1" key="$2" prompt="$3" default="${4:-}" sensitivity="${5:-plain}"
    if [ "$HAS_CACHE" = "1" ]; then
        kl_read_cached "$var" "$key" "$prompt" "$default" "$sensitivity"
    else
        printf '%s' "$prompt" >&2
        [ -n "$default" ] && printf ' [%s]' "$default" >&2
        printf ': ' >&2
        read -r _reply
        eval "$var=\"${_reply:-$default}\""
    fi
}

# ---------------------------------------------------------------------------
# 1. NAS-Verbindungsdaten (gecacht via .enterHo)
# ---------------------------------------------------------------------------
echo
echo "=== NAS SSH Setup ==="
echo

ask_cached NAS_HOST  'nas/host'     'NAS Hostname'     'nas.ad.own.dedyn.io' plain
ask_cached NAS_USER  'nas/user'     'NAS SSH User'     'admin'               plain
ask_cached NAS_GIT_ROOT 'nas/git_root' 'NAS git-Root-Pfad' \
    '/share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git' plain

# SSH-Passwort: sensitiv, im KeePass/GPG-Backend cachen
# Beim naechsten Mal wird es aus dem Cache geholt -- kein erneutes Eintippen
ask_cached NAS_PASS  'nas/ssh_pass' 'NAS SSH Passwort (wird sicher gecacht)' '' auto

# ---------------------------------------------------------------------------
# 2. SSH-Key generieren (falls noch nicht vorhanden)
# ---------------------------------------------------------------------------
SSH_KEY="$HOME/.ssh/id_nas"
if [ ! -f "$SSH_KEY" ]; then
    echo
    echo "--- SSH-Key generieren ---"
    ssh-keygen -t ed25519 -C "koni-mac-$(hostname -s)-nas" -f "$SSH_KEY" -N ''
    echo "Key erstellt: $SSH_KEY"
else
    echo "SSH-Key bereits vorhanden: $SSH_KEY -- wird wiederverwendet"
fi

# ---------------------------------------------------------------------------
# 3. Key auf NAS deployen
# ---------------------------------------------------------------------------
echo
echo "--- Key auf NAS deployen ---"
echo "(Einmalig: NAS-Passwort wird benoetigt)"

# ssh-copy-id unterstuetzt kein Passwort via stdin sauber --
# sshpass ist die sauberste Loesung, Fallback: manuell
if command -v sshpass >/dev/null 2>&1 && [ -n "$NAS_PASS" ]; then
    sshpass -p "$NAS_PASS" ssh-copy-id \
        -i "${SSH_KEY}.pub" \
        -o StrictHostKeyChecking=accept-new \
        "${NAS_USER}@${NAS_HOST}"
    echo "Key deployed via sshpass."
else
    echo
    echo "sshpass nicht verfuegbar oder kein Passwort gecacht."
    echo "Manuell ausfuehren:"
    echo
    echo "  ssh-copy-id -i ${SSH_KEY}.pub ${NAS_USER}@${NAS_HOST}"
    echo
    printf 'Jetzt manuell ausfuehren? [J/n] '
    read -r answer
    case "${answer:-J}" in
        j|J|y|Y)
            ssh-copy-id -i "${SSH_KEY}.pub" "${NAS_USER}@${NAS_HOST}" || true
            ;;
        *)
            echo "Uebersprungen -- fuehre ssh-copy-id spaeter manuell aus."
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 4. ~/.ssh/config einbinden
# ---------------------------------------------------------------------------
echo
echo "--- ~/.ssh/config aktualisieren ---"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

SSH_CONFIG="$HOME/.ssh/config"
NAS_CONFIG_MARKER="# BEGIN nas (dotfiles-macos)"

if grep -q "$NAS_CONFIG_MARKER" "$SSH_CONFIG" 2>/dev/null; then
    echo "NAS-Config bereits in ~/.ssh/config eingetragen -- uebersprungen."
else
    {
        printf '\n%s\n' "$NAS_CONFIG_MARKER"
        # NAS_HOST aus Cache einsetzen
        sed "s/nas.ad.own.dedyn.io/$NAS_HOST/g; s/User admin/User $NAS_USER/g" \
            "$DOTFILES_ROOT/ssh/config.nas" | grep -v '^#'
        printf '# END nas (dotfiles-macos)\n'
    } >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "NAS-Config in ~/.ssh/config eingetragen."
fi

# ---------------------------------------------------------------------------
# 5. Verbindung testen
# ---------------------------------------------------------------------------
echo
echo "--- Verbindung testen ---"
if ssh -o BatchMode=yes -o ConnectTimeout=5 nas 'echo OK' 2>/dev/null; then
    echo "Verbindung erfolgreich -- passwortloser SSH-Zugang aktiv."
    KEY_WORKS=1
else
    echo "Verbindung fehlgeschlagen oder Passwort noch benoetigt."
    KEY_WORKS=0
fi

# ---------------------------------------------------------------------------
# 6. SSH-Key Plattform-Vorschlag
# ---------------------------------------------------------------------------
if [ "$KEY_WORKS" = "1" ]; then
    echo
    echo "========================================"
    echo " SSH-Key Plattform-Vorschlag"
    echo "========================================"
    echo
    echo " Derselbe SSH-Key (oder ein neuer) kann auf weiteren Plattformen"
    echo " eingerichtet werden:"
    echo
    echo "  GitHub:"
    echo "    gh ssh-key add ~/.ssh/id_nas.pub --title 'koni-mac-nas'"
    echo "    # oder: Settings -> SSH Keys"
    echo
    echo "  Forgejo (lokal):"
    echo "    curl -X POST http://localhost:3000/api/v1/user/keys \\"
    echo "      -H 'Authorization: token <dein-token>' \\"
    echo "      -d '{\"key\": \"'\$(cat ~/.ssh/id_nas.pub)'\", \"title\": \"mac\"}'"
    echo
    echo "  Weitere NAS-User / Maschinen:"
    echo "    ssh-copy-id -i ~/.ssh/id_nas.pub user@host"
    echo
    echo " Tipp: Ein Key pro Geraet (nicht pro Dienst) ist das sicherere Muster."
    echo "       Bei Geraeteverlust nur diesen einen Key widerrufen."
    echo "========================================"
fi

echo
echo "Setup abgeschlossen."
echo "Nutze ab jetzt: ssh nas <befehl>  (kein Passwort, kein Q/Y-Menue)"
echo "Fuer interaktive Shell: ssh nas-shell"
