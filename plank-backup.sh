#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# plank-backup.sh — Copia de seguridad de Plank + tus cosas, A TU ELECCIÓN
#
# Al exportar TÚ eliges qué guardar:
#   • Solo navbar (sin instalar nada)      → config + tus apps (Safari→Brave),
#                                            SIN paquetes
#   • Navbar + paquetes del navbar         → lo anterior + paquetes de las apps ancladas
#   • Navbar + todos los paquetes manuales → lo anterior + los que instalaste a mano
#
# Guarda / restaura:
#   • Configuración de Plank (dock + lanzadores de la navbar) y temas
#   • LOS .DESKTOP REALES que usa cada lanzador del dock (estuvieran donde
#     estuvieran: ~/.local/share/applications, /usr/share/applications, etc.)
#     y sus recursos (iconos y ejecutables por ruta absoluta), con un mapa
#     "de dónde venía", para que al restaurar en OTRO PC funcione IGUAL,
#     aunque cambies el escritorio o el .desktop original.
#   • Apps personalizadas de ~/.local/share/applications (Safari→Brave, …)
#   • Scripts de ~/.local/bin  • Autostart  • Iconos de ~/.icons/custom
#   • Listas: apps del navbar y paquetes manuales
#   • Repositorios y claves apt (/etc/apt/sources.list.d + keyrings), para que
#     "instalar.sh" funcione en un PC recién formateado (sin repos/keys)
#   • Script "instalar.sh" para reinstalar los paquetes en otro ordenador
# ─────────────────────────────────────────────────────────────────────────────

PLANK_CONFIG="$HOME/.config/plank"
PLANK_THEMES="$HOME/.local/share/plank/themes"
APPS_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
ICONS_CUSTOM="$HOME/.icons/custom"
FECHA=$(date +%Y%m%d-%H%M%S)
DIR=$(cd "$(dirname "$0")" && pwd)

ICONO="$HOME/Escritorio/GITHUB/icon.png"
[ -f "$ICONO" ] || ICONO="$HOME/.icons/custom/plank-backup.svg"
[ -f "$ICONO" ] || ICONO="$DIR/icon-plank-backup.svg"

ZEN=(zenity --window-icon="$ICONO")

if ! command -v zenity >/dev/null 2>&1; then
    echo "zenity no está instalado. Ejecuta: sudo apt install zenity"
    exit 1
fi

plank_reiniciar() {
    pkill -x plank 2>/dev/null || true
    sleep 1
    nohup plank >/tmp/plank.log 2>&1 &
    sleep 2
}

# ─── Lanzadores portátiles ─────────────────────────────────────────────────────
# Un .dockitem de Plank solo guarda la RUTA de un .desktop
# (p. ej. Launcher=file:///home/user/.local/share/applications/safari.desktop).
# Si en el otro PC esa ruta no existe (o cambiaste el .desktop), el lanzador
# se rompe. Para evitarlo, al exportar se guardan también los .desktop REALES
# que usa el dock y los recursos que referencian (iconos y ejecutables por
# ruta absoluta), con un mapa de dónde venía cada cosa. Al importar se
# recolocan en este PC y se reescriben los .dockitem para que apunten a algo
# que exista → funciona EXACTAMENTE igual estés donde estés.

archivo_referido() {  # ruta del .desktop que usa un dockitem
    sed -n 's/^Launcher=file:\/\///p' "$1" | head -1 | tr -d '\r'
}

recurso_del_sistema() {  # ¿es de un paquete del sistema? esos no se copian al ZIP
    case "$1" in
        /usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*|/lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*|/usr/share/*|/etc/*)
            return 0 ;;
        *) return 1 ;;
    esac
}

salvar_recursos_lanzadores() {
    local tmp="$1"
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0

    local rec="$tmp/relaunchers"
    mkdir -p "$rec/icons" "$rec/exec"
    : > "$rec/origen.txt"
    echo "ORIGEN_HOME|$HOME" >> "$rec/origen.txt"

    local item ruta slug clave valor base destino zip_nom
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        ruta=$(archivo_referido "$item")
        [ -n "$ruta" ] || continue
        ruta="${ruta//\~/$HOME}"
        [ -f "$ruta" ] || continue

        slug=$(basename "$item" .dockitem)
        [ -n "$slug" ] || slug="launcher"

        # El .desktop real que usaba el lanzador (estuviera donde estuviera)
        cp "$ruta" "$rec/${slug}.desktop" 2>/dev/null || continue
        echo "DESKTOP|$ruta|${slug}.desktop" >> "$rec/origen.txt"

        # Iconos y ejecutables que ese .desktop referencia por ruta absoluta
        for clave in Icon Exec Path; do
            valor=$(grep -m1 "^$clave=" "$ruta" 2>/dev/null | cut -d= -f2-)
            [ -n "$valor" ] || continue
            case "$clave" in
                Icon)
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            [ -f "$valor" ] || continue
                            base=$(basename "$valor")
                            if [ ! -f "$rec/icons/$base" ]; then
                                cp "$valor" "$rec/icons/$base" 2>/dev/null || continue
                            fi
                            echo "ICON|$valor|icons/$base" >> "$rec/origen.txt"
                            ;;
                    esac ;;
                Exec)
                    # Los .desktop de JetBrains Toolbox traen el comando ENTRE
                    # comillas: Exec="/home/u/.../apps/idea/bin/idea" %u. Hay que
                    # quitarlas para quedarnos con la ruta real del ejecutable.
                    valor="${valor#\"}"
                    valor="${valor%%\"*}"
                    valor="${valor%% *}"          # solo el comando, sin argumentos
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            [ -f "$valor" ] || continue
                            zip_nom=$(echo "$valor" | sed "s|^$HOME/||")
                            [ -n "$zip_nom" ] || zip_nom=$(basename "$valor")
                            mkdir -p "$rec/exec/$(dirname "$zip_nom")"
                            if [ ! -f "$rec/exec/$zip_nom" ]; then
                                cp "$valor" "$rec/exec/$zip_nom" 2>/dev/null || continue
                            fi
                            echo "Exec|$valor|exec/$zip_nom" >> "$rec/origen.txt"
                            ;;
                    esac ;;
                Path)
                    case "$valor" in
                        /*)
                            recurso_del_sistema "$valor" && continue
                            if [ ! -f "$valor" ] && [ ! -d "$valor" ]; then continue; fi
                            zip_nom=$(echo "$valor" | sed "s|^$HOME/||")
                            [ -n "$zip_nom" ] || zip_nom=$(basename "$valor")
                            mkdir -p "$rec/path/$(dirname "$zip_nom")"
                            if [ ! -e "$rec/path/$zip_nom" ]; then
                                cp -r "$valor" "$rec/path/$zip_nom" 2>/dev/null || continue
                            fi
                            echo "Path|$valor|path/$zip_nom" >> "$rec/origen.txt"
                            ;;
                    esac ;;
            esac
        done
    done
}

restaurar_recursos_lanzadores() {
    local tmp="$1"
    local dock="$PLANK_CONFIG/dock1/launchers"
    local rec="$tmp/relaunchers"
    [ -d "$rec" ] || return 0

    # Hogar del PC de ORIGEN (guardado en el mapa): sirve para traducir las
    # rutas absolutas hacia el hogar de ESTE PC, sea cual sea el prefijo
    # (no solo /home/...), aunque el usuario cambie de nombre o de disco.
    local origin_home=""
    while IFS='|' read -r tipo rest1 rest2; do
        if [ "$tipo" = "ORIGEN_HOME" ]; then origin_home="$rest1"; break; fi
    done < "$rec/origen.txt"

    # ── 1) Colocar los .desktop guardados en ~/.local/share/applications ──
    mkdir -p "$APPS_DIR"
    local f nom destino
    for f in "$rec"/*.desktop; do
        [ -f "$f" ] || continue
        nom=$(basename "$f")
        destino="$APPS_DIR/$nom"
        if [ "$modo" = "Reemplazar" ] || [ ! -e "$destino" ]; then
            cp -f "$f" "$destino"
            chmod +x "$destino" 2>/dev/null || true
        fi
        # Corregir las rutas absolutas de ESTE .desktop (Icon, Exec, Path)
        if [ -n "$origin_home" ]; then
            sed -i "s|$origin_home|$HOME|g" "$destino" 2>/dev/null || true
        else
            sed -i "s|/home/[^/]*/|/home/$USER/|g" "$destino" 2>/dev/null || true
        fi
    done

    # ── 2) Recolocar iconos / ejecutables / carpetas a su ruta en ESTE PC,
    #        traduciendo el home de origen por el actual ──
    # Para los destinos FUERA de $HOME que son de solo-root (p. ej.
    # /usr/local/bin/virtualbox-no-kvm, el script que lanza el VirtualBox
    # recién instalado por apt), si la copia como usuario no puede, se
    # reintenta con sudo -n (funciona si la regla visudo ya está instalada).
    _colocar_recurso() {
        local _src="$1" _dst="$2" _dd
        _dd=$(dirname "$_dst")
        mkdir -p "$_dd" 2>/dev/null || true
        if ! cp -r "$_src" "$_dst" 2>/dev/null; then
            sudo -n mkdir -p "$_dd" 2>/dev/null
            sudo -n cp -r "$_src" "$_dst" 2>/dev/null || true
        fi
    }
    local tipo ruta_origen zip_rel ruta_nueva
    while IFS='|' read -r tipo ruta_origen zip_rel; do
        [ -n "$tipo" ] || continue
        case "$tipo" in
            ICON|Exec|Path)
                if [ -n "$origin_home" ]; then
                    ruta_nueva="${ruta_origen/#$origin_home/$HOME}"
                else
                    ruta_nueva=$(echo "$ruta_origen" | sed "s|/home/[^/]*/|/home/$USER/|g")
                fi
                if [ -e "$rec/$zip_rel" ]; then
                    if [ "$tipo" = "Path" ] && [ -d "$rec/$zip_rel" ]; then
                        # carpeta completa: crear y copiar SOLO lo que falte
                        # (sin pisar nada que ya exista en este PC)
                        if ! { mkdir -p "$ruta_nueva" 2>/dev/null && cp -rn "$rec/$zip_rel"/. "$ruta_nueva" 2>/dev/null; }; then
                            sudo -n mkdir -p "$ruta_nueva" 2>/dev/null
                            sudo -n cp -rn "$rec/$zip_rel"/. "$ruta_nueva" 2>/dev/null || true
                        fi
                    elif [ ! -e "$ruta_nueva" ]; then
                        # archivo suelto: solo si todavía no existe
                        _colocar_recurso "$rec/$zip_rel" "$ruta_nueva"
                    fi
                    if [ -e "$ruta_nueva" ]; then
                        chmod +x "$ruta_nueva" 2>/dev/null || sudo -n chmod +x "$ruta_nueva" 2>/dev/null || true
                    fi
                fi
                ;;
        esac
    done < "$rec/origen.txt"

    # ── 3) Reescribir .dockitem: si la ruta apuntada NO existe aquí, o existe
    #        pero NO es idéntica a la que guardaste (p. ej. el .desktop del
    #        sistema fue actualizado o lo modificaste a mano), se redirige al
    #        .desktop restaurado → funciona IGUAL que en el PC de origen ──
    local item ruta_iter slug usado
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        ruta_iter=$(archivo_referido "$item")
        [ -n "$ruta_iter" ] || continue
        ruta_iter="${ruta_iter//\~/$HOME}"
        if [ -n "$origin_home" ]; then
            ruta_iter="${ruta_iter/#$origin_home/$HOME}"
        else
            ruta_iter=$(echo "$ruta_iter" | sed "s|/home/[^/]*/|/home/$USER/|g")
        fi

        slug=$(basename "$item" .dockitem)
        usado="$APPS_DIR/$slug.desktop"
        if [ ! -f "$usado" ]; then
            usado=""
            while IFS='|' read -r tipo ruta_origen zip_rel; do
                if [ "$tipo" = "DESKTOP" ] && [ "${zip_rel%.desktop}" = "$slug" ]; then
                    usado="$APPS_DIR/$zip_rel"
                    break
                fi
            done < "$rec/origen.txt"
        fi
        [ -f "$usado" ] || continue   # sin copia guardada: se deja como esté

        if [ -f "$ruta_iter" ]; then
            # La ruta original existe: solo se re-apunta si difiere del guardado
            cmp -s "$ruta_iter" "$usado" && continue
        fi
        printf '[PlankDockItemPreferences]\nLauncher=file://%s\n' "$usado" > "$item"
    done
}

