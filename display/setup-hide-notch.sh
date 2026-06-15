#!/usr/bin/env zsh
# =============================================================================
# setup-hide-notch.sh
# =============================================================================
# WAS DIESES SCRIPT TUT:
#   Malt einen schwarzen Balken über den Notch-Bereich des Wallpapers,
#   sodass der Notch optisch "verschwindet". Der Balken wird in eine
#   temporäre PNG-Kopie des Wallpapers gezeichnet – das Original bleibt
#   IMMER erhalten. Ein LaunchAgent sorgt dafür, dass der Effekt nach
#   jedem Login automatisch aktiv ist.
#
# WAS DIESES SCRIPT NICHT TUT:
#   - Das Original-Wallpaper wird NIE verändert oder gelöscht
#   - System-Dateien werden nicht angefasst
#
# BACKUPS:
#   Jedes Mal wenn das Script läuft, wird das aktuelle Wallpaper
#   (vor der Änderung) gesichert nach:
#     ~/Library/Application Support/hide-notch/backups/
#   Format: wallpaper_YYYY-MM-DD_HH-MM-SS_<originalname>.backup
#   Die letzten 10 Backups werden behalten, ältere automatisch gelöscht.
#
# RÜCKGÄNGIG MACHEN (alles entfernen):
#   ./setup-hide-notch.sh --uninstall
#   Das stellt das Original-Wallpaper wieder her, entfernt den
#   LaunchAgent und löscht die temporären Dateien.
#
# MANUELL TESTEN (ohne LaunchAgent):
#   swift display/notch-black.swift
#   Mit Ctrl+C wird das Original-Wallpaper automatisch wiederhergestellt.
# =============================================================================

set -euo pipefail

# --- Konfiguration -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWIFT_SCRIPT="$SCRIPT_DIR/notch-black.swift"
LAUNCH_AGENT_LABEL="com.koni.hide-notch"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_LABEL}.plist"
BACKUP_DIR="$HOME/Library/Application Support/hide-notch/backups"
TEMP_WALLPAPER="/tmp/notch-wallpaper.png"
LOG_FILE="/tmp/hide-notch.log"
ERR_FILE="/tmp/hide-notch.err"

# --- Farben für Output -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}→${NC} $*" }
success() { echo -e "${GREEN}✓${NC} $*" }
warn()    { echo -e "${YELLOW}⚠${NC} $*" }
error()   { echo -e "${RED}✗${NC} $*" >&2 }
header()  { echo -e "\n${BOLD}$*${NC}" }

# --- Uninstall ---------------------------------------------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
    header "=== hide-notch entfernen ==="
    echo ""
    warn "Dieses Script wird:"
    echo "  1. Den LaunchAgent stoppen und entfernen"
    echo "  2. Das Original-Wallpaper wiederherstellen"
    echo "  3. Die temporäre PNG-Datei löschen"
    echo "  4. Backups BLEIBEN erhalten in: $BACKUP_DIR"
    echo ""
    read "CONFIRM?Fortfahren? [j/N] "
    [[ "$CONFIRM" != [jJyY] ]] && { info "Abgebrochen."; exit 0; }

    # LaunchAgent stoppen
    if launchctl list | grep -q "$LAUNCH_AGENT_LABEL" 2>/dev/null; then
        info "LaunchAgent stoppen..."
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        success "LaunchAgent gestoppt"
    else
        info "LaunchAgent war nicht aktiv"
    fi

    # Plist löschen
    if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
        rm "$LAUNCH_AGENT_PLIST"
        success "LaunchAgent-Plist gelöscht: $LAUNCH_AGENT_PLIST"
    fi

    # Laufendes Swift-Script killen (löst intern restoreWallpaper() aus)
    if pgrep -f "notch-black.swift" > /dev/null 2>&1; then
        info "Notch-Script stoppen (stellt Wallpaper automatisch wieder her)..."
        pkill -TERM -f "notch-black.swift" || true
        sleep 2
    fi

    # Falls das Script das Wallpaper nicht selbst zurückgesetzt hat:
    # Neuestes Backup wiederherstellen
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.backup 2>/dev/null | head -1 || echo "")
    if [[ -n "$LATEST_BACKUP" ]]; then
        ORIGINAL_PATH=$(cat "${LATEST_BACKUP}.path" 2>/dev/null || echo "")
        if [[ -n "$ORIGINAL_PATH" && -f "$LATEST_BACKUP" ]]; then
            info "Stelle Original-Wallpaper wieder her aus Backup..."
            # Wallpaper via osascript setzen
            osascript -e "tell application \"System Events\" to set picture of desktop 1 to \"$ORIGINAL_PATH\"" 2>/dev/null || \
                cp "$LATEST_BACKUP" "$ORIGINAL_PATH"
            success "Wallpaper wiederhergestellt: $ORIGINAL_PATH"
        fi
    fi

    # Temp-PNG löschen
    [[ -f "$TEMP_WALLPAPER" ]] && rm "$TEMP_WALLPAPER" && success "Temp-PNG gelöscht"
    [[ -f "$LOG_FILE" ]] && rm "$LOG_FILE"
    [[ -f "$ERR_FILE" ]] && rm "$ERR_FILE"

    echo ""
    success "hide-notch vollständig entfernt."
    warn "Deine Backups sind noch unter: $BACKUP_DIR"
    info  "Zum Löschen: rm -rf \"$BACKUP_DIR\""
    exit 0
