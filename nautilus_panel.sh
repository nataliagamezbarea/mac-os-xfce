#!/bin/bash

DIR=$(cd "$(dirname "$0")" && pwd)
source "$DIR/comun.sh"

nautilus_scripts_atajos() {
    step "Anadiendo scripts de atajos a Nautilus"
    local scripts_dir="$HOME/.local/share/nautilus/scripts"
    mkdir -p "$scripts_dir"

    cat > "$scripts_dir/+ Anadir atajo aqui" << 'SCRIPTEOF'
#!/bin/bash
RUTA="${NAUTILUS_SCRIPT_CURRENT_URI#file://}"
RUTA=$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$RUTA" 2>/dev/null || echo "$RUTA")
NOMBRE=$(zenity --entry --title="Anadir atajo" --text="Nombre para el atajo de:\n<b>$RUTA</b>" --entry-text="$(basename "$RUTA")" --width=400 2>/dev/null)
[ -z "$NOMBRE" ] && exit 0
BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$(dirname "$BOOKMARKS")"
touch "$BOOKMARKS"
ENTRADA="file://$RUTA $NOMBRE"
if grep -qF "file://$RUTA" "$BOOKMARKS"; then
    zenity --info --title="Atajo existente" --text="Ya existe un atajo para esta carpeta." --width=300 2>/dev/null
else
    echo "$ENTRADA" >> "$BOOKMARKS"
    zenity --info --title="Atajo anadido" --text="Atajo <b>$NOMBRE</b> anadido a la barra lateral." --width=300 2>/dev/null
fi
SCRIPTEOF
    chmod +x "$scripts_dir/+ Anadir atajo aqui"

    cat > "$scripts_dir/- Eliminar atajo de aqui" << 'SCRIPTEOF'
#!/bin/bash
RUTA="${NAUTILUS_SCRIPT_CURRENT_URI#file://}"
RUTA=$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$RUTA" 2>/dev/null || echo "$RUTA")
BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
if grep -qF "file://$RUTA" "$BOOKMARKS"; then
    sed -i "\|file://$RUTA|d" "$BOOKMARKS"
    zenity --info --title="Atajo eliminado" --text="Atajo eliminado de la barra lateral." --width=300 2>/dev/null
else
    zenity --info --title="Sin atajo" --text="Esta carpeta no tiene atajo en la barra lateral." --width=300 2>/dev/null
fi
SCRIPTEOF
    chmod +x "$scripts_dir/- Eliminar atajo de aqui"

    info "Scripts de atajos instalados en Nautilus"
}

