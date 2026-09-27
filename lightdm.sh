#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

lightdm_configurar() {
    step "Configurando LightDM"
    # OJO: aquí NO se instala nada. Se usa el greeter que ya hay. El
    # slick-greeter de esta maquina (2.2.6+zena) trae el tema incrustado y lee
    # solo /etc/lightdm/slick-greeter.conf, asi que no le hace falta ningun
    # paquete de temas. Antes este bloque hacia "apt install lightdm-gtk-greeter"
    # como respaldo: en una ejecucion se colaron dos paquetes que no hacia
    # falta (y el paquete de temas de slick no existe en apt, por eso caia
    # siempre en el respaldo).
    if [ -x /usr/sbin/slick-greeter ]; then
        info "greeter: slick-greeter (ya instalado)"
    else
        warn "slick-greeter no esta instalado: no se instala nada, se deja el greeter del sistema"
    fi
    sudo sed -i 's/^#*user-session=.*/user-session=xfce/' /etc/lightdm/lightdm.conf 2>/dev/null || true
    lightdm_pantallas_encendidas
    lightdm_dock_temprano
    info "LightDM configurado"
}

# ── La pantalla del login, siempre encendida ────────────────────────
# POR QUE: el login se ve bien al cambiar de usuario y al suspender, pero al
# encender el computer no. La diferencia no era LightDM (arranca a los 6 s y
# el greeter aparece a los 10 s, comprobado en el journal), sino la PANTALLA:
# el X del greeter es una instancia aparte, sin xfce4-power-manager que le
# quite el DPMS, y esta pantalla no da EDID (0 bytes en los 5 conectores), asi
# que el apagado se queda a lo que diga el X. Al suspender lo arreglaba el
# hook de resume (xset -dpms) y al cambiar de usuario el X ya venia de la
# sesion, sin DPMS. En frio no pasaba nada de eso.
#
# greeter-setup-script es la opcion de lightdm para justo esto: se ejecuta
# como root, con DISPLAY del X del login, antes de arrancar el greeter.
lightdm_pantallas_encendidas() {
    local dir="/usr/local/lib/mac-os-xfce"
    local script="$dir/greeter-setup.sh"

    sudo mkdir -p "$dir"
    sudo tee "$script" >/dev/null << 'GREEOF'
#!/bin/sh
# Lo ejecuta lightdm como root antes de arrancar el greeter, con DISPLAY
# apuntando al X del login. Sin esto, en un arranque en frio la pantalla del
# login puede quedarse en negro y parecer que LightDM no arranca.
# Todo se ignora si falla: es cosmetico y nunca debe tumbar el login.
xset dpms force on  >/dev/null 2>&1 || true
xset s off         >/dev/null 2>&1 || true
xset -dpms         >/dev/null 2>&1 || true
xset s noblank     >/dev/null 2>&1 || true
exit 0
GREEOF
    sudo chmod 0755 "$script"

    # OJO: cada ajuste va en SU PROPIO drop-in, no todos en el 99.
    # lightdm_aplicar_fondo reescribia entero el 99-macos-greeter.conf (con un
    # `tee`) para fijar el greeter, y al hacerlo se llevaba por delante el
    # greeter-setup-script y el session-setup-script que lightdm_configurar
    # acababa de registrar dos lineas antes. Como menu.sh llama a
    # `lightdm.sh lightdm` y despues a `lightdm.sh wallpaper`, al terminar
    # quedaban los dos ajustes borrados: el login en frio se volvia a quedar
    # negro y el dock volvia a salir a los +11 s. Con un fichero por ajuste
    # esto ya no puede pasar (y el 99 solo se toca para su linea del greeter).
    local dropin="/etc/lightdm/lightdm.conf.d/98-macos-pantallas.conf"
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    printf '[Seat:*]\ngreeter-setup-script=%s\n' "$script" | sudo tee "$dropin" >/dev/null
    # Limpiar la copia vieja que quedo en el 99 (si la hubiera)
    sudo sed -i '/^greeter-setup-script=/d' /etc/lightdm/lightdm.conf.d/99-macos-greeter.conf 2>/dev/null || true

    info "Pantalla del login: siempre encendida (greeter-setup-script)"
}