fi

# --- Install -----------------------------------------------------------------
header "=== hide-notch installieren ==="
echo ""
info "Was passiert:"
echo "  1. Backup des aktuellen Wallpapers → $BACKUP_DIR"
echo "  2. LaunchAgent anlegen → $LAUNCH_AGENT_PLIST"
echo "  3. LaunchAgent sofort starten"
echo "  4. notch-black.swift läuft im Hintergrund und setzt das modifizierte Wallpaper"
echo ""
info "Zum Rückgängigmachen: ./setup-hide-notch.sh --uninstall"
echo ""

# Swift-Script prüfen
if [[ ! -f "$SWIFT_SCRIPT" ]]; then
    error "Nicht gefunden: $SWIFT_SCRIPT"
    error "Bitte zuerst: cd in das dotfiles-macos Verzeichnis"
    exit 1
fi

# Backup-Verzeichnis anlegen
mkdir -p "$BACKUP_DIR"
success "Backup-Verzeichnis: $BACKUP_DIR"

# Aktuelles Wallpaper sichern
CURRENT_WALLPAPER=$(osascript -e 'tell application "Finder" to get POSIX path of (get desktop picture as alias)' 2>/dev/null || echo "")
if [[ -n "$CURRENT_WALLPAPER" && -f "$CURRENT_WALLPAPER" ]]; then
    TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
    BASENAME=$(basename "$CURRENT_WALLPAPER")
    BACKUP_FILE="$BACKUP_DIR/wallpaper_${TIMESTAMP}_${BASENAME}.backup"
    cp "$CURRENT_WALLPAPER" "$BACKUP_FILE"
    echo "$CURRENT_WALLPAPER" > "${BACKUP_FILE}.path"
    success "Wallpaper gesichert: $BACKUP_FILE"
    info  "Originalpfad gespeichert: ${BACKUP_FILE}.path"

    # Maximal 10 Backups behalten
    BACKUP_COUNT=$(ls "$BACKUP_DIR"/*.backup 2>/dev/null | wc -l | tr -d ' ')
    if (( BACKUP_COUNT > 10 )); then
        info "Bereinige alte Backups (behalte 10 neueste)..."
        ls -t "$BACKUP_DIR"/*.backup | tail -n +11 | xargs -I{} sh -c 'rm "{}" "{}" .path 2>/dev/null || true'
        success "Alte Backups bereinigt"
    fi
else
    warn "Kein aktuelles Wallpaper gefunden – kein Backup erstellt"
fi

# Laufende Instanz beenden
if pgrep -f "notch-black.swift" > /dev/null 2>&1; then
    info "Alte Instanz beenden..."
    pkill -TERM -f "notch-black.swift" || true
    sleep 1
fi

# LaunchAgent Plist schreiben
info "LaunchAgent anlegen: $LAUNCH_AGENT_PLIST"
mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"
cat > "$LAUNCH_AGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LAUNCH_AGENT_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/swift</string>
        <string>${SWIFT_SCRIPT}</string>
    </array>

    <!-- Startet automatisch beim Login -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Neustart falls der Prozess abstürzt -->
    <key>KeepAlive</key>
    <true/>

    <!-- Logs: tail -f /tmp/hide-notch.log -->
    <key>StandardOutPath</key>
    <string>${LOG_FILE}</string>
    <key>StandardErrorPath</key>
    <string>${ERR_FILE}</string>

    <!-- Benötigt Zugriff auf Display / NSScreen -->
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF
success "LaunchAgent-Plist geschrieben"

# LaunchAgent laden (neu laden falls schon vorhanden)
if launchctl list | grep -q "$LAUNCH_AGENT_LABEL" 2>/dev/null; then
    info "LaunchAgent neu laden..."
    launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
fi
launchctl load "$LAUNCH_AGENT_PLIST"
success "LaunchAgent geladen und gestartet"

echo ""
header "=== Fertig ==="
echo ""
info "Logs:    tail -f $LOG_FILE"
info "Fehler:  tail -f $ERR_FILE"
info "Status:  launchctl list | grep hide-notch"
info "Entfernen: ./setup-hide-notch.sh --uninstall"
echo ""
warn "Backups (nie automatisch gelöscht außer >10 Stück):"
ls -lh "$BACKUP_DIR"/*.backup 2>/dev/null || info "(noch keine Backups)"
echo ""
