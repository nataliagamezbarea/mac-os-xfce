#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

final_recargar() {
    step "Recargando todos los componentes visuales"

    xfconf-query -c xfwm4 -p /general/theme           -s "$TEMA_XFWM"   2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/button_layout   -s "CMH|"    2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/title_alignment -s "center"  2>/dev/null || true

    # ── 1) Parar TODO lo visual de golpe, sin esperas entre medias ──
    # Forzar cierre de xfdesktop como root y usuario para evitar procesos huérfanos
    sudo pkill -9 xfdesktop 2>/dev/null || true
    pkill -9 xfdesktop    2>/dev/null || true
    pkill -9 xfce4-panel 2>/dev/null || true
    pkill -9 plank        2>/dev/null || true
    pkill -9 xfsettingsd  2>/dev/null || true
    sleep 2
    
    # Limpiar sesión guardada de xfdesktop para que no restaure la configuración anterior
    rm -f ~/.cache/sessions/xfdesktop* 2>/dev/null || true
    rm -f ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml.bak 2>/dev/null || true

    # xfwm4 NO se reinicia a propósito: aplica tema y botones en caliente vía
    # xfconf, y un `xfwm4 --replace` con ventanas abiertas corrompe el "tamaño
    # de restauración" de Chromium/Brave (luego al desmaximizar la ventana NO
    # se achica: se queda en pantalla completa). Si hace falta reiniciarlo,
    # hacerlo sin ventanas maximizadas.

    # xfsettingsd va en segundo plano: aplica los ajustes de tema en caliente
    xfsettingsd --no-daemon >/dev/null 2>&1 &

    xfconf-query -c xsettings -p /Net/ThemeName     -s "$TEMA" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true

    # Forzar idioma español en el entorno gráfico
    for rc in ~/.xprofile ~/.profile ~/.bashrc; do
        grep -q 'LANG=es_ES.UTF-8' "$rc" 2>/dev/null || echo 'export LANG=es_ES.UTF-8' >> "$rc"
        grep -q 'LANGUAGE=es_ES:es' "$rc" 2>/dev/null || echo 'export LANGUAGE=es_ES:es' >> "$rc"
    done
    export LANG=es_ES.UTF-8
    export LANGUAGE=es_ES:es

    # Habilitar menú contextual en el escritorio
    # Primero asegurar que xfconfd esté corriendo
    asegurar_xfconfd
    sleep 1
    xfconf-query -c xfce4-desktop -p /desktop-icons/style --create -t int -s 2 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /context-menu/show-context-menus --create -t bool -s true 2>/dev/null || true
    xfconf-query -c xfce4-desktop -p /context-menu/show-in-montiores-all-workspaces --create -t bool -s true 2>/dev/null || true

    # Configurar systray para mostrar wifi y bluetooth
    xfconf-query -c xfce4-panel -p /plugins/plugin-10/known-legacy-items \
        --create --force-array \
        -t string -s "miniaplicación gestor de la red" \
        -t string -s "miniaplicación gestor de bluetooth" \
        2>/dev/null || true
    xfconf-query -c xfce4-panel -p /plugins/plugin-10/known-items \
        --create --force-array \
        -t string -s "nm-applet" \
        -t string -s "blueman-applet" \
        2>/dev/null || true
    xfconf-query -c xfce4-panel -p /plugins/plugin-10/hidden-items \
        --create --force-array \
        -t string -s "mintupdate.py" \
        -t string -s "tray.py" \
        -t string -s "applet.py" \
        -t string -s "clipman" \
        2>/dev/null || true
    info "Systray configurado: wifi y bluetooth visibles"

    # Re-aplicar wallpaper (el fondo de pantalla) ANTES de arrancar xfdesktop,
    # para que el fondo correcto esté puesto en el momento de pintarlo.
    # Forzar el fondo de macOS directamente (no depender de xfconf)
    local fondo=""
    for f in "$HOME/Pictures/ventura-wallpapers/fondo.jpg" "/usr/share/backgrounds/linuxmint/macos-login.jpg"; do
        if [ -f "$f" ]; then
            fondo="$f"
            break
        fi
    done
    
    if [ -n "$fondo" ] && [ -f "$fondo" ]; then
        info "Fondo encontrado: $fondo"
        # Aplicar el fondo a TODAS las rutas de imagen
        for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|image-path|last-single-image"); do
            xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" 2>/dev/null || true
        done
        for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep image-style); do
            xfconf-query -c xfce4-desktop -p "$ruta" -s 5 2>/dev/null || true
        done
        # Forzar la propiedad image-show a true
        for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep image-show); do
            xfconf-query -c xfce4-desktop -p "$ruta" -s true 2>/dev/null || true
        done
    else
        warn "No se encontró fondo de pantalla válido"
    fi
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true
    aplicar_iconos_persistente "$ICONOS"

    # ── 2) FONDO + BARRA + PLANK A LA VEZ ───────────────────────────────
    # Los tres se lanzan en el mismo instante (y en segundo plano), con una
    # sola espera al final: el escritorio aparece montado de golpe, sin que
    # la barra llegue segundos antes que el fondo o el dock.
    # Reiniciar componentes como el usuario actual (no como root)
    export DISPLAY="${DISPLAY:-:0}"
    setsid xfce4-panel --display="$DISPLAY" >/dev/null 2>&1 & disown
    setsid xfdesktop --display="$DISPLAY"    >/dev/null 2>&1 & disown
    nohup plank > /tmp/plank.log 2>&1 &
    sleep 4

    pkill -9 nm-applet 2>/dev/null || true
    nm-applet >/dev/null 2>&1 &

    [ "$MODO" = "dark" ] && aplicar_modo_oscuro

    # Forzar botones macOS incluso para CSD (gsettings + dconf)
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
    if command -v dconf &>/dev/null; then
        dconf write /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'" 2>/dev/null || true
    fi

    pkill -9 nautilus 2>/dev/null || true
    nohup env GTK_THEME=$TEMA GTK_CSD=1 nautilus --gapplication-service > /dev/null 2>&1 &
    sleep 1

    # Fix navegador: reajustar ventanas Chromium que quedaron a pantalla
    # completa sin maximizar por los reinicios de panel/xfconfd anteriores
    reparar_ventanas_navegador

    info "Todos los componentes recargados"
}

final_resumen() {
    local tema_final; tema_final=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null)
    local iconos_final; iconos_final=$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null)

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     ✅  macOS Ventura XFCE — INSTALADO      ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Modo:       ${GREEN}$MODO${NC}"
    echo -e "  Tema GTK:   ${GREEN}$tema_final${NC}"
    echo -e "  Iconos:     ${GREEN}$iconos_final${NC}"
    echo -e "  Dock:       ${GREEN}Plank (Transparente, 48px, zoom 150%)${NC}"
    echo -e "  Atajo:      ${GREEN}Ctrl+Space → Ulauncher${NC}"
    echo ""
    echo -e "  ${YELLOW}Cierra sesión y vuelve a entrar para${NC}"
    echo -e "  ${YELLOW}aplicar todos los cambios completamente.${NC}"
    echo ""
    echo -e "  ${YELLOW}Si los iconos del panel no aparecen:${NC}"
    echo -e "  xfconf-query -c xsettings -p /Net/IconThemeName -s $ICONOS"
    echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; TEMA_XFWM="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; TEMA_XFWM="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA TEMA_XFWM ICONOS

    paso="${2:-todo}"
    case "$paso" in
        recargar) final_recargar ;;
        resumen)  final_resumen ;;
        todo)
            final_recargar
            final_resumen
            ;;
    esac
fi
