#!/bin/sh
# git/nas-remotes.sh
#
# Verwaltet git-Remotes fuer Repos die auf dem QNAP NAS liegen.
#
# Philosophie:
#   READ  (pull/fetch) --> immer via SSH (sauber, kein Lock-Risiko)
#   WRITE (push)       --> immer via SSH
#   BROWSE             --> SMB-Mount ist okay (Finder, VSCode, etc.)
#
# Niemals git push/pull auf einem SMB-gemounteten .git/ -- Advisory Locks
# und SMB-Datei-Sperren kollidieren und koennen .git/ korrumpieren.
#
# Usage:
#   bash git/nas-remotes.sh setup           # Remotes in allen bekannten Repos setzen
#   bash git/nas-remotes.sh status          # Zeigt Remote-Status aller Repos
#   bash git/nas-remotes.sh pull            # Pullt alle Repos mit 'nas'-Remote
#   bash git/nas-remotes.sh pull <repo>     # Pullt nur einen Repo
#   bash git/nas-remotes.sh add <repo> <remote-path>  # Einzelnen Remote setzen

set -eu

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
NAS_HOST="nas.ad.own.dedyn.io"
NAS_USER="admin"
NAS_GIT_ROOT="/share/CE_CACHEDEV4_DATA/homes/DOMAIN=AD/koni/git"
LOCAL_GIT_ROOT="$HOME/git"
REMOTE_NAME="nas"

# Repos die auf dem NAS existieren (Name = Verzeichnisname auf beiden Seiten)
# Format: "local-name:nas-name" oder einfach "name" wenn identisch
NAS_REPOS="
  nw
  bootstrap-foundation
  dotfiles-macos
  local-ai-stack
  paperless-qnap
"
# Repos nur lokal (kein NAS-Remote erwuenscht):
# dotAI, brew-tracker, contributions-analyser, email-analyser, eudi-nexus
# -> die haben keinen Forgejo/NAS-Counterpart

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
nas_ssh_url() {
    local repo_name="$1"
    printf 'ssh://%s@%s%s/%s' "$NAS_USER" "$NAS_HOST" "$NAS_GIT_ROOT" "$repo_name"
}

has_remote() {
    local repo_dir="$1" remote="$2"
    git -C "$repo_dir" remote get-url "$remote" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# setup: Remotes in allen bekannten Repos setzen
# ---------------------------------------------------------------------------
cmd_setup() {
    echo "=== NAS Remote Setup ==="
    echo "Host: $NAS_USER@$NAS_HOST"
    echo "Remote name: '$REMOTE_NAME'"
    echo
    for entry in $NAS_REPOS; do
        local_name="${entry%%:*}"
        nas_name="${entry##*:}"
        repo_dir="$LOCAL_GIT_ROOT/$local_name"

        if [ ! -d "$repo_dir/.git" ]; then
            echo "  SKIP $local_name (kein lokales git-Repo gefunden)"
            continue
        fi

        url="$(nas_ssh_url "$nas_name")"

        if has_remote "$repo_dir" "$REMOTE_NAME"; then
            existing=$(git -C "$repo_dir" remote get-url "$REMOTE_NAME")
            if [ "$existing" = "$url" ]; then
                echo "  OK   $local_name -> $url"
            else
                git -C "$repo_dir" remote set-url "$REMOTE_NAME" "$url"
                echo "  UPD  $local_name -> $url (war: $existing)"
            fi
        else
            git -C "$repo_dir" remote add "$REMOTE_NAME" "$url"
            echo "  ADD  $local_name -> $url"
        fi
    done
    echo
    echo "Fertig. Teste mit: bash git/nas-remotes.sh status"
}

# ---------------------------------------------------------------------------
# status: Zeigt Remote-Konfiguration und Erreichbarkeit
# ---------------------------------------------------------------------------
cmd_status() {
    echo "=== NAS Remote Status ==="
    for entry in $NAS_REPOS; do
        local_name="${entry%%:*}"
        repo_dir="$LOCAL_GIT_ROOT/$local_name"
        [ -d "$repo_dir/.git" ] || continue

        if has_remote "$repo_dir" "$REMOTE_NAME"; then
            url=$(git -C "$repo_dir" remote get-url "$REMOTE_NAME")
            branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo '?')
            printf '  %-30s [%s] %s\n' "$local_name ($branch)" "$REMOTE_NAME" "$url"
        else
            printf '  %-30s [kein %s-Remote]\n' "$local_name" "$REMOTE_NAME"
        fi
    done
}

# ---------------------------------------------------------------------------
# pull: Alle Repos (oder einen) via SSH vom NAS pullen
# ---------------------------------------------------------------------------
cmd_pull() {
    target="${1:-}"
    echo "=== NAS Pull (via SSH) ==="
    for entry in $NAS_REPOS; do
        local_name="${entry%%:*}"
        repo_dir="$LOCAL_GIT_ROOT/$local_name"

        [ -z "$target" ] || [ "$local_name" = "$target" ] || continue
        [ -d "$repo_dir/.git" ] || continue
        has_remote "$repo_dir" "$REMOTE_NAME" || continue

        branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null || echo 'main')
        echo "  === $local_name ($branch) ==="
        git -C "$repo_dir" fetch "$REMOTE_NAME" -q 2>&1 && \
        git -C "$repo_dir" pull --ff-only "$REMOTE_NAME" "$branch" 2>&1 || \
        echo "  WARN: ff-only fehlgeschlagen -- manuell mergen noetig"
    done
}

# ---------------------------------------------------------------------------
# add: Einzelnen Remote manuell setzen
# ---------------------------------------------------------------------------
cmd_add() {
    local_name="${1:-}"
    remote_path="${2:-}"
    if [ -z "$local_name" ] || [ -z "$remote_path" ]; then
        echo "Usage: $0 add <local-repo-name> <nas-path>"
        echo "Beispiel: $0 add mein-repo /share/CE_.../koni/git/mein-repo"
        exit 1
    fi
    repo_dir="$LOCAL_GIT_ROOT/$local_name"
    url="ssh://${NAS_USER}@${NAS_HOST}${remote_path}"
    git -C "$repo_dir" remote add "$REMOTE_NAME" "$url" 2>/dev/null || \
    git -C "$repo_dir" remote set-url "$REMOTE_NAME" "$url"
    echo "Remote '$REMOTE_NAME' gesetzt: $url"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
    setup)  cmd_setup "$@" ;;
    status) cmd_status "$@" ;;
    pull)   cmd_pull "$@" ;;
    add)    cmd_add "$@" ;;
    *)
        echo "Usage: $0 {setup|status|pull [repo]|add <repo> <path>}"
        echo
        echo "  setup   -- Remotes in allen bekannten NAS-Repos setzen"
        echo "  status  -- Zeigt Remote-Konfiguration"
        echo "  pull    -- Pullt alle/einen Repo via SSH vom NAS"
        echo "  add     -- Einzelnen Remote setzen"
        echo
        echo "WICHTIG: Nur SSH fuer git-Operationen verwenden."
        echo "         SMB-Mount ist nur zum Browsen geeignet."
        ;;
esac
