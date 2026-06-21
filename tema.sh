#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

tema_instalar_whitesur() {
    local color=$1
    cd ~/WhiteSur-gtk-theme
    sudo ./install.sh -t default -c "$color" -l 2>/dev/null | grep -v "^$" || true
    local origen="/usr/share/themes/WhiteSur-${color}"
    local destino="$HOME/.themes/WhiteSur-${color}"
    if [ -d "$origen" ]; then
        mkdir -p "$destino"
        cp -r "$origen/." "$destino/"
        info "WhiteSur-${color} copiado a ~/.themes"
    else
        warn "WhiteSur-${color} no encontrado en /usr/share/themes"
    fi
    cd ~
}

tema_dependencias() {
    step "Instalando dependencias"
    apt_silencioso update
    apt_silencioso install git meson ninja-build plank konsole sassc \
        libgtk-3-dev libglib2.0-dev libwnck-3-dev xterm \
        libxcb-xinerama0 libxcb-xinerama0-dev curl unzip dconf-cli \
        libev-dev libconfig-dev libpcre2-dev libxext-dev libxdamage-dev \
        libdrm-dev libgl1-mesa-dev libdbus-1-dev libxcb-composite0-dev \
        libxcb-damage0-dev libxcb-glx0-dev libxcb-image0-dev \
        libxcb-present-dev libxcb-randr0-dev libxcb-render-util0-dev \
        libxcb-shape0-dev libxcb-util-dev libxcb-xfixes0-dev libx11-xcb-dev \
        uthash-dev network-manager-gnome
    info "Dependencias instaladas"
}

tema_instalar() {
    step "Instalando tema WhiteSur GTK"
    cd ~
    verificar_clon "WhiteSur-gtk-theme" "https://github.com/vinceliuice/WhiteSur-gtk-theme.git"
    tema_instalar_whitesur "Light"
    tema_instalar_whitesur "Dark"
    info "Temas instalados:"; ls ~/.themes/ | grep WhiteSur
    cd ~
}