# ─── Paquetes apt detrás de cada lanzador ─────────────────────────────────────
# Un lanzador del dock casi nunca es “un paquete directo”: el .desktop real
# suele vivir en ~/.local/share/applications (propio, sin dueño en dpkg) y
# apuntar a un wrapper o al binario instalado por su paquete (VS Code,
# Docker Desktop, Unity Hub…). Para descubrir el paquete “de verdad”:
#   1) ¿dpkg es dueño del .desktop?            (los del sistema: sí)
#   2) si no, ¿qué binario REAL ejecuta Exec?  (args fuera, symlinks dentro)
#   3) si ese binario es un wrapper propio (~/.local/bin, ~/Aplicaciones…),
#      se buscan las rutas absolutas a las que apunta dentro (Docker, Unity…)
# Se descartan paquetes “de infraestructura” (bash, python3, coreutils…)
# que jamás son la app que se ancla en el dock.

paquete_basura() {  # ¿paquete de sistema que no es “la app”? → no listar
    case "$1" in
        bash|dash|sh|coreutils|util-linux|procps|grep|sed|awk|gawk|mawk|diffutils|findutils|patch|tar|gzip|xz-utils|bzip2|dpkg|apt|perl|perl-base|python3|python3-minimal|python3.1*|libc6|init-system-helpers|debianutils|base-files|base-passwd|bsdutils|passwd|login|mint-meta-core|mint-meta-xfce)
            return 0 ;;
        *) return 1 ;;
    esac
}

