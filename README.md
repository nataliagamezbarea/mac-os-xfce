# macOS Ventura XFCE

## Que hace

Transforma XFCE en un escritorio con aspecto de macOS Ventura. Incluye:

- Tema WhiteSur (gtk, iconos, cursores)
- Dock estilo mac con Plank
- Panel inferior al estilo macOS
- Nautilus como gestor de archivos con modo oscuro
- Konsole con tema Ventura
- Zsh con Oh-My-Zsh y Oh-My-Posh
- Picom con blur y esquinas redondeadas
- Ulauncher (parecido a spotlight)
- LightDM con fondo de pantalla
- Fuentes Inter y MesloLGS

## Como se usa

```bash
git clone https://github.com/ibm-7094a/ventura-xfce
cd ventura-xfce
chmod +x *.sh
bash menu.sh
```

Pregunta modo light o dark, pide contraseña una vez y hace todo.

Para instalar solo una parte:

```bash
bash tema.sh dark dependencias
bash nautilus.sh dark configurar
bash terminal.sh dark zsh
```

## Archivos

| Archivo | Que hace |
|---|---|
| menu.sh | Ejecuta todo en orden |
| comun.sh | Funciones que usan los demas archivos |
| tema.sh | Instala dependencias, WhiteSur, iconos, fuentes y decoraciones |
| nautilus.sh | Configura Nautilus, modo oscuro y css de gtk4 |
| panel.sh | Copia config del panel XFCE y configura Plank |
| terminal.sh | Configura Konsole, instala zsh, oh-my-zsh y oh-my-posh |
| aplicaciones.sh | Instala AppMenu, Ulauncher, Picom y autostart |
| lightdm.sh | Configura LightDM y aplica fondo de pantalla |
| final.sh | Recarga todo y muestra resumen final |
