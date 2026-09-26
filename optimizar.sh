#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

# Redefinir funciones con output simple (sin colores ni unicode)
step() { echo "==> $1"; }
info() { echo "  + $1"; }
warn() { echo "  - $1"; }

optimizar_systemd() {
    step "Optimizando servicios del sistema"

    local sugerencias=(
        "ModemManager.service:Modulem 4G/5G (si no usas datos moviles)"
        "cups.service:Impresion (si no tienes impresora)"
        "avahi-daemon.service:Avahi (descubrimiento mDNS/Zeroconf)"
        "cups-browsed.service:Deteccion automatica de impresoras"
    )

    for sugerencia in "${sugerencias[@]}"; do
        local unidad="${sugerencia%%:*}"
        local desc="${sugerencia#*:}"

        if systemctl is-enabled "$unidad" &>/dev/null 2>&1; then
            sudo systemctl disable "$unidad" 2>/dev/null || true
            sudo systemctl stop "$unidad" 2>/dev/null || true
            info "$unidad desactivado"
        fi
    done
}

optimizar_autostart() {
    step "Optimizando autostart (menos espera al iniciar sesion)"

    local AUTOSTART="$HOME/.config/autostart"

    # ── Plank: se limpia la entrada antigua, nada más ──
    # OJO: aquí NO se pone X-XFCE-Autostart-Phase. Esa clave NO existe en este
    # XFCE (no está en xfce4-session ni en libxfce4util), así que es inerte:
    # Startup/Initialization/Default dan lo mismo. Meterla daba la impresión de
    # que Plank arrancaba antes y no era verdad. El arranque temprano se
    # resuelve con el cliente de sesión (ver aplicaciones.sh).
    local plank_auto="$AUTOSTART/00-plank.desktop"
    if [ ! -f "$plank_auto" ] && [ -f "$AUTOSTART/plank.desktop" ]; then
        mv -f "$AUTOSTART/plank.desktop" "$plank_auto" 2>/dev/null || true
    fi
    if [ -f "$plank_auto" ]; then
        sed -i '/^X-XFCE-Autostart-Phase=/d' "$plank_auto"
        sed -i 's/sleep [0-9]*/sleep 1/' "$plank_auto"
        # XFCE no expande "$HOME" ni "/home/USER/" en la línea Exec=.
        # Forzamos la ruta absoluta por si la entrada vieja traía "$HOME" literal
        # (causa habitual de que Plank no arranque al encender el PC).
        sed -i "s|\$HOME/|$HOME/|g; s|/home/USER/|$HOME/|g" "$plank_auto"
        info "plank: entrada de autostart limpia (sin fase inerte)"
    fi

    if [ -f "$AUTOSTART/ulauncher.desktop" ]; then
        sed -i 's/sleep [0-9]*/sleep 2/' "$AUTOSTART/ulauncher.desktop"
        info "ulauncher: sleep 2s"
    fi

    # Limpiar restos de versiones antiguas: este autostart relanzaba un segundo
    # xfdesktop en cada login y hacía "colapsar" el fondo/al escritorio al reiniciar.
    if [ -f "$AUTOSTART/xfdesktop-restart.desktop" ]; then
        warn "Eliminando xfdesktop-restart.desktop (causaba colapso del fondo)"
        rm -f "$AUTOSTART/xfdesktop-restart.desktop"
    fi

    # ── Miniaplicación de red (nm-applet): asegurar que arranca sola ──
    if [ -f "$AUTOSTART/nm-applet.desktop" ]; then
        sed -i 's/^Hidden=true/Hidden=false/; s/^X-GNOME-Autostart-enabled=false/X-GNOME-Autostart-enabled=true/' \
            "$AUTOSTART/nm-applet.desktop" 2>/dev/null || true
        info "nm-applet: autostart activado"
    fi
}

