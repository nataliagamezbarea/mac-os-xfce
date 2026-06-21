#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

final_recargar() {
    step "Recargando todos los componentes visuales"

    xfconf-query -c xfwm4 -p /general/theme           -s "$TEMA_XFWM"   2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/button_layout   -s "CMH|"    2>/dev/null || true
    xfconf-query -c xfwm4 -p /general/title_alignment -s "center"  2>/dev/null || true

    pkill -9 xfce4-panel 2>/dev/null || true; sleep 2
    DISPLAY="${DISPLAY:-:0}" xfce4-panel & sleep 3

    if [ "$(id -u)" = "0" ]; then
        su - "$SUDO_USER" -c "DISPLAY=${DISPLAY:-:0} xfwm4 --replace" 2>/dev/null &
    else
        DISPLAY="${DISPLAY:-:0}" xfwm4 --replace 2>/dev/null &
    fi; sleep 3

    pkill -9 xfsettingsd 2>/dev/null || true; sleep 1
    xfsettingsd --no-daemon & sleep 2

    xfconf-query -c xsettings -p /Net/ThemeName     -s "$TEMA" 2>/dev/null || true
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true

    pkill -9 xfdesktop 2>/dev/null || true; sleep 1
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true
    aplicar_iconos_persistente "$ICONOS"; sleep 1
    DISPLAY="${DISPLAY:-:0}" xfdesktop & sleep 2

    pkill -9 picom 2>/dev/null || true; sleep 1
    picom --config "$HOME/.config/picom/picom.conf" -b 2>/dev/null || true; sleep 1

    pkill -9 plank 2>/dev/null || true; sleep 1
    nohup plank > /tmp/plank.log 2>&1 & sleep 2

    pkill -9 nm-applet 2>/dev/null || true; sleep 1
    nm-applet & sleep 2

    [ "$MODO" = "dark" ] && aplicar_modo_oscuro

    # Forzar botones macOS incluso para CSD (gsettings + dconf)
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || true
    if command -v dconf &>/dev/null; then
        dconf write /org/gnome/desktop/wm/preferences/button-layout "'close,minimize,maximize:'" 2>/dev/null || true
    fi

    pkill -9 nautilus 2>/dev/null || true
    nohup env GTK_THEME=$TEMA GTK_CSD=1 nautilus --no-default-window > /dev/null 2>&1 &
    sleep 1

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