# ── El dock, antes de que arranque la sesión ─────────────────────────
# POR QUE: el dock salia 8 s tarde, cuando la barra y el fondo ya estaban.
# Todo el autostart de XFCE sale en un solo lote a los +11 s, y a los +2/+3 s
# solo arrancan los clientes de la sesion Failsafe, que van compilados en el
# binario de xfce4-session y no se pueden anadir. session-setup-script de
# lightdm es el unico sitio que se ejecuta como el usuario ANTES de que
# empiece la sesion, con el DISPLAY ya activo: desde ahi se adelanta el dock.
#
# session-setup-script es una opcion de lightdm (fichero de configuracion),
# no un envoltorio: lightdm lo ejecuta una vez por inicio de sesion. Y si
# este script fallara, el .desktop de autostart de Plank lo lanza igualmente
# a los +11 s, asi que nunca se queda el escritorio sin dock.
lightdm_dock_temprano() {
    local dir="/usr/local/lib/mac-os-xfce"
    local script="$dir/session-setup.sh"

    sudo mkdir -p "$dir"
    sudo tee "$script" >/dev/null << 'SEOF'
#!/bin/sh
# Lo ejecuta lightdm como el usuario justo antes de arrancar la sesion.
# Lanza TODOS los procesos SIMULTÁNEAMENTE para que todo aparezca a la vez.

# Esperar solo 0.5s a que el bus de sesión esté disponible
i=0
while [ "$i" -lt 5 ]; do
    if [ -n "$DBUS_SESSION_BUS_ADDRESS" ] || [ -S "/run/user/$(id -u)/bus" ]; then
        break
    fi
    i=$((i + 1))
    sleep 0.1
done

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -S "/run/user/$(id -u)/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    export DBUS_SESSION_BUS_ADDRESS
fi

# Lanzar TODOS los procesos SIMULTÁNEAMENTE (sin esperar entre ellos)
pgrep -x plank >/dev/null 2>&1 || setsid plank >/dev/null 2>&1 &
pgrep -x nm-applet >/dev/null 2>&1 || setsid nm-applet >/dev/null 2>&1 &
pgrep -x blueman-applet >/dev/null 2>&1 || setsid blueman-applet >/dev/null 2>&1 &
pgrep -x xfce4-panel >/dev/null 2>&1 || setsid xfce4-panel >/dev/null 2>&1 &
pgrep -x xfdesktop >/dev/null 2>&1 || setsid xfdesktop >/dev/null 2>&1 &

exit 0
SEOF
    sudo chmod 0755 "$script"

    # Fichero propio: el 99-macos-greeter.conf es del wallpaper (lightdm_aplicar_fondo)
    local dropin="/etc/lightdm/lightdm.conf.d/98-macos-dock.conf"
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    printf '[Seat:*]\nsession-setup-script=%s\n' "$script" | sudo tee "$dropin" >/dev/null
    # Limpiar la copia vieja que quedo en el 99 (si la hubiera)
    sudo sed -i '/^session-setup-script=/d' /etc/lightdm/lightdm.conf.d/99-macos-greeter.conf 2>/dev/null || true

    info "Dock adelantado al inicio de sesion (session-setup-script)"

    # ── Anular los autostart del sistema que causan duplicados ──
    # /etc/xdg/autostart/nm-applet.desktop y /etc/xdg/autostart/blueman.desktop
    # lanzan estos procesos al arrancar la sesión, pero como ya los lanza el
    # session-setup-script, se duplican. Se crean archivos del usuario con
    # Hidden=true para anularlos.
    mkdir -p "$HOME/.config/autostart"
    cat > "$HOME/.config/autostart/nm-applet.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NetworkManager Applet
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    cat > "$HOME/.config/autostart/blueman.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth Manager
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    info "Autostart del sistema anulados (sin duplicados)"
}

lightdm_fondo() {
    step "Descargando y aplicando wallpaper"
    local url="https://github.com/vinceliuice/WhiteSur-wallpapers/blob/main/4k/WhiteSur.jpg?raw=true"
    local destino="$HOME/Pictures/ventura-wallpapers/fondo.jpg"
    mkdir -p "$HOME/Pictures/ventura-wallpapers"
    
    # Intentar descargar el wallpaper con mejor manejo de errores
    if curl -sS -L --max-time 30 --retry 3 -o "$destino" "$url"; then
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
    # Forzar cierre de xfdesktop como root y usuario para evitar procesos huérfanos
    sudo pkill -9 xfdesktop 2>/dev/null || true
    pkill -9 xfdesktop 2>/dev/null || true
    sleep 2
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
            xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 5       2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/image-show"            --create -t bool   -s true     2>/dev/null || true
            xfconf-query -c xfce4-desktop -p "${base}/color-style"           --create -t int    -s 1       2>/dev/null || true
        done
    done

    # Configurar monitor0 específicamente como fallback universal
    for ws in 0 1 2 3 4 5 6 7 8 9; do
        local base="/backdrop/screen0/monitor0/workspace${ws}"
        xfconf-query -c xfce4-desktop -p "${base}/last-image"            --create -t string -s "$fondo" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "${base}/image-style"           --create -t int    -s 5       2>/dev/null || true
        xfconf-query -c xfce4-desktop -p "${base}/image-show"            --create -t bool   -s true     2>/dev/null || true
    done

    # También sobre cualquier propiedad existente de imagen
    for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|image-path|last-single-image"); do
        xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" 2>/dev/null || true
    done
    for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep image-style); do
        xfconf-query -c xfce4-desktop -p "$ruta" -s 5 2>/dev/null || true
    done

    info "Fondo aplicado a todos los monitores y workspaces"

    xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICONOS" 2>/dev/null || true
    aplicar_iconos_persistente "$ICONOS"
    # Reiniciar xfdesktop como el usuario actual con DISPLAY correcta
    export DISPLAY="${DISPLAY:-:0}"
    setsid xfdesktop --display="$DISPLAY" >/dev/null 2>&1 &
    disown
    sleep 3
    info "Fondo de pantalla aplicado"

    sudo mkdir -p /usr/share/backgrounds/linuxmint
    sudo cp "$fondo" /usr/share/backgrounds/linuxmint/macos-login.jpg
    sudo tee /etc/lightdm/slick-greeter.conf >/dev/null << 'SEOF'