optimizar_kernel() {
    step "Ajustes de rendimiento del kernel"

    local sysctl_file="/etc/sysctl.d/90-desktop-performance.conf"
    local temp=$(mktemp)

    cat > "$temp" << 'SYSCTLEOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.numa_balancing=0
SYSCTLEOF

    if [ -f "$sysctl_file" ]; then
        if ! cmp -s "$temp" "$sysctl_file" 2>/dev/null; then
            sudo cp "$temp" "$sysctl_file"
            sudo sysctl --system &>/dev/null || true
            info "sysctl: swappiness=10, cache pressure=50"
        else
            info "sysctl ya optimizado"
        fi
    else
        sudo cp "$temp" "$sysctl_file"
        sudo sysctl --system &>/dev/null || true
        info "sysctl: swappiness=10, cache pressure=50"
    fi
    rm -f "$temp"
}

optimizar_preload() {
    step "Instalando preload (acelera apertura de apps)"

    if ! dpkg -l preload &>/dev/null 2>&1; then
        apt_silencioso install preload 2>/dev/null || true
        if dpkg -l preload &>/dev/null 2>&1; then
            sudo systemctl enable preload 2>/dev/null || true
            sudo systemctl start preload 2>/dev/null || true
            info "preload instalado"
        else
            warn "preload no disponible"
        fi
    else
        info "preload ya instalado"
    fi
}

optimizar_boot() {
    step "Acelerando arranque (GRUB en texto + GPU manager)"

    if systemctl is-enabled gpu-manager &>/dev/null 2>&1; then
        sudo systemctl disable gpu-manager.service 2>/dev/null || true
        sudo systemctl mask gpu-manager.service 2>/dev/null || true
        info "gpu-manager desactivado"
    else
        info "gpu-manager ya desactivado"
    fi

    # Restos del instalador de Live ISO: buscan un DVD y fallan en cada arranque
    local servicio
    for servicio in casper-md5check.service casper.service; do
        if systemctl is-enabled "$servicio" &>/dev/null 2>&1; then
            sudo systemctl mask "$servicio" 2>/dev/null || true
            info "$servicio oculto (resto del Live ISO, fallaba al arrancar)"
        fi
    done

    red_no_bloquea_el_login
    grub_pantalla_limpia
}

# La red se colaba en la ruta critica del arranque:
#   graphical.target <- multi-user.target <- mysql.service <- network.target
#                      <- NetworkManager.service
# MySQL traia "After=network.target" de serie y, como esta en multi-user.target,
# la pantalla de login no aparecia hasta que NetworkManager estaba listo. MySQL
# solo escucha en 127.0.0.1 (HeidiSQL en local), asi que no necesita la red: se
# arranca en paralelo con ella. VirtualBox (convertido por el generador sysv a
# partir de /etc/init.d/virtualbox) pedia network-online.target y se ponia
# delante de graphical.target: tambien salia de la cadena.
# OJO: en un drop-in NO vale vaciar After=/Before= (systemd no permite resetear
# esas listas), por eso se copian las unidades enteras a /etc/systemd/system,
# que tiene prioridad sobre /usr/lib y sobre el generador.
# Idempotente.
red_no_bloquea_el_login() {
    # ── VirtualBox: unidad propia (el generador sysv pedía la red) ──
    local unit_vbox="# Sustituye a la unidad que generaba systemd-sysv-generator desde
# /etc/init.d/virtualbox. Aquella pedia network-online.target y se metia por
# delante de graphical.target, asi que el login esperaba a la red y a la carga
# del modulo. Solo carga modulos del kernel: va en paralelo y no bloquea.
[Unit]
Description=VirtualBox Linux kernel module
After=local-fs.target
Before=multi-user.target

[Service]
Type=forking
RemainAfterExit=yes
ExecStart=/etc/init.d/virtualbox start
ExecStop=/etc/init.d/virtualbox stop
SuccessExitStatus=5 6

[Install]
WantedBy=multi-user.target"
    local dest_vbox="/etc/systemd/system/virtualbox.service"
    if [ -f "$dest_vbox" ] && grep -q "network-online" "$dest_vbox"; then
        info "VirtualBox ya no espera a la red"
    else
        printf '%s\n' "$unit_vbox" | sudo tee "$dest_vbox" >/dev/null
        info "VirtualBox fuera de la ruta del login (ya no espera la red)"
    fi

    # ── Cualquier otro servicio que espere a la red ──────────────────
    # MySQL (After=network.target) y Apache (After=network.target ...) se
    # colgaban de network.target y, como estan en multi-user.target, la red
    # entraba en la ruta critica: la pantalla de login no salia hasta que
    # NetworkManager estaba listo. Ninguno necesita la red para arrancar
    # (MySQL solo escucha en 127.0.0.1), asi que se les quita la espera.
    # OJO: en un drop-in NO vale vaciar After= (systemd no permite resetear
    # esa lista), por eso se copia la unidad entera a /etc/systemd/system, que
    # tiene prioridad sobre /usr/lib.
    local servicio frag dest cambiados=0
    for servicio in $(systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print $1}'); do
        case "$servicio" in
            # NetworkManager ES la red: no se toca. Tampoco los que esperan a
            # que la red este de verdad disponible ni los de VirtualBox.
            NetworkManager*|systemd-networkd*|systemd-resolved*|wait-for-network*|virtualbox.service) continue ;;
        esac
        systemctl show "$servicio" -p After --value 2>/dev/null | tr ' ' '\n' \
            | grep -qxE "network(-online)?\.target" || continue
        frag=$(systemctl show "$servicio" -p FragmentPath --value 2>/dev/null)
        [ -n "$frag" ] && [ -f "$frag" ] || continue
        dest="/etc/systemd/system/$servicio"
        sudo cp "$frag" "$dest"
        if sudo python3 - "$dest" << 'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