binarios_de_desktop() {  # binario(s) REAL(es) que lanza un .desktop
    local desk="$1" linea cmd ruta cand
    linea=$(sed -n 's/^Exec=//p' "$desk" | head -1 | tr -d '\r')
    [ -n "$linea" ] || return 0
    cmd=$(echo "$linea" | awk '{print $1}')
    [ "$cmd" = "env" ] && cmd=$(echo "$linea" | awk '{print $2}')
    [ -z "$cmd" ] && return 0
    cmd="${cmd//\"/}"
    case "$cmd" in
        /*) ruta="$cmd" ;;
        *)  ruta=$(command -v "$cmd" 2>/dev/null) || return 0 ;;
    esac
    [ -f "$ruta" ] || return 0
    ruta=$(readlink -f "$ruta" 2>/dev/null || echo "$ruta")
    echo "$ruta"
    # ¿Es un wrapper propio (script)? Los de Docker Desktop, Unity Hub…
    # apuntan dentro a la ruta real (/opt/…, /usr/lib/…): exponerla también.
    if [ "$(head -c 2 "$ruta" 2>/dev/null)" = "#!" ]; then
        case "$ruta" in
            "$HOME"/.local/bin/*|"$HOME"/Aplicaciones/*|"$HOME"/bin/*)
                while IFS= read -r cand; do
                    [ -f "$cand" ] && [ -x "$cand" ] && echo "$cand"
                done < <(grep -oE '/(opt|usr/lib|usr/share|usr/local)[^ "]+' "$ruta" 2>/dev/null | sort -u) ;;
        esac
    fi
}

# Paquetes de las aplicaciones ancladas en el dock/navbar de Plank
paquetes_navbar() {
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0
    local item archivo pkg binario
    for item in "$dock"/*.dockitem; do
        [ -f "$item" ] || continue
        archivo=$(archivo_referido "$item")
        [ -n "$archivo" ] || continue
        archivo="${archivo//\~/$HOME}"
        [ -f "$archivo" ] || continue

        # 1) ¿El .desktop es de un paquete? (los del sistema, sí)
        pkg=$(dpkg -S "$archivo" 2>/dev/null | head -1 | cut -d: -f1)
        if [ -n "$pkg" ] && ! paquete_basura "$pkg"; then
            echo "$pkg"
            continue
        fi

        # 2) El .desktop es propio: rastrear el binario REAL y su wrapper
        for binario in $(binarios_de_desktop "$archivo"); do
            pkg=$(dpkg -S "$binario" 2>/dev/null | head -1 | cut -d: -f1)
            if [ -n "$pkg" ] && ! paquete_basura "$pkg"; then
                echo "$pkg"
                break
            fi
        done
    done | sort -u
}

# ─── Orden de los lanzadores en el dock (dconf dock-items) ─────────────────────
# El orden real de Plank NO está en los archivos .dockitem: vive en dconf,
# en /net/launchpad/plank/docks/dock1/dock-items. Si Plank está corriendo
# mientras se restaura, él mismo vuelve a escribir esa clave con su estado
# en memoria y PISA el orden restaurado. Por eso:
#   • al importar se PARA Plank antes de tocar nada (plank_importar), y
#   • esta función asegura que la lista dconf contenga TODOS los dockitem
#     existentes, respetando el orden actual y añadiendo al final los que
#     falten (p. ej. los nuevos lanzadores en modo “Mezclar”).
orden_dock_asegurar() {
    local dock="$PLANK_CONFIG/dock1/launchers"
    [ -d "$dock" ] || return 0
    command -v dconf >/dev/null 2>&1 || return 0
    local clave="/net/launchpad/plank/docks/dock1/dock-items"
    local lista=() actual item f base ya i contenido
    actual=$(dconf read "$clave" 2>/dev/null)
    if [ -n "$actual" ] && [[ "$actual" == \[* ]]; then
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            [ -f "$dock/$item" ] && lista+=("$item")
        done < <(echo "$actual" | tr -d '[]' | tr ',' '\n' | tr -d " '")
    fi
    for f in "$dock"/*.dockitem; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        ya=0
        for i in "${lista[@]}"; do [ "$i" = "$base" ] && ya=1 && break; done
        [ "$ya" -eq 0 ] && lista+=("$base")
    done
    [ "${#lista[@]}" -eq 0 ] && return 0
    contenido=$(printf "'%s', " "${lista[@]}")
    contenido="[${contenido%, }]"
    dconf write "$clave" "$contenido"
}

# Qué se va a guardar
f_config=false f_apps=false f_scripts=false f_autostart=false
f_iconos=false f_navbar=false f_manuales=false

# URL del .deb de un paquete sin repo, para que instalar.sh lo vuelva a
# bajar en el otro PC (viaja el ENLACE, no la app). Fuentes:
#   1) Historial real de descargas de este PC (Firefox, Chrome/Chromium,
#      Brave, Edge y terminal: .bash_history / .zsh_history).
#   2) Enlaces estables de "última versión" que publica el propio fabricante
#      (el historial solo guarda la URL concreta de ese día).
url_deb_de() {
    local paq="$1" fuente u
    for fuente in ~/.mozilla/firefox/*/places.sqlite \
                  ~/.config/google-chrome/*/History \
                  ~/.config/chromium/*/History \
                  ~/.config/BraveSoftware/*/History \
                  ~/.config/microsoft-edge/*/History \
                  ~/.bash_history ~/.zsh_history; do
        [ -f "$fuente" ] || continue
        u=$(grep -aoE "https?://[^\"<> ]*${paq}[^\"<> ]*\\.deb" "$fuente" 2>/dev/null | head -1 | sed 's/\(\.deb\).*/\1/')
        [ -n "$u" ] && { echo "$u"; return 0; }
    done
    case "$paq" in
        docker-desktop) echo "https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb" ;;
        ulauncher)      echo "https://github.com/Ulauncher/Ulauncher/releases/download/5.16.2/ulauncher_5.16.2_all.deb" ;;
    esac
}

# URL de un archivo de app portátil (tar.gz, AppImage…) desde el historial.
# Complementa a url_deb_de para las apps que NO se instalan con apt.
url_archivo_de() {
    local app="$1" fuente u
    for fuente in ~/.mozilla/firefox/*/places.sqlite \
                  ~/.config/google-chrome/*/History \
                  ~/.config/chromium/*/History \
                  ~/.config/BraveSoftware/*/History \
                  ~/.config/microsoft-edge/*/History \
                  ~/.bash_history ~/.zsh_history; do
        [ -f "$fuente" ] || continue
        u=$(grep -aoE "https?://[^\"<> ]*${app}[^\"<> ]*\\.(tar\\.gz|tar\\.xz|tar\\.bz2|tgz|tar\\.zst|zip|AppImage)" "$fuente" 2>/dev/null | head -1 | sed 's/\(\.tar\.gz\|\.tar\.xz\|\.tar\.bz2\|\.tgz\|\.tar\.zst\|\.zip\|\.AppImage\).*/\1/')
        [ -n "$u" ] && { echo "$u"; return 0; }
    done
    return 0
}

# Contenedor root de una app portátil bajo $HOME (vacío si no aplica):
# ~/Aplicaciones, ~/Software, ~/Programas, ~/Programs, apps del Toolbox…
contenedor_portatil() {
    local p="$1" d
    d=$(dirname "$p")
    while [ "$d" != "/" ]; do
        case "$d" in
            "$HOME"/Aplicaciones|"$HOME"/Software|"$HOME"/Programas|"$HOME"/Programs|\
            "$HOME"/.local/share/JetBrains/Toolbox/apps|"$HOME"/opt)
                echo "$d"; return 0 ;;
        esac
        d=$(dirname "$d")
    done
    return 0
}

# Carpeta concreta de la app dentro del contenedor. P. ej. con
# .../Aplicaciones/jetbrains-toolbox-3.8.1.88030/bin/x devuelve
# .../Aplicaciones/jetbrains-toolbox-3.8.1.88030 (donde se extrae su tar.gz).
app_dir_de() {
    local p="$1" d
    d=$(dirname "$p")
    while [ "$d" != "/" ]; do
        case "$d" in
            "$HOME"/Aplicaciones|"$HOME"/Software|"$HOME"/Programas|"$HOME"/Programs|\
            "$HOME"/.local/share/JetBrains/Toolbox/apps|"$HOME"/opt)
                echo "$p"; return 0 ;;
        esac
        p="$d"; d=$(dirname "$d")
    done
    return 0
}