nautilus_scripts_abrir_con() {
    step "Configurando acciones de menu contextual en Nautilus"
    local scripts_dir="$HOME/.local/share/nautilus/scripts"
    mkdir -p "$scripts_dir"

    if ! dpkg -l filemanager-actions &>/dev/null 2>&1; then
        apt_silencioso install filemanager-actions 2>/dev/null || \
        apt_silencioso install nautilus-actions 2>/dev/null || true
    fi

    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/gestor-acciones-nautilus.desktop << 'DESKEOF'
[Desktop Entry]
Type=Application
Name=Gestor de Acciones Nautilus
Comment=Anadir y editar acciones del menu contextual de Nautilus
Exec=fma-config-tool
Icon=filemanager-actions
Terminal=false
Categories=Utility;
NoDisplay=true
DESKEOF
    chmod +x ~/.local/share/applications/gestor-acciones-nautilus.desktop 2>/dev/null || true

    info "filemanager-actions instalado - usa fma-config-tool para gestionar acciones"

    cat > "$scripts_dir/+ Crear accion Abrir con..." << 'SCRIPTEOF'
#!/bin/bash
APPS_RAW=$(find /usr/share/applications ~/.local/share/applications -name "*.desktop" 2>/dev/null | while read f; do
        name=$(grep -m1 "^Name=" "$f" | cut -d= -f2-)
        exec=$(grep -m1 "^Exec=" "$f" | cut -d= -f2- | sed "s/ %[uUfF]//g;s/ --.*//")
        icon=$(grep -m1 "^Icon=" "$f" | cut -d= -f2-)
        nodisplay=$(grep -m1 "^NoDisplay=" "$f" | cut -d= -f2-)
        [ "$nodisplay" = "true" ] && continue
        [ -z "$name" ] || [ -z "$exec" ] && continue
        echo "$name|$exec|$icon"
    done | sort -u)

SELECCION=$(echo "$APPS_RAW" | zenity --list --title="Selecciona una aplicacion" \
    --text="Elige la app para abrir la carpeta:" \
    --column="Aplicacion" --column="Comando" --column="Icono" \
    --width=500 --height=500 --print-column=ALL --separator="|" 2>/dev/null)
[ -z "$SELECCION" ] && exit 0

APP_NOMBRE=$(echo "$SELECCION" | cut -d"|" -f1)
APP_CMD=$(echo "$SELECCION" | cut -d"|" -f2)
APP_ICON=$(echo "$SELECCION" | cut -d"|" -f3)

NOMBRE=$(zenity --entry --title="Nombre del atajo" \
    --text="Nombre que aparecera en el menu contextual:" \
    --entry-text="Abrir con $APP_NOMBRE" --width=400 2>/dev/null)
[ -z "$NOMBRE" ] && exit 0

ACTION_DIR="$HOME/.local/share/file-manager/actions"
mkdir -p "$ACTION_DIR"
ACTION_ID="custom-$(echo "$NOMBRE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"

cat > "$ACTION_DIR/${ACTION_ID}.desktop" << ENDACTION
[Desktop Entry]
Type=Action
Name=$NOMBRE
Icon=$APP_ICON
Profiles=profile-zero;

[X-Action-Profile profile-zero]
MimeTypes=inode/directory;
Exec=$APP_CMD %f
ENDACTION

nautilus -q 2>/dev/null; sleep 1; nautilus &
zenity --info --title="Accion creada" --text="<b>$NOMBRE</b> aparecera directamente en el menu contextual." --width=350 2>/dev/null
SCRIPTEOF
    chmod +x "$scripts_dir/+ Crear accion Abrir con..."
    info "Generador de acciones contextuales instalado en Nautilus"
}