salida = []
for linea in p.read_text(errors="ignore").splitlines(keepends=True):
    if linea.startswith("After="):
        nuevos = [t for t in linea.split()[1:]
                  if t not in ("network.target", "network-online.target")]
        linea = ("# La red ya no bloquea el arranque: este servicio arranca en\n"
                 "# paralelo con NetworkManager en vez de esperar a que la red este\n"
                 "# lista. Antes la red estaba en la ruta critica y la pantalla de\n"
                 "# login no aparecia hasta que estaba arriba.\n"
                 "After=" + " ".join(nuevos or ["local-fs.target"]) + "\n")
    salida.append(linea)
p.write_text("".join(salida))
PY
        then
            cambiados=$((cambiados + 1))
            info "$servicio ya no espera a la red"
        fi
    done
    [ "$cambiados" -eq 0 ] && info "Ningún servicio espera a la red"

    sudo systemctl daemon-reload 2>/dev/null || true
}

# Arranque sin una sola linea de texto (lo tipico de Linux era ver
# [ OK ] / [ FAILED ] o directamente la pantalla negra).
# GRUB y el kernel se quedan en MODO TEXTO y mudos: sin Plymouth, sin
# 'splash', con 'quiet' y sin el estado de systemd. Todo lo que se
# imprimia sigue en el journal: journalctl -b / systemctl --failed.
# Idempotente: solo regenera el grub si algo cambio de verdad.
grub_pantalla_limpia() {
    local grub="/etc/default/grub"
    local cambiado=0
    local valor_actual valor_nuevo

    [ -f "$grub" ] || { warn "No existe $grub (arranque sin tocar)"; return 0; }

    # Respaldo (solo la primera vez)
    if ! ls /etc/default/grub.macos.* >/dev/null 2>&1; then
        sudo cp "$grub" "/etc/default/grub.macos.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    fi

    # 1) Quitar splash / plymouth (son los que dejan la pantalla en NEGRA al
    #    arrancar) y dejar el arranque COMPLETAMENTE MUDo: sin una sola linea.
    #       quiet                  -> el kernel no imprime nada
    #       systemd.show_status=false -> fuera los [ OK ] y [ FAILED ]
    #    Todo sigue guardado en el journal (journalctl -b) por si hay que mirar.
    valor_actual=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub" 2>/dev/null | head -1 | cut -d= -f2-)
    valor_nuevo=$(printf '%s' "$valor_actual" \
        | sed -e 's/"//g' -e 's/\bsplash\b//g' -e 's/\bplymouth\b//g' \
              -e 's/\bloglevel=[0-9]*//g' -e 's/\bsystemd\.show_status=[a-z]*//g' -e 's/\bquiet\b//g' \
        | tr -s ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$valor_nuevo" ] && valor_nuevo="$valor_nuevo "
    valor_nuevo="${valor_nuevo}quiet loglevel=0 systemd.show_status=false"
    valor_nuevo=$(printf '%s' "$valor_nuevo" | tr -s ' ' | sed -e 's/^ //' -e 's/ $//')
    if [ "$valor_actual" != "\"$valor_nuevo\"" ]; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$valor_nuevo\"|" "$grub"
        info "Arranque mudo: sin texto (quiet + sin [ OK ]/[ FAILED ])"
        cambiado=1
    fi

    # 2) GRUB en modo texto (nada de menu grafico en negro)
    if grep -q '^GRUB_TERMINAL=' "$grub" 2>/dev/null; then
        valor_actual=$(grep '^GRUB_TERMINAL=' "$grub" | head -1 | cut -d= -f2-)
        if [ "$valor_actual" != '"console"' ]; then
            sudo sed -i 's|^GRUB_TERMINAL=.*|GRUB_TERMINAL="console"|' "$grub"
            info "GRUB en modo texto (console)"
            cambiado=1
        fi
    else
        echo 'GRUB_TERMINAL="console"' | sudo tee -a "$grub" >/dev/null 2>&1
        info "GRUB en modo texto (console)"
        cambiado=1
    fi

    if grep -q '^GRUB_GFXPAYLOAD_LINUX=' "$grub" 2>/dev/null; then
        valor_actual=$(grep '^GRUB_GFXPAYLOAD_LINUX=' "$grub" | head -1 | cut -d= -f2-)
        if [ "$valor_actual" != '"text"' ]; then
            sudo sed -i 's|^GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX="text"|' "$grub"
            cambiado=1
        fi
    else
        echo 'GRUB_GFXPAYLOAD_LINUX="text"' | sudo tee -a "$grub" >/dev/null 2>&1
        cambiado=1
    fi

    # 3) Arranque rapido: sin menu y sin espera
    valor_actual=$(grep '^GRUB_TIMEOUT_STYLE=' "$grub" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ "$valor_actual" != "hidden" ]; then
        if grep -q '^GRUB_TIMEOUT_STYLE=' "$grub"; then
            sudo sed -i 's|^GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=hidden|' "$grub"
        else
            echo 'GRUB_TIMEOUT_STYLE=hidden' | sudo tee -a "$grub" >/dev/null 2>&1
        fi
        cambiado=1
    fi

    valor_actual=$(grep '^GRUB_TIMEOUT=' "$grub" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ "$valor_actual" != "0" ]; then
        if grep -q '^GRUB_TIMEOUT=' "$grub"; then
            sudo sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=0|' "$grub"
        else
            echo 'GRUB_TIMEOUT=0' | sudo tee -a "$grub" >/dev/null 2>&1
        fi
        info "Menu de GRUB oculto (arranque directo)"
        cambiado=1
    fi

    # 4) Regenerar grub SOLO si cambio algo
    if [ "$cambiado" = "1" ]; then
        if sudo update-grub &>/dev/null 2>&1; then
            info "GRUB regenerado (efecto al reiniciar)"
        else
            warn "No se pudo regenerar GRUB"
        fi
    else
        info "Arranque ya configurado (sin cambios)"
    fi
}

optimizar_profundidad() {
    step "Optimizacion profunda: servicios + CPU + kernel"

    FWUPD=0; APT=0; E2SCRUB=0; ACCOUNTS=0; NMWAIT=0; KERNELOOPS=0; APPORT=0
    GOV=0; ZRAM=0; WATCHDOG=0

    if systemctl is-enabled fwupd-refresh &>/dev/null 2>&1; then
        sudo systemctl mask fwupd-refresh.service 2>/dev/null || true
        FWUPD=1
    fi
    if systemctl is-enabled fwupd &>/dev/null 2>&1; then
        sudo systemctl mask fwupd.service 2>/dev/null || true
    fi

    for svc in apt-daily.service apt-daily-upgrade.service; do
        if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
            sudo systemctl mask "$svc" 2>/dev/null || true
            APT=1
        fi
    done

    if systemctl is-enabled e2scrub_reap &>/dev/null 2>&1; then
        sudo systemctl mask e2scrub_reap.service 2>/dev/null || true
        E2SCRUB=1
    fi

    # accounts-daemon: NO se enmascara. Antes se hacia para ahorrar unos
    # milisegundos, pero lightdm lo usa para sacar la LISTA DE USUARIOS del
    # login. Con el servicio enmascarado, lightdm falla al arrancar el greeter:
    #   Error getting user list from org.freedesktop.Accounts:
    #   GDBus.Error:org.freedesktop.systemd1.UnitMasked
    # y el login se queda sin usuarios, que es justo lo que pasaba al ENCENDER
    # el ordenador (parecia que LightDM no arrancaba). Al cambiar de usuario o
    # al suspender el greeter si cae a la lista de PAM y por eso se veia bien.
    # Aqui solo se quita la mascara de una pasada anterior; no se vuelve a poner.
    if systemctl is-enabled accounts-daemon &>/dev/null 2>&1; then
        sudo systemctl unmask accounts-daemon.service 2>/dev/null || true
        sudo systemctl enable accounts-daemon.service 2>/dev/null || true
        ACCOUNTS=2
    else
        ACCOUNTS=1
    fi

    if systemctl is-enabled NetworkManager-wait-online &>/dev/null 2>&1; then
        sudo systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
        NMWAIT=1
    fi

    # También desactivar systemd-networkd-wait-online por si usa networkd
    if systemctl is-enabled systemd-networkd-wait-online &>/dev/null 2>&1; then
        sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true
        NMWAIT=1
    fi

    # Evitar que unidades del usuario esperen red: quitar After=network-online.target de servicios gráficos
    for svc in lightdm.service display-manager.service; do
        if systemctl cat "$svc" 2>/dev/null | grep -q 'After=.*network-online.target'; then
            sudo mkdir -p "/etc/systemd/system/$svc.d"
            printf '[Unit]\nAfter=\nWants=\n' | sudo tee "/etc/systemd/system/$svc.d/no-wait-network.conf" &>/dev/null
            sudo systemctl daemon-reload
            info "$svc: quitado After=network-online.target"
        fi
    done

    if systemctl is-enabled kerneloops &>/dev/null 2>&1; then
        sudo systemctl mask kerneloops.service 2>/dev/null || true
        KERNELOOPS=1
    fi

    if systemctl is-enabled apport &>/dev/null 2>&1; then
        sudo systemctl mask apport.service 2>/dev/null || true
        APPORT=1
    fi

    if command -v cpupower &>/dev/null; then
        sudo cpupower frequency-set -g performance &>/dev/null || true
        GOV=1
    elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor &>/dev/null || true
        GOV=1
    fi

    local gov_rule="/etc/udev/rules.d/99-cpu-governor.rules"
    if [ ! -f "$gov_rule" ]; then
        echo 'ACTION=="add", SUBSYSTEM=="cpu", ATTR{cpufreq/scaling_governor}="performance"' | \
            sudo tee "$gov_rule" &>/dev/null || true
    fi

    local grub="/etc/default/grub"
    if ! grep -q "nowatchdog" "$grub" 2>/dev/null; then
        sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog /' "$grub"
        sudo update-grub &>/dev/null || true
        WATCHDOG=1
    fi

    if ! systemctl is-enabled zram-setup &>/dev/null 2>&1; then
        sudo tee /etc/systemd/system/zram-setup.service << 'SERVICEEOF' &>/dev/null
[Unit]
Description=Swap comprimido zram
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "modprobe zram && zramctl -f --size 8G --algorithm zstd && mkswap /dev/zram0 && swapon -p 100 /dev/zram0"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF
        sudo systemctl enable zram-setup.service &>/dev/null || true
        sudo systemctl start zram-setup.service &>/dev/null || true
        ZRAM=1
    else
        ZRAM_ALREADY=1
    fi

    echo ""
    [ "$FWUPD" = 1 ]     && info "fwupd-refresh desactivado"      || info "fwupd-refresh ya desactivado"
    [ "$APT" = 1 ]       && info "apt-daily desactivado"           || info "apt-daily ya desactivado"
    [ "$E2SCRUB" = 1 ]   && info "e2scrub_reap desactivado"       || info "e2scrub_reap ya desactivado"
    [ "$ACCOUNTS" = 1 ]  && info "accounts-daemon desactivado"    || info "accounts-daemon ya desactivado"
    [ "$NMWAIT" = 1 ]    && info "NM-wait-online desactivado"     || info "NM-wait-online ya desactivado"
    [ "$KERNELOOPS" = 1 ]&& info "kerneloops desactivado"         || info "kerneloops ya desactivado"
    [ "$APPORT" = 1 ]    && info "apport desactivado"             || info "apport ya desactivado"
    [ "$GOV" = 1 ]       && info "CPU governor = performance"     || info "CPU governor ya en performance"
    [ "$WATCHDOG" = 1 ]  && info "nowatchdog anadido a kernel"    || info "nowatchdog ya presente"
    [ "$ZRAM" = 1 ]      && info "zram activado (8G zstd)"
    [ "$ZRAM_ALREADY" = 1 ] && info "zram ya activado"
}

optimizar_energia() {
    step "Configurando gestor de energía (tapa → lock, sin pantalla negra)"

    # 1. systemd-logind: cerrar tapa = bloquear (no suspender/hibernar)
    local logind_conf="/etc/systemd/logind.conf"
    local logind_tmp=$(mktemp)
    sudo cp "$logind_conf" "$logind_tmp" 2>/dev/null || true

    # Asegurar claves necesarias
    grep -q '^HandleLidSwitch=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitch=lock' >> "$logind_tmp"
    grep -q '^HandleLidSwitchExternalPower=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitchExternalPower=lock' >> "$logind_tmp"
    grep -q '^HandleLidSwitchDocked=' "$logind_tmp" 2>/dev/null || echo 'HandleLidSwitchDocked=ignore' >> "$logind_tmp"
    grep -q '^LidSwitchIgnoreInhibited=' "$logind_tmp" 2>/dev/null || echo 'LidSwitchIgnoreInhibited=no' >> "$logind_tmp"

    # Reemplazar valores si ya existen
    sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=lock/' "$logind_tmp"
    sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' "$logind_tmp"
    sed -i 's/^#*HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$logind_tmp"
    sed -i 's/^#*LidSwitchIgnoreInhibited=.*/LidSwitchIgnoreInhibited=no/' "$logind_tmp"

    if ! cmp -s "$logind_tmp" "$logind_conf" 2>/dev/null; then
        sudo cp "$logind_tmp" "$logind_conf"
        sudo systemctl restart systemd-logind 2>/dev/null || true
        info "systemd-logind: tapa → lock (externo/dock ignorado)"
    else
        info "systemd-logind ya configurado"
    fi
    rm -f "$logind_tmp"

    # 2. xfce4-power-manager: mismo comportamiento + no apagar pantalla al bloquear
    if command -v xfconf-query &>/dev/null; then
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-battery -s 1 2>/dev/null || true      # 1 = lock
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lid-action-on-ac -s 1 2>/dev/null || true          # 1 = lock
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s true 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/logind-handle-lid-switch -s true 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-battery -s 0 2>/dev/null || true          # no apagar pantalla batería
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-on-ac -s 0 2>/dev/null || true              # no apagar pantalla AC
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 2>/dev/null || true
        xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-battery -s 0 2>/dev/null || true
        info "xfce4-power-manager: tapa → lock, pantalla siempre encendida"
    fi

    # 3. BLOQUEO con xfce4-screensaver (único bloqueador, sin duplicados).
    #    light-locker 1.8.0 deja la pantalla en negro al desbloquear la 2ª
    #    vez tras cerrar la tapa (bug conocido) → se desactiva.
    if command -v xfce4-screensaver &>/dev/null || [ -f /etc/xdg/autostart/xfce4-screensaver.desktop ]; then
        cat > ~/.config/autostart/xfce4-screensaver.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Xfce Screensaver
Comment=Bloqueo de pantalla (unico bloqueador)
Exec=xfce4-screensaver
Hidden=false
EOF
        xfconf-query -c xfce4-session -p /general/LockCommand -s "xfce4-screensaver-command --lock" 2>/dev/null || true
        info "Bloqueo: xfce4-screensaver (lock fiable)"
    else
        # Fallback: solo systemd-logind para lock
        xfconf-query -c xfce4-session -p /general/LockCommand -s "loginctl lock-session" 2>/dev/null || true
        info "Lock via systemd-logind (xfce4-screensaver no disponible)"
    fi
    # light-locker desactivado (autostart oculto) para no duplicar bloqueos.
    if command -v light-locker &>/dev/null || [ -f /etc/xdg/autostart/light-locker.desktop ]; then
        cat > ~/.config/autostart/light-locker.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Light-locker
Exec=light-locker
Hidden=true
EOF
        pkill -x light-locker 2>/dev/null || true
        info "light-locker desactivado (evita doble bloqueo)"
    fi

    # Sesión: nunca se guarda. El checkbox del diálogo de salida puede estar
    # desmarcado y aun así xfce4-session dejaba la sesión en caché, con lo que
    # al siguiente arranque se restauraban las apps.
    xfconf-query -c xfce4-session -p /general/SaveOnExit -s false 2>/dev/null || true
    xfconf-query -c xfce4-session -p /general/AutoSave   -s false 2>/dev/null || true
    rm -f "$HOME"/.cache/sessions/xfce4-session-* 2>/dev/null || true
    info "Sesión nunca se guarda (SaveOnExit y AutoSave desactivados)"


    # 4. Hook systemd-sleep: al despertar (resume) recomponer sesión → pantalla ON + plank + xfce4-screensaver + red
    local sleep_hook="/lib/systemd/system-sleep/99-mac-os-xfce-resume"
    sudo tee "$sleep_hook" >/dev/null << 'SLEEPEOF'
#!/bin/bash
# Hook resume: recomponer la sesión tras suspend/hibernate (pantalla ON, plank, locker, red)
case "$1/$2" in
    post/suspend|post/hibernate|post/hybrid-sleep)
        # Esperar un poco a que el kernel termine de reanudar dispositivos
        sleep 2
        # Usuario real (no root)
        REAL_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
        [ -z "$REAL_USER" ] && REAL_USER=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd)
        [ -z "$REAL_USER" ] && exit 0
        USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
        export DISPLAY=":0"
        export XAUTHORITY="$USER_HOME/.Xauthority"
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus"

        # 0. FORZAR PANTALLA ON (DPMS) - crítico para evitar negro
        sudo -u "$REAL_USER" xset dpms force on 2>/dev/null || true
        sudo -u "$REAL_USER" xset s off 2>/dev/null || true
        sudo -u "$REAL_USER" xset -dpms 2>/dev/null || true
        sudo -u "$REAL_USER" xset s noblank 2>/dev/null || true


        # 2. Reiniciar Plank si no está
        if ! sudo -u "$REAL_USER" pgrep -x plank >/dev/null 2>&1; then
            sudo -u "$REAL_USER" plank >/dev/null 2>&1 &
        fi

        # 3. Asegurar xfce4-screensaver vivo (bloqueo actual); si murió,
        #    relanzarlo para que el próximo bloqueo funcione bien.
        if ! sudo -u "$REAL_USER" pgrep -x xfce4-screensaver >/dev/null 2>&1; then
            sudo -u "$REAL_USER" xfce4-screensaver >/dev/null 2>&1 &
        fi

        # 4. Forzar xfwm4 a redibujar (quita artefactos/negro) con compositor
        #    propio: el compositor del sistema es el de xfwm4 (xfwm4 compone,
        #    no hay picom: se solaparían y además va más lento).
        sudo -u "$REAL_USER" xfwm4 --replace --compositor=on 2>/dev/null &

        # 5. Red: reconectar cableado y asegurar nm-applet / blueman-applet
        nmcli device reapply "$(nmcli -t -f DEVICE,TYPE device | grep ':ethernet' | cut -d: -f1 | head -1)" 2>/dev/null || true
        if ! sudo -u "$REAL_USER" pgrep -x nm-applet >/dev/null 2>&1; then
            sudo -u "$REAL_USER" nm-applet 2>/dev/null &
        fi
        if ! sudo -u "$REAL_USER" pgrep -x blueman-applet >/dev/null 2>&1; then
            sudo -u "$REAL_USER" blueman-applet 2>/dev/null &
        fi
        ;;