# Según lo que HAYA, para cada app portátil (JetBrains Toolbox, HeidiSQL…):
#   - si su archivo original (tar.gz/AppImage…) sigue en el disco → viaja;
#   - si no, viaja la URL de donde se descargó (historial de descargas);
#   - si NO se sabe de qué URL viene y no queda el archivo, viaja su carpeta
#     entera (única forma de que funcione en el otro PC).
# en el otro PC, instalar.sh decide: extrae el archivo, baja la URL o,
# si venía la carpeta, la recoloca. (Se llama DESPUÉS de
# salvar_recursos_lanzadores, porque usa relaunchers/origen.txt para saber
# dónde vivía cada app.)
salvar_artefactos_origen() {
    local tmp="$1"
    local rec="$tmp/relaunchers"
    local ori="$tmp/paquetes/origen"
    local pkgs ad base arch u cont dir
    pkgs=$(cat "$tmp/paquetes/navbar.txt" "$tmp/paquetes/manuales.txt" 2>/dev/null | sort -u | tr '\n' ' ')
    [ -d "$rec" ] || return 0

    # (1) carpetas de apps portátiles que los lanzadores usan por ruta
    local appdirs="" tipo ruta
    while IFS='|' read -r tipo ruta _; do
        [ "$tipo" = "Exec" ] || [ "$tipo" = "ICON" ] || continue
        [ -n "$ruta" ] || continue
        # No se descartan las rutas bajo $HOME/.local: los ejecutables de las apps
        # del JetBrains Toolbox viven en ~/.local/share/JetBrains/Toolbox/apps/*
        # (contenedor_portatil decide si una ruta es o no una app portátil).
        case "$ruta" in /usr/*|/opt/*) continue;; esac
        cont=$(contenedor_portatil "$ruta") || continue
        [ -n "$cont" ] || continue
        dir=$(app_dir_de "$ruta") || continue
        [ -n "$dir" ] || continue
        case " $appdirs " in *" $dir "*) continue;; esac
        appdirs="$appdirs $dir"
    done < "$rec/origen.txt"

    [ -n "$appdirs" ] || return 0
    mkdir -p "$ori"

    # (2) por cada app: archivo original en disco, o su URL de descarga
    for ad in $appdirs; do

    # Normalizar nombre: los Toolbox crean DUPLICADOS con sufijo "-2"
    # Para exportar usaremos el nombre limpio (android-studio en lugar de android-studio-2)
    base_orig=$(basename "$ad")
    # Quita posible sufijo "-N" (duplicado de Toolbox)
    base=$(printf '%s' "$base_orig" | sed -E 's/-[0-9]+$//')
    # Solo viaja una variante por app (la primera)
    case " $exportados " in *" $base "*) continue;; esac
    exportados="$exportados $base"
        # si es un paquete apt (p. ej. blender), que lo instale apt
        case " $pkgs " in
            *" $base "*) grep -rq "^Package: ${base%%:*}$" /var/lib/apt/lists/ 2>/dev/null && continue ;;
        esac
        # (a) ¿sigue su archivo original en el disco?
        arch=$(find "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio" "$HOME/.cache" \
            -maxdepth 3 \( -iname "*${base}*.tar.gz" -o -iname "*${base}*.tar.xz" \
            -o -iname "*${base}*.tar.bz2" -o -iname "*${base}*.tgz" \
            -o -iname "*${base}*.tar.zst" -o -iname "*${base}*.zip" \
            -o -iname "*${base}*.AppImage" \) 2>/dev/null | head -1)
        if [ -n "$arch" ] && [ -f "$arch" ]; then
            cp -f "$arch" "$ori/" 2>/dev/null || continue
            cont=$(contenedor_portatil "$ad")
            echo "ART|$base|$(basename "$arch")|$cont" >> "$ori/mapa.txt" 2>/dev/null
            continue
        fi
        # (b) ¿está su URL de descarga en el historial?
        u=$(url_archivo_de "$base")
        if [ -n "$u" ]; then
            [ -f "$tmp/paquetes/urls.txt" ] || : > "$tmp/paquetes/urls.txt"
            cont=$(contenedor_portatil "$ad")
            echo "URL|$base|$u|$cont" >> "$tmp/paquetes/urls.txt"
            continue
        fi
        # (c) sin archivo original ni URL: viaja su carpeta entera, literal
        # (HeidiSQL, Android Studio, IntelliJ IDEA, PyCharm del Toolbox…:
        # necesitan su jbr/, plugins/ y resto de la instalación, no basta un
        # binario suelto). En el otro PC instalar.sh la recoloca tal cual.
        mkdir -p "$ori/apps"
        if [ ! -e "$ori/apps/$base" ]; then
            cp -a "$ad" "$ori/apps/$base" 2>/dev/null || continue
        fi
        echo "APP|$base|$ad" >> "$ori/mapa.txt"
    done

    # contadores globales para el resumen (se recalculan: las URLs de portátiles
    # se suman a las ya guardadas por el bloque de .deb)
    n_urls_export=$(sed -n '/^URL|/p' "$tmp/paquetes/urls.txt" 2>/dev/null | wc -l)
    n_artefactos_export=$(grep -cE '^(ART|APP)\|' "$ori/mapa.txt" 2>/dev/null || echo 0)
}

plank_exportar() {
    local carpeta
    carpeta=$("${ZEN[@]}" --file-selection --directory \
        --title="Elegir carpeta donde guardar la copia de seguridad" \
        --filename="$HOME/" 2>/dev/null)
    [ -z "$carpeta" ] && return

    local que
    que=$("${ZEN[@]}" --list --title="Qué quieres guardar" \
        --text="¿Cómo quieres hacer el respaldo?" \
        --column="Opción" --column="Qué hace" \
        "Solo navbar (sin instalar nada)" "Configuración del dock/navbar + tus apps (Safari→Brave…). SIN listas de paquetes" \
        "Navbar + paquetes del navbar" "Lo anterior + la lista de paquetes de tus apps ancladas (para reinstalarlas)" \
        "Navbar + todos los paquetes manuales" "Lo anterior + la lista de TODOS los paquetes que instalaste manualmente" \
        --width=760 --height=340 2>/dev/null)
    [ -z "$que" ] && return

    case "$que" in
        "Solo navbar (sin instalar nada)") f_config=true f_apps=true f_scripts=true f_autostart=true f_iconos=true ;;
        "Navbar + paquetes del navbar") f_config=true f_apps=true f_scripts=true f_autostart=true f_iconos=true f_navbar=true ;;
        "Navbar + todos los paquetes manuales") f_config=true f_apps=true f_scripts=true f_autostart=true f_iconos=true f_navbar=true f_manuales=true ;;
        *) return ;;
    esac

    if ! $f_config && ! $f_apps && ! $f_scripts && ! $f_autostart && ! $f_iconos; then
        # todo desmarcado no serviría de nada
        if ! "${ZEN[@]}" --question --title="Nada seleccionado" \
            --text="No has marcado nada que guardar.\\n¿Quieres guardar SOLO la lista de paquetes?" 2>/dev/null; then
            return
        fi
    fi

    local destino="$carpeta/backup-plank-$FECHA.tar.gz"
    local tmp
    tmp=$(mktemp -d)

    if $f_config && [ -d "$PLANK_CONFIG" ]; then
        mkdir -p "$tmp/config"
        cp -r "$PLANK_CONFIG"/. "$tmp/config/"
    fi
    if $f_config && [ -d "$PLANK_THEMES" ]; then
        mkdir -p "$tmp/themes"
        cp -r "$PLANK_THEMES"/. "$tmp/themes/"
    fi
    if $f_config && command -v dconf >/dev/null 2>&1; then
        dconf dump /net/launchpad/plank/ > "$tmp/plank.dconf" 2>/dev/null || true
    fi

    if $f_apps && [ -d "$APPS_DIR" ]; then
        mkdir -p "$tmp/applications"
        cp -r "$APPS_DIR"/. "$tmp/applications/"
    fi
    if $f_scripts && [ -d "$BIN_DIR" ]; then
        mkdir -p "$tmp/bin"
        cp -r "$BIN_DIR"/. "$tmp/bin/"
    fi
    if $f_autostart && [ -d "$AUTOSTART_DIR" ]; then
        mkdir -p "$tmp/autostart"
        cp -r "$AUTOSTART_DIR"/. "$tmp/autostart/"
    fi
    if $f_iconos && [ -d "$ICONS_CUSTOM" ]; then
        mkdir -p "$tmp/icons"
        cp -r "$ICONS_CUSTOM"/. "$tmp/icons/"
    fi

    # ── Lanzadores: guardar los .desktop reales y sus recursos ──
    # Para que al importar en cualquier PC los lanzadores funcionen IGUAL,
    # aunque el .desktop original haya cambiado de sitio o de contenido.
    salvar_recursos_lanzadores "$tmp"

    # ── Listas de paquetes (solo si se pidieron) ──
    n_navbar_export=0 n_manual_export=0 n_lanzadores_export=0 n_apt_export=0 n_debs_export=0 n_urls_export=0 n_artefactos_export=0
    [ -f "$tmp/relaunchers/origen.txt" ] && n_lanzadores_export=$(grep -c "^DESKTOP|" "$tmp/relaunchers/origen.txt" 2>/dev/null || echo 0)
    if [ -e /var/lib/dpkg/status ] && { $f_navbar || $f_manuales; }; then
        mkdir -p "$tmp/paquetes"
        if $f_navbar; then
            paquetes_navbar > "$tmp/paquetes/navbar.txt" 2>/dev/null || true
            n_navbar_export=$(wc -l < "$tmp/paquetes/navbar.txt" 2>/dev/null || echo 0)
        fi
        if $f_manuales; then
            apt-mark showmanual 2>/dev/null | grep -v '^$' > "$tmp/paquetes/manuales.txt"
            n_manual_export=$(wc -l < "$tmp/paquetes/manuales.txt" 2>/dev/null || echo 0)
        fi

        # ── Repositorios y claves apt del sistema ──
        # Para poder reinstalar apps de PPAs/terceros (Brave, VS Code, Docker,
        # Unity Hub…) en un PC que no los tenga configurados. La URL del repo
        # viaja DENTRO de cada fuente: cada .list/.sources lleva su URI,
        # Suites, Components y Signed-By. Lo que faltaba era asegurar que la
        # CLAVE de firma también viajara, viva donde viva (/etc/apt/keyrings
        # o /usr/share/keyrings). Así, al importar se vuelve a montar cada
        # repositorio igual que estaba (URL + clave), sin depender de la red.
        local apt_tmp="$tmp/apt"
        mkdir -p "$apt_tmp/sources.list.d" "$apt_tmp/keyrings"
        if [ -d /etc/apt/sources.list.d ]; then
            for _f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                [ -f "$_f" ] || continue
                grep -qE '^\s*(deb|Types:\s*deb)' "$_f" 2>/dev/null || continue
                cp -f "$_f" "$apt_tmp/sources.list.d/" 2>/dev/null || true
            done
        fi
        # Claves: NO se copia la carpeta /etc/apt/keyrings entera. Se lee cada
        # fuente (que ya lleva la URL) y se guarda SOLO la clave que referencia:
        # por línea "Signed-By:" (formato .sources) o por "signed-by=" inline
        # en líneas deb (.list). Cada clave viaja con la ruta EXACTA que tenía,
        # para que al importar se coloque otra vez en su mismo sitio.
        local _f2 _sb _kb2
        : > "$apt_tmp/keyrings/origen.txt"
        for _f2 in "$apt_tmp"/sources.list.d/*.list "$apt_tmp"/sources.list.d/*.sources; do
            [ -f "$_f2" ] || continue
            _sb=$(grep -m1 '^[[:space:]]*Signed-By:' "$_f2" 2>/dev/null | sed 's/.*Signed-By:[[:space:]]*//' | tr -d ' \r')
            if [ -z "$_sb" ]; then
                _sb=$(grep -oE 'signed-by=[^[:space:]]+' "$_f2" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ']')
            fi
            [ -n "$_sb" ] || continue
            case "$_sb" in
                /*) [ -f "$_sb" ] || continue
                    _kb2=$(basename "$_sb")
                    if [ ! -f "$apt_tmp/keyrings/$_kb2" ]; then
                        cp -f "$_sb" "$apt_tmp/keyrings/$_kb2" 2>/dev/null || continue
                    fi
                    grep -q "|keyrings/$_kb2$" "$apt_tmp/keyrings/origen.txt" 2>/dev/null || \
                        echo "KEY|$_sb|keyrings/$_kb2" >> "$apt_tmp/keyrings/origen.txt" ;;
            esac
        done
        n_apt_export=$(( $(ls "$apt_tmp/sources.list.d" 2>/dev/null | wc -l) + $(sed -n '/^KEY|/p' "$apt_tmp/keyrings/origen.txt" 2>/dev/null | wc -l) ))

        # ── .deb locales para apps que NO están en ningún repo ──
        # docker-desktop, opencode, ulauncher… se instalaron con un .deb bajado
        # a mano y apt no puede reinstalarlos en otro PC (no tienen repo). Si su
        # .deb original sigue en el disco (Descargas, Documentos, Escritorio o la
        # caché del actualizador), viaja en el respaldo y al importar se
        # reinstala con apt ./… (que resuelve dependencias). Si el .deb ya no
        # existe, sus ejecutables siguen viajando por relaunchers/exec (portátil).
        n_debs_export=0
        mkdir -p "$tmp/paquetes/debs"
        for _p in $(cat "$tmp/paquetes/navbar.txt" "$tmp/paquetes/manuales.txt" 2>/dev/null | sort -u); do
            case "$_p" in ""|*\ *) continue;; esac
            # ¿tiene repo apt? si sí, ya se reinstala solo desde la URL respaldada
            grep -rq "^Package: ${_p%%:*}$" /var/lib/apt/lists/ 2>/dev/null && continue
            _deb=$(find "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio" "$HOME/.cache" \
                -maxdepth 3 -iname "*.deb" 2>/dev/null | while IFS= read -r _f; do
                    case "$(basename "$_f")" in
                        *"${_p}"*) echo "$_f" ;;
                    esac
                done | head -1)
            [ -n "$_deb" ] && [ -f "$_deb" ] && cp -f "$_deb" "$tmp/paquetes/debs/" 2>/dev/null || true
        done
        n_debs_export=$(ls "$tmp/paquetes/debs/" 2>/dev/null | wc -l)
        [ "$n_debs_export" -gt 0 ] || rm -rf "$tmp/paquetes/debs"

        # ── Si el .deb ya no está en el disco: guardar la URL de DONDE se
        #    descargó (historial de descargas de Firefox/Chrome, terminal o
        #    enlace estable conocido) para que instalar.sh lo vuelva a bajar
        #    en el otro PC. Así NO viaja la app entera: viaja solo el enlace.
        n_urls_export=0
        : > "$tmp/paquetes/urls.txt"
        for _p in $(cat "$tmp/paquetes/navbar.txt" "$tmp/paquetes/manuales.txt" 2>/dev/null | sort -u); do
            case "$_p" in ""|*\ *) continue;; esac
            # ¿tiene repo? apt lo instala solo; ¿viaja su .deb? no hace falta URL
            grep -rq "^Package: ${_p%%:*}$" /var/lib/apt/lists/ 2>/dev/null && continue
            ls "$tmp/paquetes/debs/" 2>/dev/null | grep -qi "$_p" && continue
            _url=$(url_deb_de "$_p")
            [ -n "$_url" ] && echo "URL|$_p|$_url" >> "$tmp/paquetes/urls.txt"
        done
        n_urls_export=$(sed -n '/^URL|/p' "$tmp/paquetes/urls.txt" 2>/dev/null | wc -l)
        [ "$n_urls_export" -gt 0 ] || rm -f "$tmp/paquetes/urls.txt"

        # Script de instalación tolerante: solo instala lo que falta y existe
        cat > "$tmp/paquetes/instalar.sh" << 'PAQEOF'
#!/bin/bash
# Instala paquetes guardados en una copia de seguridad.
# Solo instala los que EXISTAN en los repositorios y NO estén ya instalados.
# Uso:
#   sudo bash instalar.sh                -> instala los manuales (manuales.txt)
#   sudo bash instalar.sh lista.txt      -> instala los de la lista indicada
#   sudo bash instalar.sh pkg1 pkg2 ...  -> instala esos paquetes concretos
[ "$(id -u)" -eq 0 ] || { echo "ERROR: hay que ejecutarlo con sudo."; exit 1; }
cd "$(dirname "$0")" || exit 1

# Hogar del PC de ORIGEN (guardado al exportar): sirve para traducir las
# rutas de apps portátiles al hogar de ESTE PC (sea cual sea el nombre de
# usuario, p. ej. /home/otro/... -> /home/nueva).
ORIGEN_HOME=""
[ -f ../relaunchers/origen.txt ] && ORIGEN_HOME=$(sed -n 's/^ORIGEN_HOME|//p' ../relaunchers/origen.txt 2>/dev/null | head -1)

# Hogar REAL del usuario en ESTE PC: al ejecutarse con sudo, $HOME apunta a
# /root; los apps portátiles deben volver al hogar del usuario (SUDO_USER).
DEST_HOME=""
if [ -n "$SUDO_USER" ]; then
    DEST_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
fi
[ -n "$DEST_HOME" ] || DEST_HOME="$HOME"
[ -n "$ORIGEN_HOME" ] || ORIGEN_HOME="$DEST_HOME"

# Restaurar repositorios y claves apt que venían en la copia (carpeta "apt"
# justo al lado de paquetes/: ../apt). Con cp -rn NO se pisa lo que el PC
# destino ya tenga configurado; solo se añade lo que le falta.
if [ -d ../apt/sources.list.d ]; then
    mkdir -p /etc/apt/sources.list.d
    cp -rn ../apt/sources.list.d/* /etc/apt/sources.list.d/ 2>/dev/null || true
fi
if [ -d ../apt/keyrings ]; then
    # Cada clave se devuelve a la ruta EXACTA que tenía en el PC de origen
    # (p. ej. /usr/share/keyrings/microsoft.gpg de VS Code), usando el mapa
    # keyrings/origen.txt que guardó el export: "KEY|/ruta/exacta|keyrings/nombre".
    if [ -f ../apt/keyrings/origen.txt ]; then
        while IFS='|' read -r _tipo _ruta _rel; do
            [ "$_tipo" = "KEY" ] || continue
            [ -n "$_ruta" ] || continue
            [ -f "../apt/keyrings/$_rel" ] || continue
            mkdir -p "$(dirname "$_ruta")"
            [ -e "$_ruta" ] || cp -f "../apt/keyrings/$_rel" "$_ruta" 2>/dev/null || true
        done < ../apt/keyrings/origen.txt
    fi
    # Cualquier clave sin ruta anotada acaba en el sitio habitual.
    mkdir -p /etc/apt/keyrings
    for _k in ../apt/keyrings/*.gpg ../apt/keyrings/*.asc; do
        [ -f "$_k" ] || continue
        cp -rn "$_k" /etc/apt/keyrings/ 2>/dev/null || true
    done
fi

echo "== Actualizando repositorios =="
apt-get update -qq
instalados=0; saltados=0; errores=0
instalar_uno() {
    local pkg="$1"
    [ -n "$pkg" ] || return
    pkg="${pkg%%:*}"
    case "$pkg" in *[[:space:]]*) return;; esac
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        saltados=$((saltados+1)); return
    fi
    if apt-cache show "$pkg" >/dev/null 2>&1; then
        if apt-get install -y --no-install-recommends "$pkg" >/dev/null 2>&1; then
            instalados=$((instalados+1))
        else
            errores=$((errores+1))
            echo "ERROR instalando: $pkg"
        fi
    else
        saltados=$((saltados+1))
    fi
}
if [ $# -eq 0 ]; then
    LISTA="manuales.txt"
    [ -s "$LISTA" ] || { echo "No hay lista de paquetes en la copia."; exit 0; }
    while IFS= read -r p; do instalar_uno "$p"; done < "$LISTA"
elif [ $# -eq 1 ] && [ -f "$1" ]; then
    while IFS= read -r p; do instalar_uno "$p"; done < "$1"
else
    for p in "$@"; do instalar_uno "$p"; done
fi

# Instalar los archivos .deb locales que venían en la copia (apps sin
# repositorio: docker-desktop, opencode…). Se usa apt ./para que resuelva
# dependencias, igual que al instalarlas a mano en su día.
if [ -d debs ] && ls debs/*.deb >/dev/null 2>&1; then
    echo "== Instalando archivos .deb del respaldo =="
    for _deb in debs/*.deb; do
        [ -f "$_deb" ] || continue
        if apt-get install -y "./$_deb" >/dev/null 2>&1; then
            instalados=$((instalados+1))
        else
            errores=$((errores+1))
            echo "ERROR instalando: $_deb"
        fi
    done
fi

# Apps portátiles (JetBrains Toolbox, HeidiSQL…): el export guardó su archivo
# original (tar.gz/AppImage/zip) en "origen/" o su URL. Aquí se extrae/copia
# en la misma carpeta donde vivía en el PC de origen (mapa.txt).
if [ -d origen ] && [ -s origen/mapa.txt ]; then
    echo "== Extrayendo apps portátiles del respaldo (origen/) =="
    while IFS='|' read -r _tipo _app _fich _cont; do
        case "$_tipo" in
            ART)
        [ -f "origen/$_fich" ] || continue
        _fpath=$(readlink -f "origen/$_fich") || continue
        # traducir hogar de origen a este PC
        _cont="${_cont/#$ORIGEN_HOME/$DEST_HOME}"
        mkdir -p "$_cont" 2>/dev/null || continue
        echo "extrayendo $_fich  ->  $_cont/"
        case "$_fich" in
            *.tar.gz|*.tgz)  tar -xzf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.xz)        tar -xJf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.bz2)       tar -xjf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.tar.zst)       tar --zstd -xf "$_fpath" -C "$_cont" 2>/dev/null ;;
            *.zip)           unzip -q -o "$_fpath" -d "$_cont" 2>/dev/null ;;
            *.AppImage)      chmod +x "$_fpath" 2>/dev/null; cp -f "$_fpath" "$_cont/" 2>/dev/null ;;
            *) continue ;;
        esac
                ;;
            APP)
        # app portátil pequeña que viaja con su carpeta entera (HeidiSQL…)
        _dest="${_fich/#$ORIGEN_HOME/$DEST_HOME}"
        [ -d "origen/apps/$_app" ] || continue
        mkdir -p "$_dest" 2>/dev/null || continue
        cp -rn "origen/apps/$_app"/. "$_dest"/ 2>/dev/null || continue
                ;;
            *) continue ;;
        esac
        instalados=$((instalados+1))
    done < origen/mapa.txt
fi

# Apps cuyo .deb original ya no estaba en el disco de origen: instalar.sh
# vuelve a bajarlo DESDE DONDE SE DESCARGÓ (la URL viaja en urls.txt).
# Así no hace falta que la app entera viaje: solo el enlace.
if [ -s urls.txt ]; then
    echo "== Bajando .deb/tar.gz desde su origen (urls.txt) =="
    while IFS='|' read -r _tipo _p _u _tgt; do
        [ "$_tipo" = "URL" ] || continue
        _nom="${_u%%\?*}"; _nom=$(basename "$_nom")
        [ -n "$_nom" ] || continue
        echo "bajando $_p  ->  $_u"
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$_nom" "$_u" 2>/dev/null || { errores=$((errores+1)); echo "ERROR bajando: $_u"; continue; }
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$_nom" "$_u" 2>/dev/null || { errores=$((errores+1)); echo "ERROR bajando: $_u"; continue; }
        else
            errores=$((errores+1)); echo "ERROR: ni wget ni curl para $_p"; continue
        fi
        # .deb -> se instala con apt (resuelve dependencias); comprimidos ->
        # se extraen en la carpeta que ocupaban en el PC de origen (campo 4).
        case "$_nom" in
            *.deb)
                if apt-get install -y "./$_nom" >/dev/null 2>&1; then
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1)); echo "ERROR instalando: $_nom"
                fi ;;
            *)
                if [ -n "$_tgt" ]; then
                    _tgt="${_tgt/#$ORIGEN_HOME/$DEST_HOME}"
                    mkdir -p "$_tgt" 2>/dev/null || { errores=$((errores+1)); echo "ERROR destino: $_tgt"; continue; }
                    echo "extrayendo $_nom  ->  $_tgt/"
                    case "$_nom" in
                        *.tar.gz|*.tgz)  tar -xzf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.xz)        tar -xJf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.bz2)       tar -xjf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.tar.zst)       tar --zstd -xf "$_nom" -C "$_tgt" 2>/dev/null ;;
                        *.zip)           unzip -q -o "$_nom" -d "$_tgt" 2>/dev/null ;;
                        *.AppImage)      chmod +x "$_nom" 2>/dev/null; cp -f "$_nom" "$_tgt/" 2>/dev/null ;;
                        *) continue ;;
                    esac
                    instalados=$((instalados+1))
                else
                    errores=$((errores+1)); echo "ERROR: sin destino para $_nom"
                fi ;;
        esac
    done < urls.txt
fi

echo
echo "== Resumen =="
echo "Instalados: $instalados"
echo "Ya estaban o no disponibles (saltados): $saltados"
echo "Errores: $errores"
PAQEOF
        chmod +x "$tmp/paquetes/instalar.sh"
    fi

    # ── Artefactos de origen de apps portátiles (según lo que haya) ──
    # Después de conocer los lanzadores: para cada app portátil bajo
    # ~/Aplicaciones u otros contenedores, guarda su archivo original (tar.gz,
    # AppImage…) si sigue en el disco, o su URL de descarga si no. instalar.sh
    # decide al importar: extrae el archivo o baja la URL.
    salvar_artefactos_origen "$tmp"

    tar -czf "$destino" -C "$tmp" . 2>/dev/null
    rm -rf "$tmp"

    if [ -f "$destino" ]; then
        local resumen="• Configuración de Plank y lanzadores"
        $f_apps      && resumen+="\n• Apps personalizadas (Safari→Brave y otras)"
        $f_scripts   && resumen+="\n• Scripts (~/.local/bin)"
        $f_autostart && resumen+="\n• Autostart"
        $f_iconos    && resumen+="\n• Iconos propios"
        [ "$n_lanzadores_export" -gt 0 ] && resumen+="\n• .desktop reales de los $n_lanzadores_export lanzadores + recursos (portátil)"
        [ "$n_apt_export" -gt 0 ]     && resumen+="\n• $n_apt_export repositorios/claves apt (para reinstalar en otro PC)"
        [ "$n_navbar_export" -gt 0 ]  && resumen+="\n• Apps del navbar ($n_navbar_export paquetes)"
        [ "$n_debs_export" -gt 0 ]    && resumen+="\n• .deb locales de apps sin repo ($n_debs_export)"
        [ "$n_artefactos_export" -gt 0 ] && resumen+="\n• Apps portátiles con su fuente (JetBrains, Heidi…): $n_artefactos_export"
        [ "$n_urls_export" -gt 0 ]    && resumen+="\n• URLs para volver a bajar los .deb/.tar.gz en el otro PC ($n_urls_export)"
        [ "$n_manual_export" -gt 0 ]  && resumen+="\n• Paquetes manuales ($n_manual_export)"
        local hay_instalador="no"
        if [ "$n_navbar_export" -gt 0 ] || [ "$n_manual_export" -gt 0 ]; then
            resumen+="\n• Script instalar.sh para reinstalar en otro PC"
            hay_instalador="sí (con instalar.sh)"
        fi
        "${ZEN[@]}" --info --title="Copia de seguridad de Plank" \
            --text="Respaldo guardado en:\\n<b>$destino</b>\\n\\nContiene:\\n$resumen\\n\\nPaquetes para reinstalar: <b>$hay_instalador</b>" 2>/dev/null
    else
        "${ZEN[@]}" --error --title="Error" --text="No se pudo guardar la copia de seguridad." 2>/dev/null
    fi
}

plank_importar() {
    local raiz
    local candidatos=()
    for raiz in "$HOME" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio"; do
        [ -d "$raiz" ] || continue
        while IFS= read -r f; do
            candidatos+=("$f")
        done < <(find "$raiz" -maxdepth 1 -type f \( -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" \) 2>/dev/null)
    done
    IFS=$'\n' candidatos=($(printf "%s\n" "${candidatos[@]}" | sort -u))

    local origen
    origen=$("${ZEN[@]}" --list --title="Copias de seguridad encontradas" \
        --text="Se han detectado automáticamente estas copias. Elige una:" \
        --column="Archivo" "Buscar en otra carpeta..." "${candidatos[@]}" \
        --width=720 --height=380 2>/dev/null)
    [ -z "$origen" ] && return

    if [ "$origen" = "Buscar en otra carpeta..." ]; then
        local carpeta
        carpeta=$("${ZEN[@]}" --file-selection --directory \
            --title="Elegir carpeta donde están las copias de seguridad" \
            --filename="$HOME/" 2>/dev/null)
        [ -z "$carpeta" ] && return
        mapfile -t candidatos < <(find "$carpeta" -maxdepth 1 -type f \( -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" -o -name "*.tar.gz" \) 2>/dev/null | sort)
        if [ "${#candidatos[@]}" -eq 0 ]; then
            "${ZEN[@]}" --warning --title="Sin copias de seguridad" \
                --text="No se encontraron copias (.tar.gz) en:\\n$carpeta" 2>/dev/null
            return
        fi
        origen=$("${ZEN[@]}" --list --title="Copias de seguridad encontradas" \
            --text="Selecciona la copia a restaurar:" \
            --column="Archivo" "${candidatos[@]}" \
            --width=640 --height=360 2>/dev/null)
        [ -z "$origen" ] && return
    fi

    if ! tar -tzf "$origen" >/dev/null 2>&1; then
        "${ZEN[@]}" --error --title="Error" \
            --text="El archivo seleccionado no es una copia válida." 2>/dev/null
        return
    fi

    local modo
    modo=$("${ZEN[@]}" --list --title="Cómo restaurar" \
        --text="¿Cómo quieres aplicar la copia de seguridad?" \
        --column="Opción" --column="Descripción" \
        "Mezclar" "Dejar lo que ya tiene el panel y añadir lo que falte de la copia" \
        "Reemplazar" "Borrar la configuración actual y restaurar solo lo de la copia" \
        --width=680 --height=320 2>/dev/null)
    [ -z "$modo" ] && return

    if [ "$modo" = "Reemplazar" ]; then
        if ! "${ZEN[@]}" --question --title="Reemplazar configuración" \
            --text="Se borrará la configuración actual de Plank y sus lanzadores.\\n\\nSe hará una copia de seguridad de lo actual antes.\\n¿Continuar?" 2>/dev/null; then
            return
        fi
    fi

    # Parar Plank ANTES de tocar nada: Plank se lanza desde el propio dock,
    # así que si sigue corriendo, al terminar escribe su dock-items (el orden
    # viejo) en dconf y pisa el orden restaurado. Se vuelve a lanzar al final.
    if pgrep -x plank >/dev/null 2>&1; then
        pkill -x plank 2>/dev/null || true
        sleep 1
    fi

    # Copia de seguridad de la configuración actual
    [ -d "$PLANK_CONFIG" ] && cp -r "$PLANK_CONFIG" "$PLANK_CONFIG.bak-$FECHA" 2>/dev/null || true

    local tmp
    tmp=$(mktemp -d)
    tar -xzf "$origen" -C "$tmp" 2>/dev/null

    if [ "$modo" = "Reemplazar" ]; then
        if [ -d "$tmp/config" ]; then
            rm -rf "$PLANK_CONFIG"
            mkdir -p "$HOME/.config"
            cp -r "$tmp/config" "$PLANK_CONFIG"
        fi
        if [ -d "$tmp/themes" ]; then
            rm -rf "$PLANK_THEMES"
            mkdir -p "$HOME/.local/share/plank"
            cp -r "$tmp/themes" "$PLANK_THEMES"
        fi
        if [ -f "$tmp/plank.dconf" ] && command -v dconf >/dev/null 2>&1; then
            dconf load /net/launchpad/plank/ < "$tmp/plank.dconf" 2>/dev/null || true
        fi
    else
        # MEZCLAR: conservar lo actual y añadir solo lo que falte
        mkdir -p "$PLANK_CONFIG/dock1/launchers"
        if [ -d "$tmp/config/dock1/launchers" ]; then
            for dock in "$tmp"/config/dock1/launchers/*.dockitem; do
                [ -f "$dock" ] || continue
                local base; base=$(basename "$dock")
                local destino_dock="$PLANK_CONFIG/dock1/launchers/$base"
                if [ ! -f "$destino_dock" ]; then
                    cp "$dock" "$destino_dock"
                fi
            done
        fi
        if [ -d "$tmp/themes" ]; then
            mkdir -p "$PLANK_THEMES"
            for tema in "$tmp"/themes/*/; do
                [ -d "$tema" ] || continue
                local nombre_tema; nombre_tema=$(basename "$tema")
                [ -d "$PLANK_THEMES/$nombre_tema" ] || cp -r "$tema" "$PLANK_THEMES/$nombre_tema"
            done
        fi
    fi

    # ── Apps personalizadas (Safari→Brave y otras) ──
    if [ -d "$tmp/applications" ]; then
        mkdir -p "$APPS_DIR"
        for f in "$tmp"/applications/*; do
            [ -e "$f" ] || continue
            local basef; basef=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$APPS_DIR/$basef" ]; then
                cp -r "$f" "$APPS_DIR/$basef"
            fi
        done
    fi
    if [ -d "$tmp/bin" ]; then
        mkdir -p "$BIN_DIR"
        for f in "$tmp"/bin/*; do
            [ -e "$f" ] || continue
            local baseb; baseb=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$BIN_DIR/$baseb" ]; then
                cp -r "$f" "$BIN_DIR/$baseb"
                chmod +x "$BIN_DIR/$baseb" 2>/dev/null || true
            fi
        done
    fi
    if [ -d "$tmp/autostart" ]; then
        mkdir -p "$AUTOSTART_DIR"
        for f in "$tmp"/autostart/*; do
            [ -e "$f" ] || continue
            local basea; basea=$(basename "$f")
            if [ "$modo" = "Reemplazar" ] || [ ! -e "$AUTOSTART_DIR/$basea" ]; then
                cp -r "$f" "$AUTOSTART_DIR/$basea"
            fi
        done
    fi
    if [ -d "$tmp/icons" ]; then
        mkdir -p "$ICONS_CUSTOM"
        cp -r "$tmp"/icons/. "$ICONS_CUSTOM/"
    fi

    # ── Corregir rutas de usuario (para que funcione en otro PC) ──
    # Los .desktop y lanzadores guardan /home/USUARIO_ORIGEN/... → /home/$USER
    if [ -d "$PLANK_CONFIG/dock1/launchers" ]; then
        sed -i "s|/home/[^/]*/|/home/$USER/|g" "$PLANK_CONFIG"/dock1/launchers/*.dockitem 2>/dev/null || true
    fi
    if [ -d "$APPS_DIR" ]; then
        # En los .desktop se corrigen Exec, Icon y Path
        find "$APPS_DIR" -maxdepth 1 -name "*.desktop" -exec \
            sed -i "s|/home/[^/]*/|/home/$USER/|g" {} + 2>/dev/null || true
    fi
    if [ -d "$AUTOSTART_DIR" ]; then
        find "$AUTOSTART_DIR" -maxdepth 1 -name "*.desktop" -exec \
            sed -i "s|/home/[^/]*/|/home/$USER/|g" {} + 2>/dev/null || true
    fi

    # ── Restaurar los .desktop reales de los lanzadores y reescribir los
    #    .dockitem que apunten a rutas que no existen en este PC ──
    restaurar_recursos_lanzadores "$tmp"

    # ── Asegurar el orden de los lanzadores en dconf (dock-items): que la
    #    lista tenga TODOS los dockitem existentes, en su orden, y que a
    #    los nuevos (modo Mezclar) se les asigne posición al final ──
    orden_dock_asegurar

    # ── Reinstalar paquetes incluidos en la copia (tú eliges) ──
    if [ -f "$tmp/paquetes/instalar.sh" ]; then
        local opciones_paq=()
        [ -s "$tmp/paquetes/navbar.txt" ]   && opciones_paq+=("Apps del navbar/dock ($(wc -l < "$tmp/paquetes/navbar.txt"))")
        [ -s "$tmp/paquetes/manuales.txt" ] && opciones_paq+=("Paquetes instalados manualmente ($(wc -l < "$tmp/paquetes/manuales.txt"))")

        local eleccion
        if [ "${#opciones_paq[@]}" -gt 0 ]; then
            eleccion=$("${ZEN[@]}" --list --title="Reinstalar paquetes" \
                --text="La copia incluye paquetes instalados.\\nSelecciona qué reinstalar (puedes marcar varios con Ctrl+clic):" \
                --column="Elegir" --width=680 --height=340 --multiple \
                "${opciones_paq[@]}" 2>/dev/null)
        else
            eleccion=""
        fi

        if [ -n "$eleccion" ]; then
            local lista_sel="$tmp/paquetes/seleccion.txt"
            : > "$lista_sel"
            while IFS= read -r op; do
                case "$op" in
                    "Apps del navbar/dock"*) cat "$tmp/paquetes/navbar.txt" >> "$lista_sel" ;;
                    "Paquetes instalados manualmente"*) cat "$tmp/paquetes/manuales.txt" >> "$lista_sel" ;;
                esac
            done <<< "$eleccion"
            sort -u "$lista_sel" -o "$lista_sel"

            if [ -s "$lista_sel" ]; then
                local pass
                pass=$("${ZEN[@]}" --password --title="Contraseña de administrador" \
                    --text="Introduce tu contraseña para instalar los <b>$(wc -l < "$lista_sel")</b> paquetes seleccionados:" 2>/dev/null)
                if [ -n "$pass" ]; then
                    (
                        echo "$pass" | sudo -S bash "$tmp/paquetes/instalar.sh" "$lista_sel" > /tmp/plank-paquetes.log 2>&1
                        echo "100"
                    ) | "${ZEN[@]}" --progress --pulsate --auto-close \
                        --title="Instalando paquetes" \
                        --text="Instalando los paquetes seleccionados...\\nEsto puede tardar unos minutos." 2>/dev/null
                    resumen=$(tail -n 5 /tmp/plank-paquetes.log 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
                    "${ZEN[@]}" --info --title="Paquetes" \
                        --text="Listo. Se instaló lo que faltaba (saltando lo que ya estaba o no existe).\\n\\n<b>Resumen:</b>\\n$resumen\\n\\nLog completo en /tmp/plank-paquetes.log" 2>/dev/null
                fi
            else
                "${ZEN[@]}" --info --title="Paquetes" \
                    --text="No hay paquetes instalables en la copia. Se restauró la configuración de Plank igualmente." 2>/dev/null
            fi
        fi
    fi

    rm -rf "$tmp"

    plank_reiniciar

    "${ZEN[@]}" --info --title="Importar copia de Plank" \
        --text="Copia <b>$( [ "$modo" = "Mezclar" ] && echo "mezclada" || echo "restaurada" )</b> correctamente.\\nPlank se ha reiniciado.\\n\\nConfiguración anterior guardada en:\\n$PLANK_CONFIG.bak-$FECHA" 2>/dev/null
}

