#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

panel_plank() {
    step "Configurando Plank"
    pkill -9 plank 2>/dev/null || true
    sleep 1

    local tema_origen="$HOME/ventura-xfce/dock/plank/Ventura"
    local tema_destino="$HOME/.local/share/plank/themes/Ventura"
    mkdir -p "$HOME/.local/share/plank/themes"
    if [ -d "$tema_origen" ]; then
        cp -r "$tema_origen" "$tema_destino"
    else
        mkdir -p "$tema_destino"
        cat > "$tema_destino/dock.theme" << 'EOF'
[PlankTheme]
TopRoundness=4
BottomRoundness=0
LineWidth=1
OuterStrokeColor=40;;40;;40;;180
FillStartColor=255;;255;;255;;25
FillEndColor=255;;255;;255;;25
InnerStrokeColor=255;;255;;255;;35
EOF
        info "Tema Ventura generado manualmente"
    fi

    local trans_destino="$HOME/.local/share/plank/themes/Transparent"
    mkdir -p "$trans_destino"
    cat > "$trans_destino/dock.theme" << 'EOF'
[PlankTheme]
TopRoundness=0
BottomRoundness=0
LineWidth=0
OuterStrokeColor=0;;0;;0;;0
FillStartColor=0;;0;;0;;0
FillEndColor=0;;0;;0;;0
InnerStrokeColor=0;;0;;0;;0
EOF

    local lanzadores_origen="$HOME/ventura-xfce/dock/launchers"
    local lanzadores_destino="$HOME/.config/plank/dock1/launchers"
    mkdir -p "$lanzadores_destino"
    rm -f "$lanzadores_destino"/*.dockitem
    local permitidos=("safari" "finder" "mail" "music" "notes" "photos" "Calc" "pages" "settings")
    if [ -d "$lanzadores_origen" ]; then
        for archivo in "$lanzadores_origen"/*.desktop; do
            local base; base=$(basename "$archivo" .desktop)
            local permitido=0
            for p in "${permitidos[@]}"; do
                [ "$p" = "$base" ] && permitido=1 && break
            done
            [ "$permitido" = "0" ] && continue
            local dockitem="$lanzadores_destino/${base}.dockitem"
            local sistema=""
            for ruta in "/usr/share/applications/${base}.desktop" \
                        "/usr/local/share/applications/${base}.desktop" \
                        "$HOME/.local/share/applications/${base}.desktop"; do
                [ -f "$ruta" ] && sistema="$ruta" && break
            done
            if [ -z "$sistema" ]; then
                cp "$archivo" "$HOME/.local/share/applications/${base}.desktop"
                sistema="$HOME/.local/share/applications/${base}.desktop"
            fi
            sed -i "s|lukas|$USER|g; s|ibm-7094a|$USER|g; s|ibm-7094|$USER|g" "$sistema" 2>/dev/null || true
            printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$sistema" > "$dockitem"
        done
        find "$lanzadores_destino" -name "*.dockitem" -exec \
            sed -i "s|/home/lukas/|/home/$USER/|g; s|/home/ibm-7094a/|/home/$USER/|g; s|/home/ibm-7094/|/home/$USER/|g" {} \; 2>/dev/null || true
        local cantidad; cantidad=$(ls "$lanzadores_destino"/*.dockitem 2>/dev/null | wc -l)
        info "Lanzadores creados: $cantidad"
    else
        warn "Carpeta de lanzadores no encontrada"
    fi

    local schema="net.launchpad.plank.dock.settings:/net/launchpad/plank/docks/dock1/"
    local dconf_path="/net/launchpad/plank/docks/dock1"
    gsettings set "$schema" theme               'Ventura'     2>/dev/null || true; sleep 0.5
    gsettings set "$schema" theme               'Transparent' 2>/dev/null || true
    gsettings set "$schema" position            'bottom'      2>/dev/null || true
    gsettings set "$schema" alignment           'center'      2>/dev/null || true
    gsettings set "$schema" icon-size           48            2>/dev/null || true
    gsettings set "$schema" zoom-enabled        true          2>/dev/null || true
    gsettings set "$schema" zoom-percent        150           2>/dev/null || true
    gsettings set "$schema" hide-mode           'window-dodge' 2>/dev/null || true
    gsettings set "$schema" show-dock-item      false         2>/dev/null || true
    gsettings set "$schema" lock-items          false         2>/dev/null || true

    if command -v dconf &>/dev/null; then
        dconf write "${dconf_path}/theme"          "'Transparent'" 2>/dev/null || true
        dconf write "${dconf_path}/position"       "'bottom'"      2>/dev/null || true
        dconf write "${dconf_path}/alignment"      "'center'"      2>/dev/null || true
        dconf write "${dconf_path}/icon-size"      "48"            2>/dev/null || true
        dconf write "${dconf_path}/zoom-enabled"   "true"          2>/dev/null || true
        dconf write "${dconf_path}/zoom-percent"   "150"           2>/dev/null || true
        dconf write "${dconf_path}/hide-mode"      "'window-dodge'" 2>/dev/null || true
        dconf write "${dconf_path}/show-dock-item" "false"         2>/dev/null || true
        dconf write "${dconf_path}/lock-items"     "false"         2>/dev/null || true
    fi
    info "Plank configurado: Transparente, 48px, zoom 150%"

    nohup plank > /tmp/plank.log 2>&1 &
    sleep 2
    pgrep -x plank > /dev/null && info "Plank corriendo" || warn "Plank no arrancó"
}

panel_configurar() {
    step "Copiando configuración del panel XFCE"
    cp -r ~/ventura-xfce/config/xfce4 ~/.config/
    cp -r ~/ventura-xfce/config/xfce4-dict ~/.config/ 2>/dev/null || true
    chown -R "$USER:$USER" ~/.config/xfce4
    chown -R "$USER:$USER" ~/.config/xfce4-dict 2>/dev/null || true
    find ~/.config/xfce4 -type f -name "*.xml" -exec \
        sed -i "s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true

    find ~/.config/xfce4/panel -name "*.desktop" -exec \
    sed -i "s/lukas/$USER/g; s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true

    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    sed -i 's|<property name="expand" type="bool" value="true"/>|<property name="expand" type="bool" value="false"/>|g; s|<property name="expand" type="empty"/>|<property name="expand" type="bool" value="false"/>|g' "$panel_xml"
    sed -i 's|<property name="plugin-10" type="string" value="notification-plugin"/>|<property name="plugin-10" type="string" value="systray">\n      <property name="name-visible" type="bool" value="false"/>\n      <property name="square-icons" type="bool" value="false"/>\n      <property name="icon-size" type="int" value="0"/>\n    </property>|' "$panel_xml"
    sed -i '/<value type="int" value="19"\/>/d' "$panel_xml"
    sed -i '/<value type="int" value="21"\/>/d' "$panel_xml"
    sed -i '/<value type="int" value="10"\/>/d' "$panel_xml"
    grep -q '<value type="int" value="10"/>' "$panel_xml" || \
        sed -i '/<value type="int" value="22"\/>/a\        <value type="int" value="10"/>' "$panel_xml"
    _panel_remove_right_of_systray "$panel_xml"
    panel_systray_solo_wifi
    info "Configuración del panel copiada"
}

_panel_remove_right_of_systray() {
    local xml="$1"
    [ -f "$xml" ] || return

    local tmp="/tmp/panel_elim_$$.xml"
    local systray_id=""
    local in_ids=0
    local count=0
    local to_remove=""

    systray_id=$(grep -oP '(?<=<property name="plugin-)\d+(?=" type="string" value="systray")' "$xml" | head -1)
    [ -z "$systray_id" ] && { cp "$xml" "$tmp"; rm -f "$xml"; mv "$tmp" "$xml"; return; }

    while IFS= read -r line; do
        if echo "$line" | grep -q 'plugin-ids.*array'; then
            in_ids=1
            count=0
        fi
        if echo "$line" | grep -q '/property' && [ "$in_ids" -eq 1 ]; then
            in_ids=0
        fi

        if [ "$in_ids" -eq 1 ] && [ "$count" -gt 0 ] && [ "$count" -le 2 ]; then
            local pid=$(echo "$line" | grep -oP 'value="\K\d+(?="/>)')
            if [ -n "$pid" ]; then
                to_remove="$to_remove $pid"
                count=$((count + 1))
                continue
            fi
        fi

        if [ "$in_ids" -eq 1 ]; then
            local curr=$(echo "$line" | grep -oP 'value="\K\d+(?="/>)')
            if [ "$curr" = "$systray_id" ]; then
                count=$((count + 1))
            fi
        fi

        echo "$line" >> "$tmp"
    done < "$xml"

    for pid in $to_remove; do
        sed -i "/<value type=\"int\" value=\"$pid\"\/>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"separator\">/,/<\/property>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"launcher\">/,/<\/property>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"separator\"\/>/d" "$tmp"
        sed -i "/<property name=\"plugin-$pid\" type=\"string\" value=\"launcher\"\/>/d" "$tmp"
    done

    cp "$tmp" "$xml"
    rm -f "$tmp"
}

panel_systray_solo_wifi() {
    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    [ -f "$panel_xml" ] || { warn "panel.xml no encontrado"; return; }

    sed -i '/<property name="hidden-legacy-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="hidden-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="known-legacy-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="known-items" type="array">/,/<\/property>/d' "$panel_xml"
    sed -i '/<property name="hidden-sni-items" type="array">/,/<\/property>/d' "$panel_xml"

    local new_plugin10='    <property name="plugin-10" type="string" value="systray">
      <property name="name-visible" type="bool" value="false"/>
      <property name="square-icons" type="bool" value="false"/>
      <property name="icon-size" type="int" value="0"/>
      <property name="hidden-legacy-items" type="array">
        <value type="string" value="mintupdate.py"/>
        <value type="string" value="tray.py"/>
        <value type="string" value="applet.py"/>
        <value type="string" value="blueman-tray"/>
        <value type="string" value="blueman-applet"/>
        <value type="string" value="blueman applet"/>
        <value type="string" value="Blueman Applet"/>
        <value type="string" value="clipman"/>
      </property>
      <property name="hidden-items" type="array">
        <value type="string" value="mintupdate.py"/>
        <value type="string" value="tray.py"/>
        <value type="string" value="applet.py"/>
        <value type="string" value="blueman-tray"/>
        <value type="string" value="blueman-applet"/>
        <value type="string" value="blueman applet"/>
        <value type="string" value="Blueman Applet"/>
        <value type="string" value="clipman"/>
      </property>
      <property name="known-legacy-items" type="array">
        <value type="string" value="miniaplicación gestor de la red"/>
      </property>
      <property name="known-items" type="array"/>
    </property>'

    local tmp="/tmp/panel_fix_$$.xml"
    local in_plugin10=0
    local depth=0

    while IFS= read -r line; do
        if echo "$line" | grep -q 'name="plugin-10".*systray'; then
            in_plugin10=1
            depth=0
            echo "$new_plugin10" >> "$tmp"
            continue
        fi

        if [ "$in_plugin10" -eq 1 ]; then
            local opens=$(echo "$line" | grep -c '<property ' || true)
            local scloses=$(echo "$line" | grep -c '/>' || true)
            local closes=$(echo "$line" | grep -c '</property>' || true)
            depth=$((depth + opens - scloses - closes))
            if [ "$depth" -le 0 ] && echo "$line" | grep -q '</property>'; then
                in_plugin10=0
            fi
            continue
        fi

        echo "$line" >> "$tmp"
    done < "$panel_xml"

    cp "$tmp" "$panel_xml"
    rm -f "$tmp"
    info "plugin-10 systray: arrays hidden OK"

    mkdir -p "$HOME/.config/autostart"
    if [ -f /etc/xdg/autostart/blueman.desktop ]; then
        cp -n /etc/xdg/autostart/blueman.desktop "$HOME/.config/autostart/" 2>/dev/null || true
    fi
    grep -q 'Hidden=true' "$HOME/.config/autostart/blueman.desktop" 2>/dev/null || \
        echo "Hidden=true" >> "$HOME/.config/autostart/blueman.desktop"

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate          2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true

    local systray_id
    systray_id=$(grep -oP '(?<=<property name="plugin-)\d+(?=" type="string" value="systray")' "$panel_xml" | head -1)
    if [ -n "$systray_id" ]; then
        local base="/plugins/plugin-${systray_id}"
        xfconf-query -c xfce4-panel -p "${base}/hidden-legacy-items" \
            --create --force-array \
            -t string -s "mintupdate.py" \
            -t string -s "tray.py" \
            -t string -s "applet.py" \
            -t string -s "blueman-tray" \
            -t string -s "blueman-applet" \
            -t string -s "blueman applet" \
            -t string -s "Blueman Applet" \
            -t string -s "clipman" \
            2>/dev/null || true
        xfconf-query -c xfce4-panel -p "${base}/hidden-items" \
            --create --force-array \
            -t string -s "mintupdate.py" \
            -t string -s "tray.py" \
            -t string -s "applet.py" \
            -t string -s "blueman-tray" \
            -t string -s "blueman-applet" \
            -t string -s "blueman applet" \
            -t string -s "Blueman Applet" \
            -t string -s "clipman" \
            2>/dev/null || true
        xfconf-query -c xfce4-panel -p "${base}/known-legacy-items" \
            --create --force-array \
            -t string -s "miniaplicación gestor de la red" \
            2>/dev/null || true
        info "Bandeja oculta (array) aplicada en systray plugin-${systray_id}"
    fi

    info "Bandeja: solo wifi visible"
}

panel_reiniciar() {
    local iconos="$1"; local tema_gtk="$2"; local tema_xfwm="$3"
    pkill -15 xfce4-panel 2>/dev/null || true; sleep 1
    pkill -9  xfce4-panel 2>/dev/null || true
    for i in $(seq 1 8); do pgrep -x xfce4-panel > /dev/null || break; sleep 1; done
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    rm -rf ~/.cache/xfce4 ~/.cache/sessions
    rm -f  /tmp/xfce4-panel-*.pid 2>/dev/null || true
    rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/xfce4-panel"* 2>/dev/null || true
    asegurar_xfconfd; sleep 2

    xfconf-query -c xsettings -p /Net/ThemeName       -s "$tema_gtk"   || true
    xfconf-query -c xsettings -p /Net/IconThemeName   -s "$iconos"     || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeName -s "WhiteSur-cursors" || true
    xfconf-query -c xsettings -p /Gtk/FontName        -s "Inter 11"    || true
    xfconf-query -c xfwm4 -p /general/theme           -s "$tema_xfwm"  || true
    xfconf-query -c xfwm4 -p /general/button_layout   -s "CMH|"        || true

    aplicar_iconos_persistente "$iconos"
    [ "$MODO" = "dark" ] && aplicar_modo_oscuro
    gtk-update-icon-cache -f -t "$HOME/.icons/$iconos" 2>/dev/null || true

    local panel_xml="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    cp ~/ventura-xfce/config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml "$panel_xml"
    sed -i 's|<property name="expand" type="bool" value="true"/>|<property name="expand" type="bool" value="false"/>|g; s|<property name="expand" type="empty"/>|<property name="expand" type="bool" value="false"/>|g' "$panel_xml"
    sed -i 's|<property name="plugin-10" type="string" value="notification-plugin"/>|<property name="plugin-10" type="string" value="systray">\n      <property name="name-visible" type="bool" value="false"/>\n      <property name="square-icons" type="bool" value="false"/>\n      <property name="icon-size" type="int" value="0"/>\n    </property>|' "$panel_xml"
    sed -i '/<value type="int" value="19"\/>/d' "$panel_xml"
    sed -i '/<value type="int" value="21"\/>/d' "$panel_xml"
    sed -i '/<value type="int" value="10"\/>/d' "$panel_xml"
    grep -q '<value type="int" value="10"/>' "$panel_xml" || \
        sed -i '/<value type="int" value="22"\/>/a\        <value type="int" value="10"/>' "$panel_xml"
    _panel_remove_right_of_systray "$panel_xml"
    if [ -d ~/ventura-xfce/config/xfce4/panel ]; then
        cp -r ~/ventura-xfce/config/xfce4/panel/launcher-* ~/.config/xfce4/panel/ 2>/dev/null || true
        find ~/.config/xfce4/panel -name "*.desktop" -exec \
            sed -i "s/lukas/$USER/g; s/ibm-7094a/$USER/g; s/ibm-7094/$USER/g" {} \; 2>/dev/null || true
        local n_launchers
        n_launchers=$(ls -d ~/.config/xfce4/panel/launcher-* 2>/dev/null | wc -l)
        info "Launchers del panel restaurados: $n_launchers"
    else
        warn "Carpeta de launchers del repo no encontrada — los iconos del panel pueden faltar"
    fi
    panel_systray_solo_wifi
    grep -q 'reserve-space' "$panel_xml" 2>/dev/null || \
        sed -i '/<property name="position-locked" type="bool" value="true"\/>/a\      <property name="reserve-space" type="bool" value="true"/>' "$panel_xml"
    asegurar_xfconfd

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate          2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true
    sleep 1

    DISPLAY="${DISPLAY:-:0}" xfce4-panel & sleep 4
    if ! pgrep -x xfce4-panel > /dev/null; then
        DISPLAY="${DISPLAY:-:0}" xfce4-panel & sleep 3
    fi
    pgrep -x xfce4-panel > /dev/null && info "Panel reiniciado" || warn "El panel no arrancó"
    for i in 1 2 3; do
        sleep 2
        pkill -9 xfconfd 2>/dev/null || true; sleep 1
        panel_systray_solo_wifi
        sed -i 's|<property name="expand" type="bool" value="true"/>|<property name="expand" type="bool" value="false"/>|g; s|<property name="expand" type="empty"/>|<property name="expand" type="bool" value="false"/>|g' "$panel_xml"
        asegurar_xfconfd
    done
    sleep 2
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    pkill -15 xfce4-panel 2>/dev/null || true; sleep 2
    pkill -9  xfce4-panel 2>/dev/null || true
    for i in $(seq 1 8); do pgrep -x xfce4-panel > /dev/null || break; sleep 1; done
    asegurar_xfconfd
    DISPLAY="${DISPLAY:-:0}" xfce4-panel & sleep 3

    pkill -f mintUpdate          2>/dev/null || true
    pkill -f mintupdate-launcher 2>/dev/null || true
    pkill -f applet.py           2>/dev/null || true
    pkill -f tray.py             2>/dev/null || true
    pkill -f blueman-tray        2>/dev/null || true

    pkill -9 xfdesktop 2>/dev/null || true; sleep 2
    xfconf-query -c xsettings -p /Net/IconThemeName -s "$iconos" || true
    aplicar_iconos_persistente "$iconos"

    local xml_escritorio="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml"
    if [ -f "$xml_escritorio" ]; then
        local fondo; fondo=$(grep -oP '(?<=value=")[^"]+\.(jpg|png|jpeg|webp)(?=")' "$xml_escritorio" | head -1)
        if [ -n "$fondo" ] && [ -s "$fondo" ]; then
            for ruta in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E "last-image|last-single-image|image-path"); do
                xfconf-query -c xfce4-desktop -p "$ruta" -s "$fondo" --create -t string 2>/dev/null || true
            done
        fi
    fi
    sleep 2; DISPLAY="${DISPLAY:-:0}" xfdesktop & sleep 2
    sleep 3
    pkill -9 xfconfd 2>/dev/null || true; sleep 1
    sed -i 's|<property name="expand" type="bool" value="true"/>|<property name="expand" type="bool" value="false"/>|g; s|<property name="expand" type="empty"/>|<property name="expand" type="bool" value="false"/>|g' "$panel_xml"
    asegurar_xfconfd
    info "Panel y escritorio reiniciados"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; TEMA_XFWM="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; TEMA_XFWM="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA TEMA_XFWM ICONOS

    paso="${2:-todo}"
    case "$paso" in
        config|configurar)    panel_configurar ;;
        plank)     panel_plank ;;
        reiniciar) panel_reiniciar "$ICONOS" "$TEMA" "$TEMA_XFWM" ;;
        todo)
            panel_configurar
            panel_plank
            panel_reiniciar "$ICONOS" "$TEMA" "$TEMA_XFWM"
            ;;
    esac
fi
