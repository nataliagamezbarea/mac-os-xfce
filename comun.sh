#!/bin/bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DIR_LOG="$PWD/logs"
mkdir -p "$DIR_LOG" 2>/dev/null

log_escribir() {
    local nivel="$1"
    local msg="$2"
    local fuente="${BASH_SOURCE[2]:-${BASH_SOURCE[0]}}"
    echo "$(date '+%H:%M:%S') [$nivel] $msg" >> "$DIR_LOG/$(basename "$fuente" .sh).log" 2>/dev/null || true
}

info()  { echo -e "${GREEN}[✓]${NC} $1"; log_escribir INFO "$1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; log_escribir WARN "$1"; }
error() { echo -e "${RED}[✗]${NC} $1"; log_escribir ERROR "$1"; exit 1; }
step()  { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

apt_silencioso() { DEBIAN_FRONTEND=noninteractive sudo apt-get -qq -y "$@"; }

DIR_COMUN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

verificar_clon() {
    local carpeta=$1
    local repo=$2
    [ -d "$HOME/$carpeta" ] && rm -rf "$HOME/$carpeta"
    git -C "$HOME" clone "$repo"
}

asegurar_xfconfd() {
    if ! pgrep -x xfconfd > /dev/null; then
        local ruta
        ruta=$(find /usr -name "xfconfd" 2>/dev/null | head -1)
        if [ -n "$ruta" ]; then
            "$ruta" &
            sleep 2
            info "xfconfd arrancado"
        fi
    fi
}

aplicar_iconos_persistente() {
    local tema_iconos="$1"
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$tema_iconos" 2>/dev/null || true

    for dir_gtk in gtk-3.0 gtk-4.0; do
        local archivo_ini="$HOME/.config/$dir_gtk/settings.ini"
        mkdir -p "$(dirname "$archivo_ini")"
        if grep -q "gtk-icon-theme-name" "$archivo_ini" 2>/dev/null; then
            sed -i "s/^gtk-icon-theme-name=.*/gtk-icon-theme-name=$tema_iconos/" "$archivo_ini"
        else
            echo "gtk-icon-theme-name=$tema_iconos" >> "$archivo_ini"
        fi
    done

    local ruta_iconos="$HOME/.icons/$tema_iconos"
    if [ -d "$ruta_iconos" ]; then
        local archivo_idx="$ruta_iconos/index.theme"
        [ -f "$archivo_idx" ] || printf "[Icon Theme]\nName=%s\n" "$tema_iconos" > "$archivo_idx"
    fi
}

aplicar_modo_oscuro() {
    local tema="${TEMA:-WhiteSur-Dark}"

    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "$tema" 2>/dev/null || true

    if command -v dconf &>/dev/null; then
        dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'" 2>/dev/null || true
        dconf write /org/gnome/desktop/interface/gtk-theme "'$tema'" 2>/dev/null || true
    fi

    local archivo_env="$HOME/.config/environment.d/dark.conf"
    mkdir -p "$(dirname "$archivo_env")"
    cat > "$archivo_env" << EOF
GTK_THEME=$tema
ADW_DISABLE_PORTAL=1
EOF

    local ini_gtk3="$HOME/.config/gtk-3.0/settings.ini"
    mkdir -p "$(dirname "$ini_gtk3")"
    if grep -q "gtk-application-prefer-dark-theme" "$ini_gtk3" 2>/dev/null; then
        sed -i "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=1/" "$ini_gtk3"
    else
        echo "gtk-application-prefer-dark-theme=1" >> "$ini_gtk3"
    fi

    mkdir -p ~/.config/gtk-4.0
    local origen_gtk4=""
    for candidato in "$HOME/.themes/${tema}/gtk-4.0" "/usr/share/themes/${tema}/gtk-4.0"; do
        [ -d "$candidato" ] && origen_gtk4="$candidato" && break
    done

    if [ -n "$origen_gtk4" ]; then
        [ -f "$origen_gtk4/gtk.gresource" ] && cp "$origen_gtk4/gtk.gresource" ~/.config/gtk-4.0/ || true
        cat > ~/.config/gtk-4.0/gtk.css << CSSEOF
@import url("file://${origen_gtk4}/gtk.css");
CSSEOF
        cat > ~/.config/gtk-4.0/gtk-dark.css << CSSEOF
@import url("file://${origen_gtk4}/gtk-dark.css");
CSSEOF
        info "CSS de GTK4 importado desde $origen_gtk4"
    else
        warn "No se encontró la carpeta gtk-4.0 del tema"
    fi

    for archivo_rc in ~/.profile ~/.bashrc ~/.zshrc; do
        grep -q "GTK_THEME=$tema" "$archivo_rc" 2>/dev/null || echo "export GTK_THEME=$tema" >> "$archivo_rc"
    done

    info "Modo oscuro aplicado"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Este archivo es una librería. No se ejecuta directamente."
    echo "Úsalo con: source comun.sh"
fi