esac
SLEEPEOF
    sudo chmod +x "$sleep_hook"
    info "Hook resume systemd-sleep creado (pantalla ON + plank + xfce4-screensaver + xfwm4 + red)"

    # 6. NetworkManager: conexión cableada RÁPIDA (no esperar "online", pero sí conectar ya)
    local nm_conf="/etc/NetworkManager/conf.d/99-wired-fast.conf"
    sudo mkdir -p "$(dirname "$nm_conf")"
    sudo tee "$nm_conf" >/dev/null << 'NMEOF'
[main]
# No esperar conectividad completa para considerar "conectado"
connectivity-check-enabled=false

[device]
# No gestionar wait-online para wired
wired.wait-online=false
NMEOF
    sudo systemctl reload NetworkManager 2>/dev/null || true
    info "NetworkManager: wired rápido (sin wait-online)"
}

optimizar_limpiar() {
    step "Limpiando caches y temporales"

    apt_silencioso autoremove 2>/dev/null || true
    apt_silencioso autoclean 2>/dev/null || true
    journalctl --vacuum-time=7d &>/dev/null || true
    rm -rf ~/.cache/thumbnails/* 2>/dev/null || true
    rm -rf ~/.cache/mozilla/firefox/*/cache2/* 2>/dev/null || true
    info "Caches limpiadas"
}

optimizar_resumen() {
    echo ""
    echo "=== Sistema optimizado ==="
    echo "  + Autostart: sleeps reducidos"
    echo "  + Sysctl:    swappiness=10, cache optim."
    echo "  + Servicios: fwupd, apt, e2scrub, ..."
    echo "  + CPU:       governor performance"
    echo "  + Kernel:    nowatchdog"
    echo "  + zram:      swap comprimida en RAM"
    echo "  + GRUB:      sin splash, timeout 1s"
    echo "  + Caches:    limpiadas"
    echo ""
    echo "Reinicia para aplicar todos los cambios."
}

if [ "$1" = "systemd" ]; then optimizar_systemd; fi
if [ "$1" = "autostart" ]; then optimizar_autostart; fi
if [ "$1" = "kernel" ]; then optimizar_kernel; fi
if [ "$1" = "preload" ]; then optimizar_preload; fi
if [ "$1" = "boot" ]; then optimizar_boot; fi
if [ "$1" = "profundidad" ]; then optimizar_profundidad; fi
if [ "$1" = "limpiar" ]; then optimizar_limpiar; fi
if [ "$1" = "energia" ]; then optimizar_energia; fi

if [ -z "$1" ] || [ "$1" = "all" ]; then
    optimizar_autostart
    optimizar_kernel
    optimizar_preload
    optimizar_boot
    optimizar_profundidad
    optimizar_energia
    optimizar_limpiar
    optimizar_resumen
fi