plank_eliminar() {
    local raiz
    local candidatos=()
    for raiz in "$HOME" "$HOME/Descargas" "$HOME/Documentos" "$HOME/Escritorio"; do
        [ -d "$raiz" ] || continue
        while IFS= read -r f; do
            candidatos+=("$f")
        done < <(find "$raiz" -maxdepth 1 -type f \( -name "backup-plank*.tar.gz" -o -name "plank-backup*.tar.gz" -o -name "*.tar.gz" \) 2>/dev/null)
    done
    IFS=$'\n' candidatos=($(printf "%s\n" "${candidatos[@]}" | sort -u))

    if [ "${#candidatos[@]}" -eq 0 ]; then
        "${ZEN[@]}" --warning --title="Sin copias de seguridad" \
            --text="No se encontraron copias (.tar.gz) en tu home, Descargas, Documentos o Escritorio." 2>/dev/null
        return
    fi

    local elegida
    elegida=$("${ZEN[@]}" --list --title="Eliminar copia de seguridad" \
        --text="Selecciona la copia que quieres eliminar:" \
        --column="Archivo" "${candidatos[@]}" \
        --width=720 --height=380 2>/dev/null)
    [ -z "$elegida" ] && return

    if ! "${ZEN[@]}" --question --title="Confirmar eliminación" \
        --text="Se eliminará para siempre:\\n<b>$elegida</b>\\n\\n¿Continuar?" 2>/dev/null; then
        return
    fi

    if rm -f "$elegida"; then
        "${ZEN[@]}" --info --title="Eliminar copia de seguridad" \
            --text="Copia eliminada:\\n$elegida" 2>/dev/null
    else
        "${ZEN[@]}" --error --title="Error" --text="No se pudo eliminar:\\n$elegida" 2>/dev/null
    fi
}

# Si el script se ejecuta directamente (no se “sourcea” para pruebas),
# se muestra el menú principal; si se importa como librería no pasa nada.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ACCION=$("${ZEN[@]}" --list --title="Copia de seguridad de Plank" \
        --text="¿Qué quieres hacer con la configuración de Plank?" \
        --column="Acción" --column="Descripción" \
        "Exportar" "Guardar una copia (puedes elegir qué incluir)" \
        "Importar" "Restaurar una copia de seguridad guardada" \
        "Eliminar copia" "Borrar una copia de seguridad guardada" \
        --width=680 --height=360 2>/dev/null)

    case "$ACCION" in
        Exportar) plank_exportar ;;
        Importar) plank_importar ;;
        "Eliminar copia") plank_eliminar ;;
        *) exit 0 ;;
    esac
fi