tema_gtk_repo() {
    step "Instalando temas GTK desde el repo"
    mkdir -p ~/.themes
    cp ~/ventura-xfce/gtk/gtkthemes/*.tar.xz ~/.themes/ 2>/dev/null || true
    cd ~/.themes
    tar -xf WhiteSur-Light.tar.xz 2>/dev/null || true
    tar -xf WhiteSur-Dark.tar.xz  2>/dev/null || true
    cd ~/ventura-xfce
}

tema_iconos() {
    step "Instalando iconos y cursores"
    mkdir -p ~/.icons
    cp ~/ventura-xfce/gtk/icons/*.tar.xz ~/.icons/ 2>/dev/null || true
    cd ~/.icons
    tar -xf 01-WhiteSur.tar.xz      2>/dev/null || true
    tar -xf custom.tar.xz            2>/dev/null || true
    tar -xf WhiteSur-cursors.tar.xz  2>/dev/null || true
    cd ~/ventura-xfce
    gtk-update-icon-cache -f -t ~/.icons/"$ICONOS" 2>/dev/null || true

    # ── Aplicar cursor a nivel X11 ──────────────────────────────────────────
    # Sin esto el cursor solo cambia en apps GTK pero no en el escritorio/X11.
    # ~/.icons/default/index.theme es el mecanismo estándar que lee el servidor X.
    mkdir -p ~/.icons/default
    printf '[Icon Theme]\nInherits=WhiteSur-cursors\n' > ~/.icons/default/index.theme

    # También vía update-alternatives si está disponible (Debian/Ubuntu)
    if update-alternatives --list x-cursor-theme &>/dev/null 2>&1; then
        local cursor_path=""
        for p in ~/.icons/WhiteSur-cursors /usr/share/icons/WhiteSur-cursors; do
            [ -f "$p/index.theme" ] && cursor_path="$p/index.theme" && break
        done
        if [ -n "$cursor_path" ]; then
            sudo update-alternatives --install /usr/share/icons/default/index.theme \
                x-cursor-theme "$cursor_path" 50 2>/dev/null || true
            sudo update-alternatives --set x-cursor-theme "$cursor_path" 2>/dev/null || true
        fi
    fi

    # XCURSOR_THEME para sesiones X que no leen xfconf
    grep -q 'XCURSOR_THEME' ~/.profile 2>/dev/null || \
        echo 'export XCURSOR_THEME=WhiteSur-cursors' >> ~/.profile
    grep -q 'XCURSOR_THEME' ~/.xprofile 2>/dev/null || \
        echo 'export XCURSOR_THEME=WhiteSur-cursors' >> ~/.xprofile

    info "Iconos y cursor instalados"
}

tema_fuentes() {
    step "Instalando fuentes"
    cd ~
    apt_silencioso install fonts-inter || (
        curl -L -o /tmp/inter.zip "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
        unzip /tmp/inter.zip -d /tmp/inter
        sudo mkdir -p /usr/share/fonts/Inter
        sudo find /tmp/inter -name "*.ttf" -exec cp {} /usr/share/fonts/Inter/ \;
    )
    sudo fc-cache -f -v
    mkdir -p ~/.local/share/fonts/MesloLGS
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Regular.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Bold.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Italic.ttf
    curl -fL "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf" -o ~/.local/share/fonts/MesloLGS/MesloLGS_NF_Bold_Italic.ttf
    fc-cache -fv
    info "Fuentes instaladas"
}

tema_aplicar() {
    step "Aplicando temas GTK y XFWM"
    asegurar_xfconfd
    sleep 2
    xfconf-query -c xsettings -p /Net/ThemeName       -s "$TEMA"
    xfconf-query -c xsettings -p /Net/IconThemeName   -s "$ICONOS"
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "WhiteSur-cursors"
    xfconf-query -c xsettings -p /Gtk/FontName        -s "Inter 11"
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0
    printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-cursor-theme-name=WhiteSur-cursors\ngtk-font-name=Inter 11\n' \
        "$TEMA" "$ICONOS" > ~/.config/gtk-3.0/settings.ini
    printf '[Settings]\ngtk-theme-name=%s\ngtk-icon-theme-name=%s\ngtk-cursor-theme-name=WhiteSur-cursors\ngtk-font-name=Inter 11\n' \
        "$TEMA" "$ICONOS" > ~/.config/gtk-4.0/settings.ini
    aplicar_iconos_persistente "$ICONOS"
    [ "$MODO" = "dark" ] && aplicar_modo_oscuro
    info "Tema GTK aplicado: $TEMA / Iconos: $ICONOS"
}

tema_xfwm() {
    step "Instalando decoraciones XFWM"
    local xfwm_src="$HOME/WhiteSur-gtk-theme"
    mkdir -p "$HOME/.themes/WhiteSur-Light/xfwm4" "$HOME/.themes/WhiteSur-Dark/xfwm4"
    for color in Light Dark; do
        local origen="/usr/share/themes/WhiteSur-${color}/xfwm4"
        local destino="$HOME/.themes/WhiteSur-${color}/xfwm4"
        if [ -d "$origen" ]; then
            mkdir -p "$destino"; cp -r "$origen/." "$destino/"
        elif [ -d "$xfwm_src/src/other/xfwm4/WhiteSur-${color}" ]; then
            mkdir -p "$destino"; cp -r "$xfwm_src/src/other/xfwm4/WhiteSur-${color}/." "$destino/"
        elif [ -d "$xfwm_src/src/other/xfwm4" ]; then
            mkdir -p "$destino"; cp -r "$xfwm_src/src/other/xfwm4/." "$destino/"
        fi
        local origen_completo="/usr/share/themes/WhiteSur-${color}"
        local destino_completo="$HOME/.themes/WhiteSur-${color}"
        if [ -d "$origen_completo" ]; then
            mkdir -p "$destino_completo"
            cp -r "$origen_completo/." "$destino_completo/"
        fi
    done
    info "Decoraciones XFWM copiadas"
    if [ -d "$HOME/ventura-xfce/gtk/xfwm4" ]; then
        for d in "$HOME/ventura-xfce/gtk/xfwm4"/*/; do
            local nombre; nombre=$(basename "$d")
            mkdir -p "$HOME/.themes/$nombre/xfwm4"
            cp -r "$d." "$HOME/.themes/$nombre/xfwm4/"
        done
        info "xfwm4 extra copiado desde ventura-xfce"
    fi
    xfconf-query -c xfwm4 -p /general/theme            -s "$TEMA_XFWM"
    xfconf-query -c xfwm4 -p /general/title_alignment  -s "center"
    xfconf-query -c xfwm4 -p /general/button_layout    -s "CMH|"
    xfconf-query -c xfwm4 -p /general/show_dock_shadow -s false
    local xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
    mkdir -p "$(dirname "$xml")"
    cat > "$xml" << XFWMEOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="${TEMA_XFWM}"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="button_layout" type="string" value="CMH|"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="inactive_opacity" type="int" value="100"/>
  </property>
</channel>
XFWMEOF
    info "xfwm4 configurado: $TEMA_XFWM"
    local dir_tema="$HOME/.themes/$TEMA_XFWM/xfwm4"
    if [ ! -d "$dir_tema" ] || [ -z "$(ls -A "$dir_tema" 2>/dev/null)" ]; then
        local dir_sistema="/usr/share/themes/$TEMA_XFWM/xfwm4"
        if [ -d "$dir_sistema" ]; then
            mkdir -p "$dir_tema"; cp -r "$dir_sistema/." "$dir_tema/"
            info "xfwm4 recuperado desde /usr/share/themes"
        else
            warn "No se encontraron decoraciones xfwm4 para $TEMA_XFWM"
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; TEMA_XFWM="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; TEMA_XFWM="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA TEMA_XFWM ICONOS

    paso="${2:-todo}"
    case "$paso" in
        dependencias) tema_dependencias ;;
        instalar)     tema_instalar ;;
        gtk-repo)     tema_gtk_repo ;;
        iconos)       tema_iconos ;;
        fuentes)      tema_fuentes ;;
        aplicar)      tema_aplicar ;;
        xfwm)         tema_xfwm ;;
        todo)
            tema_dependencias
            tema_instalar
            tema_gtk_repo
            tema_iconos
            tema_fuentes
            tema_aplicar
            tema_xfwm
            ;;
    esac
fi
