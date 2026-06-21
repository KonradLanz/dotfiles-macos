#!/bin/sh
# nas-console-mgmt.sh
#
# Steuert QNAP qts-console-mgmt (das Q/Y-Login-Menue fuer admin).
#
# Normalzustand: AUTO LAUNCH = FALSE
#   -> ssh nas-shell startet direkt bash, kein Menue
#
# Notfall/Reboot: AUTO LAUNCH = TRUE
#   -> QNAP-Konsolen-Menue verfuegbar (serielle Konsole, HDMI)
#   -> Nach Notfall wieder deaktivieren!
#
# Verwendung:
#   bash ssh/nas-console-mgmt.sh status    # aktuellen Status anzeigen
#   bash ssh/nas-console-mgmt.sh disable   # fuer SSH-Betrieb (Normalfall)
#   bash ssh/nas-console-mgmt.sh enable    # fuer Notfall/Wartung
#   bash ssh/nas-console-mgmt.sh reboot-safe  # nach Reboot: einmalig ein, dann aus

NAS_HOST="${NAS_HOST:-nas.ad.own.dedyn.io}"
NAS_USER="${NAS_USER:-admin}"
CFG_FILE="/etc/config/uLinux.conf"
CFG_SECTION="Console Mgmt"
CFG_KEY="Auto Launch"

action="${1:-status}"

_nas_ssh() {
    # stdout bleibt offen (Caller entscheidet ob er captured)
    # stderr -> /dev/null damit SSH-Verbindungsmeldungen nicht stoeren
    ssh -i ~/.ssh/id_nas -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no \
        -o LogLevel=QUIET \
        -o ConnectTimeout=10 \
        "${NAS_USER}@${NAS_HOST}" "$@"
}

_get_status() {
    # Nur stdout captured, stderr via LogLevel=QUIET unterdrueckt
    _nas_ssh "/sbin/getcfg -f '$CFG_FILE' '$CFG_SECTION' '$CFG_KEY'"
}

_set_status() {
    # setcfg gibt nichts auf stdout aus -- wir zeigen NAS-stderr trotzdem
    _nas_ssh "/sbin/setcfg -f '$CFG_FILE' '$CFG_SECTION' '$CFG_KEY' '$1' && echo 'setcfg OK'"
}

case "$action" in
    status)
        current=$(_get_status)
        printf '\nQNAP Console Mgmt Auto Launch: %s\n' "$current"
        if [ "$current" = "TRUE" ]; then
            printf '  -> Q/Y-Menue aktiv bei naechstem Login-Shell-Start\n'
            printf '  -> Fuer SSH-Normalbetrieb: bash ssh/nas-console-mgmt.sh disable\n'
        else
            printf '  -> SSH nas-shell startet direkt bash (Normalfall)\n'
            printf '  -> Fuer Notfall-Zugang: bash ssh/nas-console-mgmt.sh enable\n'
        fi
        printf '\n'
        ;;

    disable)
        printf 'Deaktiviere QNAP Console Mgmt Auto Launch...\n'
        _set_status FALSE
        current=$(_get_status)
        if [ "$current" = "FALSE" ]; then
            printf 'OK -- ssh nas-shell startet jetzt direkt bash.\n'
        else
            printf 'FEHLER -- Status: %s\n' "$current" >&2
            exit 1
        fi
        ;;

    enable)
        printf 'Aktiviere QNAP Console Mgmt Auto Launch (Notfall-Modus)...\n'
        _set_status TRUE
        current=$(_get_status)
        if [ "$current" = "TRUE" ]; then
            printf 'OK -- Q/Y-Menue aktiv.\n'
            printf '\n'
            printf 'WICHTIG: Nach Wartung zuruecksetzen:\n'
            printf '  bash ssh/nas-console-mgmt.sh disable\n'
            printf '\n'
        else
            printf 'FEHLER -- Status: %s\n' "$current" >&2
            exit 1
        fi
        ;;

    reboot-safe)
        # Setzt Auto Launch vor Reboot auf TRUE (Notfall-Zugang)
        # und plant nach dem Reboot automatisches Deaktivieren via rc.local.
        printf 'Reboot-Safe Modus: Auto Launch wird EINMALIG aktiviert.\n'
        printf 'Nach Reboot: automatisch wieder deaktiviert (via /etc/rc.local).\n\n'

        # Schritt 1: TRUE setzen
        _set_status TRUE
        printf 'Auto Launch = TRUE (aktiv fuer den Reboot)\n'

        # Schritt 2: Einmaligen Deaktivierungs-Eintrag in rc.local schreiben
        # QNAP fuehrt /etc/rc.local nach jedem Boot aus
        _nas_ssh "grep -q 'nas-console-mgmt-disable' /etc/rc.local 2>/dev/null || \
            printf '\n# nas-console-mgmt-disable (einmalig nach Reboot)\n/sbin/setcfg -f /etc/config/uLinux.conf \"Console Mgmt\" \"Auto Launch\" FALSE\n' >> /etc/rc.local"
        printf 'rc.local: Deaktivierungs-Eintrag gesetzt.\n'
        printf '\nJetzt rebooten:\n'
        printf '  ssh nas \'reboot\'\n'
        printf '\nNach Reboot: Auto Launch automatisch FALSE -- ssh nas-shell direkt bash.\n'
        ;;

    *)
        printf 'Verwendung: %s [status|disable|enable|reboot-safe]\n' "$0" >&2
        exit 1
        ;;
esac
