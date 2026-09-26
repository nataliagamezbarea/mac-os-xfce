# Script de Configuración del Panel XFCE

Este script configura automáticamente el panel XFCE, Plank y varias funciones del sistema.

## Opciones de Ejecución

### Ejecutar todo (completo)
```bash
bash panel.sh
```
Configura todo el sistema:
- Panel XFCE con tema macOS
- Plank dock con launchers
- Brave como navegador predeterminado
- Safari usando Brave con icono de Safari
- Gestor wifi al inicio
- Ocultar gestor de llaves de la bandeja

### Opciones individuales
```bash
# Configurar solo el panel XFCE
bash panel.sh config

# Configurar solo Plank
bash panel.sh plank

# Configurar solo el navegador (Safari/Brave)
bash panel.sh navegador

# Desactivar el gestor de llaves
bash panel.sh desactivar-keyring

# Crear copia de seguridad de Plank
bash panel.sh backup

# Reiniciar el panel
bash panel.sh reiniciar
```

## Configuraciones Adicionales

### Configurar comportamiento de la tapa (requiere sudo)
```bash
sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitch=.*/HandleLidSwitch=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
sudo sed -i 's/^HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=suspend/' /etc/systemd/logind.conf
```

> **Apariencia de la pantalla de inicio de sesión** ("¿Cambiar la apariencia de la
> pantalla de inicio de sesión (fondo macOS)?"): con "s" instala/ajusta
> `slick-greeter` y su fondo (`lightdm.sh`); con "n" no se toca el greeter y se
> queda el que haya. No hay inicio de sesión automático: siempre se pide la
> contraseña.

> En el menú se hacen **todas las preguntas primero** y la contraseña se pide
> una sola vez al final, justo antes de empezar los pasos.
> **Compositor**: no hay `picom`; el compositor es el de `xfwm4`
> (`use_compositing=true`), que es lo que había antes y no ralentiza nada.
> El dock (Plank) y el fondo entran por el autostart normal de XFCE
> (`Phase=Initialization`), sin hooks ni envoltorios.

## Arranque sin pantalla negra (lo hace `optimizar.sh boot` automáticamente)
```bash
# Arranque MUDO y en texto: ni una sola linea, sin Plymouth
sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="nowatchdog quiet systemd.show_status=false"/' /etc/default/grub
echo 'GRUB_TERMINAL="console"' >> /etc/default/grub
echo 'GRUB_GFXPAYLOAD_LINUX="text"' >> /etc/default/grub
sudo update-grub
```
> No añadas `splash` ni `plymouth`: son los que dejan la pantalla negra.
> Lo que no se ve sigue en el journal: `journalctl -b` y `systemctl --failed`.

## Características

- **Navegador predeterminado**: Brave configurado como navegador del sistema
- **Safari**: Usa Brave internamente pero mantiene icono de Safari
- **Gestor wifi**: Se inicia automáticamente al arranque
- **Gestor de llaves**: Se puede desactivar completamente
- **VirtualBox**: Funciona normalmente (sin agrupado forzado)
- **Plank**: Dock estilo macOS con tema transparente

## Arreglos incluidos

| Problema | Qué hace el script |
|---|---|
| Brave no se achica al desmaximizar | `reparar_ventanas_navegador()` (`comun.sh`): detecta la ventana a ancho completo sin maximizar o con restore corrupta y la deja a media pantalla. La llaman `final.sh recargar` y `menu.sh` |
| Pantalla negra al encender | `grub_pantalla_limpia()` (`optimizar.sh`): quita `quiet`/`splash`, GRUB en modo texto, menú oculto |
| Arranche con texto (`[ OK ]`, `[ FAILED ]`, kernel) | `quiet` + `systemd.show_status=false` + GRUB en texto: **cero texto**, sin Plymouth. Todo sigue en `journalctl -b` |
| `[ FAILED ] casper-md5check.service` | `casper.service` y `casper-md5check.service` se enmascaran (restos del instalador Live ISO que buscan un DVD) |
| VirtualBox: `VERR_VMX_IN_VMX_ROOT_MODE` | Grupo `vbox` + regla udev `99-vbox-acceso-usuario.rules` + lanzadores con `sg vbox` (el driver exige el grupo **primario**) |
| Pantalla negra al 2º desbloqueo | Bloqueo con `xfce4-screensaver` (light-locker desactivado) |
| Terminal con texto y "failed" | Los procesos se lanzan redirigidos (`>/dev/null 2>&1`): solo se ve el progreso `[✓]` |
| Fondo que no cubria la pantalla | `image-style 5` (Zoomed) en vez de 4 (Tiled) |
| Sesión que se guarda sola pese a desmarcarla | `SaveOnExit` y `AutoSave` en `false` y borrado de `~/.cache/sessions/`: arranque limpio |
| Texto en la pantalla de inicio ("Linux Mint", nombre) | `brand=no` y `show-hostname=false` en `~/.config/slick-greeter.conf` + greeter fijado en `99-macos-greeter.conf` |
| Una sola línea de texto al arrancar o al apagar | `quiet loglevel=0 systemd.show_status=false` en GRUB |
| El login esperaba a la red para aparecer | MySQL ya no depende de `network.target` y VirtualBox tiene unidad propia sin `network-online.target`: la red, el fondo, la barra y el dock cargan en paralelo |
| Ventanas que se descuadran al reiniciar el panel | El panel ya no reinicia `xfwm4`; el tema se aplica en caliente |
| Icono de Bluetooth que no aparecia en la bandeja | `blueman-applet` (el que muestra los estados) ya no se oculta, y se añade a `known-items`/`known-legacy-items`: sin estar ahí la bandeja no le reserva hueco y el icono no sale aunque el proceso esté corriendo |
| Lanzador en la barra que no hacía nada (Wi-Fi) | `panel_ocultar_elementos_defecto()` quita los lanzadores con `Exec` vacío o `Exec=null`, y los que se quedan sin carpeta (el hueco vacío de la barra) |
| El lanzador de Bluetooth volvía a salir en cada `panel.sh config` | Se limpian los dos XML del panel: el de la sesión y el de `~/ventura-xfce`, que es el que se copia. Antes solo se limpiaba el primero |
| El lanzador de Bluetooth salía vacío en la barra | Al reconocerlo se miran las dos carpetas (`launcher-<id>` y `launcher-<id>.off`). Si solo se mira la primera, la segunda ejecución ya no la encuentra y no lo quita nunca |
| El dock (Plank) aparecía 8 s tarde, después de la barra | El autostart de XFCE sale en un solo lote a los +11 s y a los +2/+3 s solo arrancan los clientes de la sesión `Failsafe`, **compilados en el binario** (añadirlos en xfconf no sirve: comprobado). `lightdm_dock_temprano()` usa `session-setup-script` de lightdm, que se ejecuta como el usuario justo antes de que arranque la sesión, y adelanta el dock allí |
| Los iconos de la bandeja desaparecen al reiniciar la barra | Al reiniciar el panel se destruye la ventana del systray y los iconos embebidos quedan **huérfanos**: el proceso sigue vivo pero ya no dibuja nada. `_panel_reiniciar_bandeja()` los relanza con el systray nuevo delante |
| El `slick-greeter.conf` "de usuario" no hacía nada | El greeter lo arranca lightdm como **root**, así que su `$HOME` es `/root`: el fichero en `/home/<usuario>/.config/` no lo leía nunca. Ahora se escribe también en `/root/.config/` |
| El login se ve al cambiar de usuario y al suspender, pero al encender no | El X del greeter es una instancia aparte, sin `xfce4-power-manager` que le quite el DPMS, y la pantalla no da EDID. `lightdm_pantallas_encendidas()` registra un `greeter-setup-script` que hace `xset -dpms` antes de arrancar el greeter, igual que ya hacía el hook de `resume` |
| El login salía **vacío** al encender el ordenador | `optimizar.sh` enmascaraba `accounts-daemon` para ahorrar milisegundos, pero lightdm lo necesita para la lista de usuarios: `Error getting user list from org.freedesktop.Accounts: ...UnitMasked`. Al cambiar de usuario o al suspender el greeter cae a la lista de PAM y por eso se veía bien. **Ya no se enmascara** |
| El icono de Bluetooth no salía en la barra | El que dibuja el icono es `blueman-tray`, no `blueman-applet`: este último es solo el demonio y es el que lo lanza. Se estaba escondiendo justo el que dibuja. Además `blueman-applet` se registra como StatusNotifierItem y el systray de XFCE solo repinta esos iconos al reiniciar la barra |

### Ver errores del arranque
```bash
grep -iE "fail|error" ~/.xsession-errors | tail -20   # apps del autostart
journalctl --user -b --no-pager                       # journal de la sesion
```

## Solución de Problemas

Si algo no funciona correctamente:
1. Ejecuta la opción específica para ese componente
2. Verifica que los archivos de configuración se crearon correctamente
3. Reinicia el panel XFCE: `xfce4-panel -r`
4. Reinicia Plank: `pkill plank && plank`

## Archivos Modificados

- `~/.config/xfce4/` - Configuración del panel XFCE
- `~/.config/plank/` - Configuración del dock Plank
- `~/.local/share/applications/` - Launchers modificados
- `~/.local/bin/` - Scripts wrappers si es necesario
