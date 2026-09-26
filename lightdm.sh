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
    
    # Intentar descargar el wallpaper con mejor manejo de errores
    if curl -L --max-time 30 --retry 3 -o "$destino" "$url" 2>/dev/null; then
        if [ -s "$destino" ]; then
            info "Wallpaper descargado correctamente"
            lightdm_aplicar_fondo "$destino"
        else
            warn "El archivo descargado está vacío, usando fondo alternativo"
            # Usar fondo del sistema como respaldo
            local fondo_sistema="/usr/share/backgrounds/linuxmint/default_background.jpg"
            if [ -f "$fondo_sistema" ]; then
                lightdm_aplicar_fondo "$fondo_sistema"
            else
                warn "No se encontró fondo alternativo"
            fi
        fi
    else
        warn "No se pudo descargar el wallpaper, usando fondo del sistema"
        local fondo_sistema="/usr/share/backgrounds/linuxmint/default_background.jpg"
        if [ -f "$fondo_sistema" ]; then
            lightdm_aplicar_fondo "$fondo_sistema"
        else
            warn "No se encontró fondo del sistema"
        fi
    fi
}

lightdm_aplicar_fondo() {
    local fondo="$1"
    [ -s "$fondo" ] || { warn "Fondo no encontrado"; return; }
    pkill -9 xfdesktop 2>/dev/null || true; sleep 2
    asegurar_xfconfd; sleep 1

    # Detectar TODOS los monitores disponibles (incluyendo nombres complejos)
    local monitores
    monitores=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -oP '(?<=/screen0/)[^/]+' | sort -u)
    
    # Si no se detectaron monitores, usar monitor0 como fallback
    if [ -z "$monitores" ]; then
        monitores="monitor0"
    fi
    
    info "Monitores detectados: $monitores"
    
    # Configurar fondo para TODOS los monitores y TODOS los workspaces
    for mon in $monitores; do
        for ws in 0 1 2 3 4 5 6 7 8 9; do
            local base="/backdrop/screen0/${mon}/workspace${ws}"
            xfconf-query -c xfce4-desktop -p "${base}/last-image"            --create -t string -s "$fondo" 2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 4       2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/image-show"            --create -t bool   -s true     2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/color-style"           --create -t int    -s 1       2>/dev/null || true
        done
    done

    # Configurar monitor0 específicamente como fallback universal
    for ws in 0 1 2 3 4 5 6 7 8 9; do
        local base="/backdrop/screen0/monitor0/workspace${ws}"
        xfconf-query -c xfce4-desktop -p "${base}/last-image"            --create -t string -s "$fondo" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 4       2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "${base}/image-show"            --create -t bool   -s true     2>/dev/null || true
    done

    # También sobre cualquier propiedad existente de imagen
    for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|image-path|last-single-image"); do
        xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" 2>/dev/null || true
    done
    for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep image-style); do
        xfconf-query -c xfce4-desktop -p "$ruta" -s 4 2>/dev/null || true
    done

    info "Fondo aplicado a todos los monitores y workspaces"

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