[Greeter]
# brand=no quita el texto "Linux Mint" de la esquina y show-hostname=false el
# nombre del equipo: la pantalla de inicio sin una sola palabra.
brand=no
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
# OJO: en slick-greeter 2.2.6+zena la clave NO es "user-background" (esa no la
# conoce y se ignora en silencio). La buena es "draw-user-backgrounds", y su
# valor por defecto es TRUE: el greeter intenta pintar el ULTIMO FONDO DEL
# USUARIO. Como el lo lanza el usuario `lightdm` y /home/natalia es 750, no
# puede leerlo, se cae la imagen y sale background-color, que por defecto es
# #000000 -> login en NEGRO. Con esto en false se usa el `background` de arriba,
# que vive en /usr/share y puede leer cualquiera.
draw-user-backgrounds=false
background-color=#1c1c1e
draw-grid=false
show-hostname=false
show-power=true
show-a11y=true
SEOF
    # El greeter lo arranca lightdm con el usuario `lightdm` (home
    # /var/lib/lightdm), NO como root: por eso /root/.config no lo leia nunca
    # y /home/natalia/.config tampoco. El que manda es
    # /etc/lightdm/slick-greeter.conf (de arriba); este de aqui es por si
    # arrancara como otro usuario.
    local home_greeter
    home_greeter=$(getent passwd lightdm 2>/dev/null | cut -d: -f6)
    [ -n "$home_greeter" ] && [ -d "$home_greeter" ] || home_greeter=/var/lib/lightdm
    sudo mkdir -p "$home_greeter/.config"
    sudo tee "$home_greeter/.config/slick-greeter.conf" >/dev/null << 'SEOF'
[Greeter]
brand=no
show-hostname=false
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
draw-user-backgrounds=false
background-color=#1c1c1e
draw-grid=false
SEOF
    # También en el usuario, por si el greeter se llega a lanzar como usuario
    # (lightdm --test-mode): es inofensivo y cubre ese caso.
    cat > "$HOME/.config/slick-greeter.conf" << 'SEOF'
[Greeter]
brand=no
show-hostname=false
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
draw-user-backgrounds=false
background-color=#1c1c1e
draw-grid=false
SEOF
    # El greeter fijo en 99: gana a 60-lightdm-gtk-greeter y 90-slick-greeter,
    # asi la pantalla de inicio no cambia sola al actualizar paquetes.
    # OJO: se TOCA solo la linea del greeter, no se reescribe el fichero entero.
    # Con un `tee` completo se borraban los demas ajustes registrados ahi
    # (pantalla encendida y dock temprano), que viven ahora en 98-macos-*.conf.
    local dropin99="/etc/lightdm/lightdm.conf.d/99-macos-greeter.conf"
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    sudo touch "$dropin99"
    sudo sed -i '/^greeter-session=/d' "$dropin99"
    grep -q '^\[Seat:\*\]' "$dropin99" 2>/dev/null || printf '[Seat:*]\n' | sudo tee -a "$dropin99" >/dev/null
    printf 'greeter-session=slick-greeter\n' | sudo tee -a "$dropin99" >/dev/null
    sudo mkdir -p /etc/lightdm/lightdm-gtk-greeter.conf.d
    sudo tee /etc/lightdm/lightdm-gtk-greeter.conf.d/99_linuxmint.conf >/dev/null << 'SEOF'
[Greeter]
background=/usr/share/backgrounds/linuxmint/macos-login.jpg
draw-user-backgrounds=false
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
