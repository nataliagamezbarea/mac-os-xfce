#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

echo -e "\n=== Instalador macOS Ventura XFCE ==="
if [ -t 0 ]; then
    read -p "¿Qué modo quieres? (light/dark): " MODO </dev/tty
fi
MODO="${MODO:-dark}"
MODO=$(echo "$MODO" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

ARCHIVO_LOG="$PWD/instalacion.log"
echo "===== Instalación iniciada: $(date) =====" | tee "$ARCHIVO_LOG"
echo "Modo: $MODO" | tee -a "$ARCHIVO_LOG"
exec >> "$ARCHIVO_LOG" 2>&1

info "Se pedirá la contraseña una sola vez para todo el proceso"
if [ -t 0 ]; then
    sudo -v
else
    askpass=$(mktemp)
    cat > "$askpass" << 'ASKEOL'
#!/bin/bash
zenity --password --title="Contraseña sudo" 2>/dev/null
ASKEOL
    chmod +x "$askpass"
    SUDO_ASKPASS="$askpass" sudo -A true 2>/dev/null || true
    rm -f "$askpass"
fi
if sudo -n true 2>/dev/null; then
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    PID_SUDO=$!
    trap 'kill $PID_SUDO 2>/dev/null || true' EXIT
fi

step "1/9 Limpiando sesión XFCE y archivos previos"
pkill -9 xfce4-panel 2>/dev/null || true
pkill -9 xfconfd      2>/dev/null || true
pkill -9 plank        2>/dev/null || true
sleep 3

rm -rf ~/.config/xfce4
rm -rf ~/.config/xfce4-dict
rm -rf ~/.cache/xfce4
rm -rf ~/.cache/sessions
rm -rf ~/.icons/WhiteSur* ~/.icons/custom
rm -rf ~/.themes/WhiteSur*


bash "$DIR/aplicaciones.sh" "$MODO" appmenu

bash "$DIR/tema.sh" "$MODO" dependencias

bash "$DIR/tema.sh" "$MODO" instalar

step "Clonando repositorio ventura-xfce"
verificar_clon "ventura-xfce" "https://github.com/ibm-7094a/ventura-xfce"
info "Repositorio clonado"

bash "$DIR/aplicaciones.sh" "$MODO" ulauncher

bash "$DIR/nautilus.sh" "$MODO" configurar

bash "$DIR/nautilus.sh" "$MODO" ocultar

bash "$DIR/nautilus_panel.sh" "$MODO" atajos

bash "$DIR/nautilus_panel.sh" "$MODO" abrir_con

bash "$DIR/nautilus.sh" "$MODO" extension

bash "$DIR/tema.sh" "$MODO" gtk-repo

bash "$DIR/tema.sh" "$MODO" iconos

bash "$DIR/tema.sh" "$MODO" fuentes

bash "$DIR/panel.sh" "$MODO" configurar

bash "$DIR/panel.sh" "$MODO" plank

bash "$DIR/aplicaciones.sh" "$MODO" picom

bash "$DIR/tema.sh" "$MODO" aplicar

bash "$DIR/tema.sh" "$MODO" xfwm

bash "$DIR/terminal.sh" "$MODO" konsole

bash "$DIR/terminal.sh" "$MODO" default

bash "$DIR/terminal.sh" "$MODO" zsh

bash "$DIR/aplicaciones.sh" "$MODO" autostart

bash "$DIR/lightdm.sh" "$MODO" lightdm

bash "$DIR/lightdm.sh" "$MODO" wallpaper

bash "$DIR/panel.sh" "$MODO" reiniciar

bash "$DIR/final.sh" "$MODO" recargar

bash "$DIR/nautilus.sh" "$MODO" relanzar

# Asegurar que ningún separador del panel se expanda
source "$DIR/comun.sh"
source "$DIR/panel.sh"
_panel_expand_false "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"

bash "$DIR/final.sh" "$MODO" resumen
