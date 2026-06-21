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
        curl -L --retry 3 --max-time 60 -o "$appmenu_deb" \
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
        curl -L --retry 3 --max-time 60 -o /tmp/ulauncher.deb \
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
ULEOF
        pkill -9 ulauncher 2>/dev/null || true
        sleep 1
        DISPLAY="${DISPLAY:-:0}" ulauncher --hide-window 2>/dev/null &
        info "Ulauncher configurado (Ctrl+Space)"
    else
        warn "Ulauncher no se instaló"
    fi
}

aplicaciones_picom() {
    step "Instalando Picom (blur + sombras)"
    cd ~
    verificar_clon "picom" "https://github.com/ibhagwan/picom.git"
    cd picom
    meson setup --buildtype=release build
    ninja -C build && sudo ninja -C build install
    cd ~
    if ! command -v picom &>/dev/null; then
        warn "Picom no se compiló — revisá los errores arriba"
        return
    fi
    mkdir -p ~/.config/picom
    cat > ~/.config/picom/picom.conf << 'EOF'
backend = "glx";
vsync = true;
corner-radius = 14;
rounded-corners-exclude = ["window_type = 'dock'"];
blur-method = "dual_kawase";
blur-strength = 8;
shadow = true;
shadow-radius = 15;
shadow-opacity = 0.35;
EOF
    info "Picom configurado"
}

aplicaciones_autostart() {
    step "Configurando autostart"
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/plank.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 3 && plank"
Name=Plank
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
    cat > ~/.config/autostart/picom.desktop << 'EOF'
[Desktop Entry]
Type=Application
Exec=picom --config /home/USER/.config/picom/picom.conf -b
Name=Picom
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
    sed -i "s|/home/USER/|/home/$USER/|g" ~/.config/autostart/picom.desktop
    cat > ~/.config/autostart/xfdesktop-restart.desktop << EOF
[Desktop Entry]
Type=Application
Exec=bash -c "sleep 2 && xfconf-query -c xsettings -p /Net/IconThemeName -s '$ICONOS' 2>/dev/null; sleep 1 && xfdesktop"
Name=XFDesktop
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF

    cat > ~/.config/autostart/nautilus-dark.desktop << EOF
[Desktop Entry]
Type=Application
Name=Modo oscuro Nautilus
Exec=bash -c "sleep 3 && dconf write /org/gnome/desktop/interface/color-scheme \"'prefer-dark'\" && dconf write /org/gnome/desktop/interface/gtk-theme \"'$TEMA'\" && dconf write /org/gnome/desktop/wm/preferences/button-layout \"'close,minimize,maximize:'\""
Hidden=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
    # nm-applet desactivado: el systray de XFCE ya muestra el gestor de red nativo.
    # Lanzarlo ademas creaba un icono duplicado en la bandeja.
    cat > ~/.config/autostart/nm-applet.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Gestor de red
Exec=nm-applet
Icon=network-wireless-symbolic
Hidden=true
StartupNotify=false
X-GNOME-Autostart-enabled=false
EOF
    pkill -f nm-applet 2>/dev/null || true
    info "Autostart configurado"
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
        picom)     aplicaciones_picom ;;
        autostart) aplicaciones_autostart ;;
        todo)
            aplicaciones_appmenu
            aplicaciones_ulauncher
            aplicaciones_picom
            aplicaciones_autostart
            ;;
    esac
fi
