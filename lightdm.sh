#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

lightdm_configurar() {
    step "Configurando LightDM"
    if apt-cache show lightdm-slick-greeter &>/dev/null; then
        apt_silencioso install lightdm-slick-greeter
        sudo sed -i 's/^#*greeter-session=.*/greeter-session=slick-greeter/' /etc/lightdm/lightdm.conf 2>/dev/null || true
        sudo sed -i 's/^#*user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
        info "lightdm-slick-greeter instalado"
    elif apt-cache show lightdm-gtk-greeter &>/dev/null; then
        apt_silencioso install lightdm-gtk-greeter lightdm-gtk-greeter-settings
        sudo sed -i 's/^#*greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf 2>/dev/null || true
        sudo sed -i 's/^#*user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
        info "lightdm-gtk-greeter instalado como respaldo"
    else
        warn "No se encontró ningún greeter compatible"
    fi
    info "LightDM configurado"
}

lightdm_fondo() {
    step "Descargando y aplicando wallpaper"
    local url="https://github.com/vinceliuice/WhiteSur-wallpapers/blob/main/4k/WhiteSur.jpg?raw=true"
    local destino="$HOME/Pictures/ventura-wallpapers/fondo.jpg"
    mkdir -p "$HOME/Pictures/ventura-wallpapers"
    curl -L --max-time 20 -o "$destino" "$url"
    [ -s "$destino" ] && lightdm_aplicar_fondo "$destino" || warn "No se pudo descargar el wallpaper"
}

lightdm_aplicar_fondo() {
    local fondo="$1"
    [ -s "$fondo" ] || { warn "Fondo no encontrado"; return; }
    pkill -9 xfdesktop 2>/dev/null || true; sleep 2
    asegurar_xfconfd; sleep 1

    local claves; claves=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|image-path|last-single-image")
    if [ -z "$claves" ]; then
        for ws in 0 1 2 3; do
            local base="/backdrop/screen0/monitor0/workspace${ws}"
            xfconf-query -c xfce4-desktop -p "${base}/last-image"            --create -t string -s "$fondo" 2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 5       2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/backdrop-cycle-enable" --create -t bool   -s false   2>/dev/null || true
        done
        for ws in 0 1 2 3; do
            local base="/backdrop/screen0/monitorHDMI-1/workspace${ws}"
            xfconf-query -c xfce4-desktop -p "${base}/last-image"            --create -t string -s "$fondo" 2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 5       2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/backdrop-cycle-enable" --create -t bool   -s false   2>/dev/null || true
        done
    else
        for ruta in $claves; do
            xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" 2>/dev/null || true
        done
        for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep image-style); do
            xfconf-query -c xfce4-desktop -p "$ruta" -s 5 2>/dev/null || true
        done
        for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep backdrop-cycle-enable); do
            xfconf-query -c xfce4-desktop -p "$ruta" -s false 2>/dev/null || true
        done
    fi

    info "Fondo aplicado via xfconf-query"

    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true
    aplicar_iconos_persistente "$ICONOS"
    sleep 2; DISPLAY="${DISPLAY:-:0}" xfdesktop & sleep 3
    info "Fondo de pantalla aplicado"

    sudo mkdir -p /usr/share/backgrounds/linuxmint
    sudo cp "$fondo" /usr/share/backgrounds/linuxmint/macos-login.jpg
    sudo tee /etc/lightdm/slick-greeter.conf >/dev/null << 'SEOF'
[Greeter]
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
draw-grid=false
show-hostname=false
show-power=true
show-a11y=true
SEOF
    sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
    sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/99_linuxmint.conf >/dev/null << 'SEOF'
[Greeter]
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
user-background=true
SEOF
    info "Fondo aplicado también en LightDM"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && ICONOS="WhiteSur-light" || ICONOS="WhiteSur-dark"
    export MODO ICONOS

    paso="${2:-todo}"
    case "$paso" in
        lightdm)   lightdm_configurar ;;
        wallpaper) lightdm_fondo ;;
        todo)
            lightdm_configurar
            lightdm_fondo
            ;;
    esac
fi
