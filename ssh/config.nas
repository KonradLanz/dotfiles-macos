# ssh/config.nas
#
# NAS SSH-Konfiguration fuer QNAP.
# Einbinden in ~/.ssh/config:
#   cat ~/git/dotfiles-macos/ssh/config.nas >> ~/.ssh/config
#
# QNAP zeigt bei interaktivem Login ein Q/Y-Menue (Shell-Auswahl).
# Mit RequestTTY no wird dieses Menue bei headless/Script-Aufrufen
# uebersprungen. Interaktive Sessions (ssh nas ohne Command) zeigen
# es weiterhin -- das ist QNAP-seitig nicht abschaltbar ohne Root.
#
# SSH-Key-Setup (empfohlen, einmalig):
#   ssh-keygen -t ed25519 -C "koni-mac-nas" -f ~/.ssh/id_nas
#   ssh-copy-id -i ~/.ssh/id_nas.pub admin@nas.ad.own.dedyn.io
#   # Danach: PasswordAuthentication faellt weg

Host nas
    HostName nas.ad.own.dedyn.io
    User admin
    IdentityFile ~/.ssh/id_nas
    IdentitiesOnly yes
    RequestTTY no
    ConnectTimeout 10
    ServerAliveInterval 30
    ServerAliveCountMax 3

# Interaktive Shell (ssh nas-shell)
# QNAP zeigt bei interaktivem Login ein Q/Y-Menue das Shell-Typ abfragt.
# Workaround: /bin/sh direkt aufrufen, QNAP-Login-Script ueberspringen.
# Falls das Menue trotzdem erscheint: 'Q' dann Enter -> bash/sh
Host nas-shell
    HostName nas.ad.own.dedyn.io
    User admin
    IdentityFile ~/.ssh/id_nas
    IdentitiesOnly yes
    RequestTTY yes
    RemoteCommand /bin/sh
    ConnectTimeout 10
