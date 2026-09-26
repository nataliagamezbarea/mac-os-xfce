#!/bin/bash

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_escribir() { :; }

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

apt_silencioso() { DEBIAN_FRONTEND=noninteractive sudo apt-get -qq -y "$@"; }

DIR_COMUN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

verificar_clon() {
    local carpeta=$1
    local repo=$2
    local destino="$HOME/$carpeta"

    if [ -d "$destino/.git" ]; then
        info "Repositorio $carpeta ya existe: $destino"
        return 0
    fi

    if [ -e "$destino" ]; then
        local respaldo="${destino}.backup-$(date +%Y%m%d-%H%M%S)"
        warn "$destino existe pero no es un repositorio Git"
        warn "Se conservará como $respaldo"
        mv "$destino" "$respaldo" || return 1
    fi

    git -C "$HOME" clone "$repo" "$destino"
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

# Repara ventanas de navegadores Chromium cuya geometría de restauración quedó
# corrupta: si los scripts reinician panel/xfconfd o borran la sesión con la
# ventana abierta, Chromium pierde el estado MAXIMIZED de golpe y guarda
# "pantalla completa" como su tamaño normal → al desmaximizar NO se achica.
# Criterio de detección: geometría a pantalla completa (wmctrl -lG) SIN estado
# maximizado. Se reajusta a media pantalla (Chromium resincroniza su
# restauración) y, si la ventana estaba maximizada, se le devuelve ese estado.
reparar_ventanas_navegador() {
    command -v wmctrl  >/dev/null 2>&1 || return 0
    command -v xprop   >/dev/null 2>&1 || return 0

    local wid cls estado maxi w h ws corrupta medio_x medio_y full warea ancho alto warea_y
    # Área útil REAL (panel/dock fuera) según el gestor de ventanas:
    # _NET_WORKAREA devuelve "x, y, ancho, alto" → se adapta a cualquier
    # resolución, alto o posición del panel (arriba/abajo), docks y monitores.
    warea=$(xprop -root _NET_WORKAREA 2>/dev/null | grep -oE '[0-9]+, [0-9]+, [0-9]+, [0-9]+' | head -1)
    if [ -n "$warea" ]; then
        warea_y=$(echo "$warea" | cut -d, -f2 | tr -d ' ')
        ancho=$(echo "$warea" | cut -d, -f3 | tr -d ' ')
        alto=$(echo "$warea" | cut -d, -f4 | tr -d ' ')
    else
        # fallback: toda la pantalla
        read -r ancho alto <<< "$(xdotool getdisplaygeometry 2>/dev/null || echo 1920 1080)"
        warea_y=0
    fi
    ancho="${ancho:-1920}"; alto="${alto:-1080}"; warea_y="${warea_y:-0}"
    full=$((ancho - 40))            # ancho "a pantalla completa" (con tolerancia)
    medio_x=$((ancho / 2 - 2))      # media pantalla (área útil / 2)
    medio_y=$((alto))               # alto útil completo (llega hasta el final)

    # wmctrl -lG → ventana, desktop, x, y, ancho, alto, host, título
    while read -r wid desktop wx wy w h host titulo; do
        [ "$wid" = "0x0" ] && continue
        cls=$(xprop -id "$wid" WM_CLASS 2>/dev/null | grep -o '"[^"]*"' | tail -1 | tr -d '"')
        case "$cls" in
            brave|Brave|Brave-browser|chromium|Chromium|Chromium-browser|google-chrome|Google-chrome|microsoft-edge|vivaldi|opera) ;;
            *) continue ;;
        esac
        # geometría corrupta = pantalla completa sin maximizar, O ventana
        # minimizada con alto que no llega al final del escritorio (fantasma
        # a mitad de alto, como deja el script cuando la interrumpe)
        [ "${w:-0}" -le 0 ] && continue
        corrupta=0
        if [ "${w:-0}" -ge "$full" ]; then
            corrupta=1
        else
            ws=$(xprop -id "$wid" WM_STATE 2>/dev/null)
            if echo "$ws" | grep -q "window state: Iconic" && \
               [ "${h:-0}" -gt 0 ] && [ "${h:-0}" -lt "$((medio_y - 60))" ]; then
                corrupta=1
            fi
        fi
        [ "$corrupta" = "0" ] && continue

        estado=$(xprop -id "$wid" _NET_WM_STATE 2>/dev/null)
        maxi=0
        echo "$estado" | grep -q "_NET_WM_STATE_MAXIMIZED" && maxi=1

        # 1) quitar maximizado (para que Chromium recalcule su restauración)
        [ "$maxi" = "1" ] && wmctrl -ir "$wid" -b remove,maximized_vert,maximized_horz
        sleep 0.4

        # 2) reajustar a media pantalla (desiconifica si quedó minizada-fantasma)
        info "Navegador ($cls): geometría corrupta ${w}x${h} → media pantalla"
        wmctrl -ir "$wid" -e 0,0,"$warea_y","$medio_x","$medio_y"
        sleep 0.4

        # 3) devolverle el maximizado si lo tenía
        [ "$maxi" = "1" ] && wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz
    done < <(wmctrl -lG 2>/dev/null)
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Este archivo es una librería. No se ejecuta directamente."
    echo "Úsalo con: source comun.sh"
fi
