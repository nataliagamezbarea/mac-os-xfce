#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

aplicaciones_appmenu() {
    step "AppMenu + StatusNotifier"
    if apt-cache show xfce4-appmenu-plugin &>/dev/null; then
        apt_silencioso install xfce4-appmenu-plugin
        info "AppMenu instalado desde apt"
    else
        warn "Descargando AppMenu desde GitHub..."
        local appmenu_deb="/tmp/appmenu_$$.deb"
        curl -sS -L --retry 3 --max-time 60 -o "$appmenu_deb" \
            "https://github.com/lxde/xfce4-appmenu-plugin/releases/download/v0.8.0/xfce4-appmenu-plugin_0.8.0_amd64.deb"
        local tamano
        tamano=$(stat -c%s "$appmenu_deb" 2>/dev/null || echo 0)
        if [ "$tamano" -gt 10240 ]; then
            apt_silencioso install "$appmenu_deb"
            info "AppMenu instalado desde .deb"
        else
            warn "El .deb está corrupto — se omite AppMenu"
        fi
        rm -f "$appmenu_deb"
    fi
    info "AppMenu + StatusNotifier listos"
}

aplicaciones_ulauncher() {
    step "Instalando Ulauncher"
    cd ~
    local ok=false
    if ! command -v ulauncher &>/dev/null; then
        if add-apt-repository -y ppa:agornostal/ulauncher 2>/dev/null; then
            apt_silencioso update
            apt_silencioso install ulauncher && ok=true
            info "Ulauncher instalado desde PPA"
        fi
    fi
    if ! $ok && ! command -v ulauncher &>/dev/null; then
        warn "PPA no disponible — descargando .deb..."
        local version
        version=$(curl -s https://api.github.com/repos/Ulauncher/Ulauncher/releases/latest | grep '"tag_name"' | cut -d\" -f4)
        [ -z "$version" ] && version="5.15.7"
        curl -sS -L --retry 3 --max-time 60 -o /tmp/ulauncher.deb \
            "https://github.com/Ulauncher/Ulauncher/releases/download/${version}/ulauncher_${version}_all.deb"
        local tamano
        tamano=$(stat -c%s /tmp/ulauncher.deb 2>/dev/null || echo 0)
        if [ "$tamano" -gt 10240 ]; then
            apt_silencioso install /tmp/ulauncher.deb && ok=true
            info "Ulauncher ${version} instalado desde .deb"
        else
            warn "No se pudo descargar Ulauncher"
        fi
    fi
    if command -v ulauncher &>/dev/null; then
        local tema_ul="dark"
        [ "$MODO" = "light" ] && tema_ul="light"
        mkdir -p ~/.config/ulauncher
        cat > ~/.config/ulauncher/settings.json << ULJSON
{
    "hotkey-show-app": "<Control>space",
    "grab-mouse-pointer": true,
    "render-on-screen": "mouse-pointer-monitor",
    "show-indicator-icon": false,
    "terminal-command": "",
    "theme-name": "${tema_ul}"
}
ULJSON
        mkdir -p ~/.config/autostart
        cat > ~/.config/autostart/ulauncher.desktop << 'ULEOF'
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 5 && ulauncher --hide-window"
Name=Ulauncher
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=2
ULEOF
        pkill -9 ulauncher 2>/dev/null || true
        sleep 1
        DISPLAY="${DISPLAY:-:0}" ulauncher --hide-window 2>/dev/null &
        info "Ulauncher configurado (Ctrl+Space)"
    else
        warn "Ulauncher no se instaló"
    fi
}



fix_permisos_usuario() {
    step "Corrigiendo permisos de carpetas de usuario"
    local dirs=("$HOME/Escritorio" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Imágenes" "$HOME/Vídeos" "$HOME/Música" "$HOME/.local" "$HOME/.config")
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            sudo chown -R "$USER:$USER" "$d" 2>/dev/null || true
        fi
    done
    info "Permisos de usuario corregidos"
}

aplicaciones_autostart() {
    step "Configurando autostart"
    mkdir -p ~/.config/autostart
    mkdir -p ~/.local/bin

    # ── Instalar blueman (Bluetooth applet) ──
    if ! command -v blueman-applet &>/dev/null; then
        apt_silencioso install blueman 2>/dev/null || true
    fi

    # ── BLOQUEO: xfce4-screensaver (único bloqueador, sin duplicados).
    #    Sustituye a light-locker: light-locker 1.8.0 deja la pantalla en
    #    negro al desbloquear la 2ª vez tras cerrar la tapa (bug conocido). ──
    if command -v xfce4-screensaver &>/dev/null || [ -f /etc/xdg/autostart/xfce4-screensaver.desktop ]; then
        cat > ~/.config/autostart/xfce4-screensaver.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Xfce Screensaver
Comment=Bloqueo de pantalla (unico bloqueador)
Exec=xfce4-screensaver
Hidden=false
EOF
        xfconf-query -c xfce4-session -p /general/LockCommand -s "xfce4-screensaver-command --lock" 2>/dev/null || true
        info "Bloqueo: xfce4-screensaver (lock fiable)"
    else
        xfconf-query -c xfce4-session -p /general/LockCommand -s "loginctl lock-session" 2>/dev/null || true
    fi
    # ── Sesión: NUNCA se guarda ────────────────────────────────────────
    # En el diálogo de salida "Guardar sesión" puede estar desmarcado y, aun
    # así, xfce4-session dejaba la sesión guardada en caché: al siguiente
    # arranque se restauraban las apps. Aquí se desactivan los dos interruptores
    # (SaveOnExit = el checkbox del diálogo, AutoSave = el guardado automático)
    # y se borra cualquier sesión que hubiera quedado guardada de antes.
    xfconf-query -c xfce4-session -p /general/SaveOnExit -s false 2>/dev/null || true
    xfconf-query -c xfce4-session -p /general/AutoSave   -s false 2>/dev/null || true
    rm -f "$HOME/.cache/sessions/xfce4-session-$USER:0" 2>/dev/null || true
    rm -f "$HOME"/.cache/sessions/xfce4-session-* 2>/dev/null || true
    info "Sesión nunca se guarda (arranque limpio, sin apps recordadas)"

    # light-locker desactivado (autostart oculto) para no duplicar bloqueos.
    if command -v light-locker &>/dev/null || [ -f /etc/xdg/autostart/light-locker.desktop ]; then
        cat > ~/.config/autostart/light-locker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Light-locker
Exec=light-locker
Hidden=true
EOF
        pkill -x light-locker 2>/dev/null || true
        info "light-locker desactivado (evita doble bloqueo)"
    fi

    # ── Plank y la red: NO por el autostart de XFCE, sino por lightdm ──
    #
    # POR QUE NO FUNCIONA LO DE ARRIBA (y no es cosa de las prioridades):
    #   a) `X-XFCE-Autostart-Phase` no existe en este XFCE. La clave no esta
    #      ni en xfce4-session ni en libxfce4util, asi que Startup /
    #      Initialization / Default dan EXACTAMENTE lo mismo.
    #   b) Los clientes de sesion tampoco valen. LightDM no pone la variable
    #      XFCE4_SESSION, asi que xfce4-session arranca la sesion "Failsafe",
    #      e ignora /sessions/Default/. Y los clientes de /sessions/Failsafe/
    #      tampoco se lanzan: sus comandos vienen COMPILADOS en el binario
    #      (xfwm4, xfsettingsd, xfce4-panel, Thunar, xfdesktop) y lo que se
    #      guarde en xfconf se ignora. Comprobado tras un reinicio: con
    #      Count=7 y los clientes 5 y 6 escritos, /tmp/orden-login.txt salio
    #      vacio y el dock arranco por el autostart, igual que siempre.
    #   c) Medido de verdad, tres arranques seguidos:
    #         +2 s  xfwm4  +3 s  xfce4-panel / xfdesktop
    #         +11 s plank, nm-applet, blueman, ulauncher  (un solo lote)
    #      El dock tarda 0,14 s en crear su ventana, igual que la red: el hueco
    #      son los 8 s que xfce4-session espera antes de soltar el lote.
    #
    # LA VIA QUE SI LLEGA: `session-setup-script` de lightdm. Se ejecuta como
    # el usuario, con DISPLAY ya puesto, JUSTO antes de que arranque la sesion:
    # es el unico sitio que llega antes que xfce4-session. Desde ahi se lanza el
    # dock, y asi aparece con el fondo y la barra en vez de 8 s despues.
    # El .desktop de autostart se queda de red de seguridad, con pgrep para no
    # lanzar un segundo dock.
    # Los .desktop de autostart se quedan como RED DE SEGURIDAD: si algún día
    # la sesión no arrancara, el dock y la red aparecen igual. El `pgrep` evita
    # lanzar un segundo (haría parpadear el dock a los +11 s).
    rm -f ~/.config/autostart/plank.desktop
    cat > ~/.config/autostart/00-plank.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=Dock
Exec=sh -c 'pgrep -x plank >/dev/null 2>&1 || exec plank'
Icon=plank
Terminal=false
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=0
EOF
    cat > ~/.config/autostart/00-red.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Gestor de red
Comment=Red
Exec=sh -c 'pgrep -x nm-applet >/dev/null 2>&1 || exec nm-applet'
Icon=nm-applet
Terminal=false
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=0
EOF

    # NOTA: ya NO se genera xfdesktop-restart.desktop. Ese autostart lanzaba un
    # segundo xfdesktop en cada login (el de la sesión + este), haciendo que el
    # fondo y el escritorio "colapsen" al reiniciar. El tema de iconos lo aplica
    # xfsettingsd solo; no hace falta reiniciar el escritorio.

    # ── Ocultar el autostart roto de xscreensaver ──────────────────────
    # /etc/xdg/autostart/xscreensaver.desktop apunta a
    # /usr/share/xscreensaver/xscreensaver-wrapper.sh, que NO existe (el paquete
    # no está instalado): XFCE lo intentaba en cada login y moría. Aquí no se
    # toca el archivo del sistema, solo se tapa con el mismo nombre en el
    # autostart del usuario (el de usuario gana). El protector de pantalla que
    # se usa es xfce4-screensaver, que sí está instalado.
    cat > ~/.config/autostart/xscreensaver.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Screensaver
Hidden=true
X-GNOME-Autostart-enabled=false
EOF

    # ── Miniaplicación de red (nm-applet): arranque automático ──
    cat > ~/.config/autostart/nm-applet.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Gestor de red
Comment=Miniaplicación de red
Exec=nm-applet
Icon=network-wireless-symbolic
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=1
EOF
    
    # ── Bluetooth (blueman-applet): arranque automático temprano ──
    cat > ~/.config/autostart/blueman-applet.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth
Comment=Gestor de Bluetooth
Exec=blueman-applet
Icon=bluetooth-symbolic
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-Autostart-Priority=2
EOF
    
    # ── 1Password: NO se inicia nunca ─────────────────────────────────
    # 1Password se auto-instala su propio .desktop de autostart cada vez que
    # arranca (y lo reescribe si el usuario toca el ajuste), así que no vale
    # con ocultar el suyo. La forma que aguanta es la MÁSCARA de sistema: un
    # .desktop en /etc/xdg/autostart con Hidden=true y el MISMO nombre anula el
    # del usuario, aunque 1Password lo regenere. Aquí se 1Password con 7 procesos
    # (zygotes included) occupying RAM and un icono de estado en la barra.
    mkdir -p /etc/xdg/autostart
    _onep_mascara=/etc/xdg/autostart/com.onepassword.OnePassword.desktop
    if sudo -n true 2>/dev/null; then
        sudo tee "$_onep_mascara" >/dev/null << 'ONEOF'
[Desktop Entry]
Type=Application
Name=1Password (autostart desactivado)
Hidden=true
ONEOF
        sudo chmod 644 "$_onep_mascara" 2>/dev/null || true
        info "1Password: autostart enmascarado en /etc/xdg/autostart"
    else
        warn "1Password: hace falta sudo para enmascarar el autostart"
    fi

    # Y además el suyo propio, por si algún gestor de sesión leyera el del usuario
    local _onep_usuario="$HOME/.config/autostart/com.onepassword.OnePassword.desktop"
    if [ -f "$_onep_usuario" ]; then
        [ -f "$_onep_usuario.bak" ] || cp -a "$_onep_usuario" "$_onep_usuario.bak"
        sed -i 's/^X-GNOME-Autostart-enabled=.*/X-GNOME-Autostart-enabled=false/' "$_onep_usuario"
        grep -q '^Hidden=' "$_onep_usuario" || sed -i 's/^\[Desktop Entry\]$/[Desktop Entry]\nHidden=true/' "$_onep_usuario"
        info "1Password: autostart del usuario desactivado"
    fi
    pkill -x 1password 2>/dev/null || true
    sleep 1
    pkill -9 -x 1password 2>/dev/null || true

    info "Autostart configurado (Plank primero, red, Bluetooth, sin 1Password)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA ICONOS

    paso="${2:-todo}"
    case "$paso" in
        appmenu)   aplicaciones_appmenu ;;
        ulauncher) aplicaciones_ulauncher ;;
        autostart) aplicaciones_autostart ;;
        fix_permisos_usuario) fix_permisos_usuario ;;
        todo)
            aplicaciones_appmenu
            aplicaciones_ulauncher
            aplicaciones_autostart
            ;;
    esac
fi