nautilus_scripts_panel() {
    step "Anadiendo gestor de menu contextual a Nautilus"
    local scripts_dir="$HOME/.local/share/nautilus/scripts"
    mkdir -p "$scripts_dir"

    cat > "$scripts_dir/Gestionar menu contextual" << 'SCRIPTEOF'
#!/bin/bash
ACTIONS_DIR="$HOME/.local/share/file-manager/actions"
mkdir -p "$ACTIONS_DIR"

_listar_apps() {
    while IFS= read -r f; do
        nodisplay=$(grep -m1 "^NoDisplay=" "$f" 2>/dev/null | cut -d= -f2-)
        [ "$nodisplay" = "true" ] && continue
        onlyshowin=$(grep -m1 "^OnlyShowIn=" "$f" 2>/dev/null | cut -d= -f2-)
        [ -n "$onlyshowin" ] && continue
        name=$(grep -m1 "^Name=" "$f" 2>/dev/null | cut -d= -f2-)
        exec_val=$(grep -m1 "^Exec=" "$f" 2>/dev/null | cut -d= -f2- | sed 's/ %[uUfFdDnNickvm]//g')
        icon=$(grep -m1 "^Icon=" "$f" 2>/dev/null | cut -d= -f2-)
        [ -z "$name" ] || [ -z "$exec_val" ] && continue
        echo "${name}|${f}|${icon}|${exec_val}"
    done < <(find /usr/share/applications ~/.local/share/applications -maxdepth 1 -name "*.desktop" 2>/dev/null | sort -u)
}

_listar_acciones() {
    while IFS= read -r f; do
        nombre=$(grep -m1 "^Name=" "$f" 2>/dev/null | cut -d= -f2-)
        mime=$(grep -m1 "^MimeTypes=" "$f" 2>/dev/null | cut -d= -f2-)
        exec_val=$(grep -m1 "^Exec=" "$f" 2>/dev/null | cut -d= -f2-)
        [ -z "$nombre" ] && continue
        echo "${nombre}|${f}|${mime}|${exec_val}"
    done < <(find "$ACTIONS_DIR" -name "*.desktop" 2>/dev/null | sort)
}

_escribir_accion() {
    local id="$1" nombre="$2" icon="$3" exec_val="$4" mime="$5"
    cat > "$ACTIONS_DIR/${id}.desktop" << ENDACTION
[Desktop Entry]
Type=Action
Name=$nombre
Icon=$icon
Profiles=p0;

[X-Action-Profile p0]
MimeTypes=$mime
Exec=$exec_val %f
ENDACTION
}

_refrescar() { nautilus -q 2>/dev/null; sleep 0.8; nautilus &>/dev/null & }

while true; do
    OPCION=$(zenity --list --title="Gestionar menu contextual de Nautilus" \
        --text="Que quieres hacer?" \
        --column="" --column="Accion" --hide-column=1 --print-column=1 \
        --width=420 --height=300 --hide-header \
        "add"  "+  Anadir nueva entrada (Abrir con...)" \
        "edit" "Editar entrada existente" \
        "del"  "Eliminar entrada existente" 2>/dev/null)
    [ -z "$OPCION" ] && exit 0

    if [ "$OPCION" = "add" ]; then
        APP_DATA=$(_listar_apps)
        [ -z "$APP_DATA" ] && zenity --error --text="No se encontraron aplicaciones." --width=300 2>/dev/null && continue
        SEL=$(echo "$APP_DATA" | awk -F'|' '{print $1"\t"$2"\t"$3"\t"$4}' | \
            zenity --list --title="+ Anadir entrada" --text="Selecciona la aplicacion:" \
            --column="App" --column="Desktop" --column="Icono" --column="Comando" \
            --hide-column=2 --hide-column=3 --hide-column=4 \
            --print-column=ALL --separator="|" --width=550 --height=520 2>/dev/null)
        [ -z "$SEL" ] && continue
        APP_NOMBRE=$(echo "$SEL" | cut -d"|" -f1)
        APP_ICON=$(echo "$SEL" | cut -d"|" -f3)
        APP_EXEC=$(echo "$SEL" | cut -d"|" -f4)
        NOMBRE=$(zenity --entry --title="Nombre en el menu" \
            --text="Texto que aparecera en el clic derecho:" \
            --entry-text="Abrir con $APP_NOMBRE" --width=430 2>/dev/null)
        [ $? -ne 0 ] || [ -z "$NOMBRE" ] && continue
        TIPO=$(zenity --list --title="Sobre que aparece?" \
            --column="" --column="Tipo" --hide-column=1 --print-column=1 \
            --width=400 --height=280 --hide-header \
            "inode/directory;" "Carpetas" \
            "application/octet-stream;" "Cualquier archivo" \
            "inode/directory;application/octet-stream;" "Carpetas y archivos" 2>/dev/null)
        [ -z "$TIPO" ] && continue
        ACTION_ID="custom-$(echo "$NOMBRE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
        [ -f "$ACTIONS_DIR/${ACTION_ID}.desktop" ] && \
            zenity --question --title="Ya existe" --text="Ya existe <b>$NOMBRE</b>. Reemplazar?" --width=350 2>/dev/null || continue
        _escribir_accion "$ACTION_ID" "$NOMBRE" "$APP_ICON" "$APP_EXEC" "$TIPO"
        _refrescar
        zenity --info --title="Anadida" --text="<b>$NOMBRE</b> ya aparece en el clic derecho." --width=380 2>/dev/null

    elif [ "$OPCION" = "edit" ]; then
        ACCIONES=$(_listar_acciones)
        [ -z "$ACCIONES" ] && zenity --info --title="Sin entradas" --text="No hay entradas todavia." --width=320 2>/dev/null && continue
        SEL=$(echo "$ACCIONES" | awk -F'|' '{print $1"\t"$2"\t"$3"\t"$4}' | \
            zenity --list --title="Editar entrada" \
            --column="Nombre" --column="Archivo" --column="Tipos" --column="Comando" \
            --hide-column=2 --hide-column=3 --hide-column=4 \
            --print-column=ALL --separator="|" --width=500 --height=400 2>/dev/null)
        [ -z "$SEL" ] && continue
        NOMBRE_ACTUAL=$(echo "$SEL" | cut -d"|" -f1)
        ARCHIVO=$(echo "$SEL" | cut -d"|" -f2)
        MIME_ACTUAL=$(echo "$SEL" | cut -d"|" -f3)
        EXEC_ACTUAL=$(echo "$SEL" | cut -d"|" -f4)
        CAMPO=$(zenity --list --title="Que quieres cambiar?" \
            --column="" --column="Campo" --hide-column=1 --print-column=1 \
            --width=380 --height=280 --hide-header \
            "nombre" "Nombre" "app" "Aplicacion" "tipo" "Tipo de archivo" 2>/dev/null)
        [ -z "$CAMPO" ] && continue
        NUEVO_NOMBRE="$NOMBRE_ACTUAL"; NUEVO_EXEC="$EXEC_ACTUAL"; NUEVO_MIME="$MIME_ACTUAL"
        NUEVO_ICON=$(grep -m1 "^Icon=" "$ARCHIVO" 2>/dev/null | cut -d= -f2-)
        if [ "$CAMPO" = "nombre" ]; then
            NUEVO_NOMBRE=$(zenity --entry --title="Nuevo nombre" --entry-text="$NOMBRE_ACTUAL" --width=430 2>/dev/null)
            [ $? -ne 0 ] || [ -z "$NUEVO_NOMBRE" ] && continue
        elif [ "$CAMPO" = "app" ]; then
            APP_DATA=$(_listar_apps)
            SEL2=$(echo "$APP_DATA" | awk -F'|' '{print $1"\t"$2"\t"$3"\t"$4}' | \
                zenity --list --title="Nueva aplicacion" \
                --column="App" --column="Desktop" --column="Icono" --column="Comando" \
                --hide-column=2 --hide-column=3 --hide-column=4 \
                --print-column=ALL --separator="|" --width=550 --height=520 2>/dev/null)
            [ -z "$SEL2" ] && continue
            NUEVO_ICON=$(echo "$SEL2" | cut -d"|" -f3)
            NUEVO_EXEC=$(echo "$SEL2" | cut -d"|" -f4)
        elif [ "$CAMPO" = "tipo" ]; then
            NUEVO_MIME=$(zenity --list --title="Tipo de archivo" \
                --column="" --column="Tipo" --hide-column=1 --print-column=1 \
                --width=400 --height=280 --hide-header \
                "inode/directory;" "Carpetas" \
                "application/octet-stream;" "Cualquier archivo" \
                "inode/directory;application/octet-stream;" "Carpetas y archivos" 2>/dev/null)
            [ -z "$NUEVO_MIME" ] && continue
        fi
        ACTION_ID=$(basename "$ARCHIVO" .desktop)
        _escribir_accion "$ACTION_ID" "$NUEVO_NOMBRE" "$NUEVO_ICON" "$NUEVO_EXEC" "$NUEVO_MIME"
        _refrescar
        zenity --info --title="Actualizada" --text="<b>$NUEVO_NOMBRE</b> actualizada." --width=380 2>/dev/null

    elif [ "$OPCION" = "del" ]; then
        ACCIONES=$(_listar_acciones)
        [ -z "$ACCIONES" ] && zenity --info --title="Sin entradas" --text="No hay entradas que eliminar." --width=320 2>/dev/null && continue
        SEL=$(echo "$ACCIONES" | awk -F'|' '{print $1"\t"$2}' | \
            zenity --list --title="Eliminar entrada" \
            --column="Nombre" --column="Archivo" --hide-column=2 \
            --print-column=ALL --separator="|" --width=480 --height=420 2>/dev/null)
        [ -z "$SEL" ] && continue
        NOMBRE_DEL=$(echo "$SEL" | cut -d"|" -f1)
        ARCHIVO_DEL=$(echo "$SEL" | cut -d"|" -f2)
        zenity --question --title="Confirmar" --text="Eliminar <b>$NOMBRE_DEL</b>?" --width=340 2>/dev/null || continue
        rm -f "$ARCHIVO_DEL"
        _refrescar
        zenity --info --title="Eliminada" --text="<b>$NOMBRE_DEL</b> eliminada." --width=340 2>/dev/null
    fi
done
SCRIPTEOF
    chmod +x "$scripts_dir/Gestionar menu contextual"
    info "Gestor de menu contextual instalado en Nautilus"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    MODO="${1:-dark}"
    [ "$MODO" = "light" ] && { TEMA="WhiteSur-Light"; ICONOS="WhiteSur-light"; } \
                          || { TEMA="WhiteSur-Dark"; ICONOS="WhiteSur-dark"; }
    export MODO TEMA ICONOS

    paso="${2:-todo}"
    case "$paso" in
        atajos)    nautilus_scripts_atajos ;;
        abrir_con) nautilus_scripts_abrir_con ;;
        panel)     nautilus_scripts_panel ;;
        todo)
            nautilus_scripts_atajos
            nautilus_scripts_abrir_con
            nautilus_scripts_panel
            ;;
    esac
fi
