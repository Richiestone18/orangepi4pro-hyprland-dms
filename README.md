# orangepi4pro-hyprland-dms

Instalador para dejar una **Orange Pi 4 Pro** (Allwinner A733) con **Armbian CLI**
(Debian 13 "trixie", kernel vendor) con un escritorio estilo **Omarchy**:
**Hyprland + Quickshell + DankMaterialShell (DMS)** sobre la GPU **PowerVR BXM-4-64**,
con menú interactivo, instalación desatendida, reporte final y entrada directa al escritorio.

Es el hermano de [debian13-hyprland-dms](https://github.com/Richiestone18/debian13-hyprland-dms)
(para PC), adaptado a la placa: **sin nada que choque con Armbian ni con su GPU**
(ver [Qué se quitó y por qué](#qué-se-quitó-y-por-qué)).

**Versión 1.0** — probada con una instalación real en un contenedor que imita la imagen CLI
de Armbian para esta placa (ver [Cómo se probó](#cómo-se-probó)). Falta la prueba en la
placa misma.

## ¿Qué hace?

- **Menú interactivo** (`whiptail`, o `dialog`, que es lo que trae la imagen minimal de
  Armbian): marcas los componentes, eliges idioma y teclado, ves el resumen y puedes
  **volver atrás** antes de confirmar. Después todo es **desatendido** y termina con un
  **reporte** (`~/reporte-instalacion-<fecha>.txt`).
- **Escritorio**: Hyprland 0.55 (backports de Debian) con configuración **Lua**, Quickshell y
  DankMaterialShell desplegado con su configurador oficial (`dms setup headless`). La
  configuración se **valida con el propio Hyprland** (`--verify-config`), que además se
  arranca con `LD_BIND_NOW=1`: si a las librerías de la GPU les faltara algo, se ve ahí.
- **Terminal Alacritty** (usa OpenGL ES, que es lo que da esta GPU) con los colores de DMS,
  y **foot** de respaldo (dibuja con la CPU).
- **GPU PowerVR**: usa los drivers que pone Armbian (DDK 24.2 de Imagination: EGL, GLES,
  GBM, Vulkan y OpenCL, por delante de Mesa). Si a la imagen le faltan, los instala **igual
  que Armbian**: el mismo paquete de Orange Pi, el mismo commit y comprobado por `sha256`.
- **Red**: pasa netplan de `systemd-networkd` a **NetworkManager** (así DMS ve y cambia el
  WiFi), como lo hace `armbian-config` al instalar un escritorio, pero **conservando tu IP
  fija y tu WiFi**. Lo valida con `netplan generate` antes de tocar nada y el cambio vale
  **al reiniciar**: la conexión de ahora (SSH incluido) no se corta.
- **Inicio directo al escritorio** con `greetd` (o, con `--sin-autologin`, pide usuario y
  contraseña). Si Hyprland no arrancara, greetd cae a un acceso de texto y SSH sigue igual.
- **Protege la placa**:
  - apt nunca quita paquetes (`--no-remove`).
  - Ningún kernel de Debian se puede instalar (pin a −1).
  - Al final comprueba que el kernel, el firmware y el BSP de Armbian sigan instalados y que
    `/boot/Image` y `/boot/uInitrd` no cambiaron.
- **Repositorios**:
  - Armbian y Debian ya vienen en la imagen.
  - OBS de AvengeMedia (DMS, matugen, dgop) y Brave oficial (arm64).
  - Backports de Debian **solo para el escritorio**: el sistema (SSH, arranque, red) se
    queda en Debian estable.
- **Apariencia**: tema oscuro Arc-Dark, iconos Papirus-Dark, cursor Bibata, fuentes Inter y
  JetBrains Mono, fondos oficiales de Hyprland. `tema-desde-fondo /ruta/imagen` cambia el
  fondo y DMS recalcula los colores de todo.
- **Programas** (cada grupo se puede quitar en el menú):
  - Diseño y multimedia: GIMP, Inkscape, Krita, Darktable, Scribus, OpenShot, Audacity,
    wf-recorder…
  - Kodi, RetroArch y OpenRCT2 (en arm64 usan OpenGL ES).
  - Auditoría de redes: wifite, hashcat, wireshark…
  - Herramientas: Docker, gh, lazydocker, mise, tte y Flatpak con Flathub.
- **Re-ejecutable**: si algo falla, dice la sección y la línea; al volver a correrlo retoma
  lo que falte y respalda todo lo que cambia (`/var/backups/orangepi4pro-hyprland-dms/`).

## Requisitos

- Orange Pi 4 Pro con **Armbian CLI** (sin escritorio): Debian 13 "trixie", kernel
  **vendor** (6.6, familia `sun60iw2`), con tu usuario creado en el primer arranque.
- Internet, unos **12 GB libres** y de preferencia 8 GB de RAM o más.

Armbian publica para esta placa (noviembre de 2026) Ubuntu 26.04 server y Debian 13 con
XFCE, pero **no** Debian CLI. La imagen CLI se fabrica con el build framework de Armbian
(en una PC con Debian/Ubuntu y Docker):

```bash
git clone --depth=1 https://github.com/armbian/build
cd build
./compile.sh BOARD=orangepi4pro BRANCH=vendor RELEASE=trixie BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no
```

Sirve la minimal (`BUILD_MINIMAL=yes`) o la normal (`BUILD_MINIMAL=no`). Sobre la imagen
XFCE el script se niega (ya trae escritorio); con `--forzar` se instala encima.

## Uso

```bash
curl -fsSLO https://raw.githubusercontent.com/Richiestone18/orangepi4pro-hyprland-dms/main/orangepi4pro-hyprland-dms.sh
chmod +x orangepi4pro-hyprland-dms.sh
sudo ./orangepi4pro-hyprland-dms.sh          # menu
sudo ./orangepi4pro-hyprland-dms.sh --seco   # solo revisa requisitos, no cambia nada
sudo ./orangepi4pro-hyprland-dms.sh --si     # todo desatendido
```

Al terminar: `sudo reboot`. La red pasa a NetworkManager y entras al escritorio.

## Banderas

| Bandera | Qué hace |
|---|---|
| `--sin-extras` | sin diseño y multimedia |
| `--sin-kodi` | sin Kodi, RetroArch ni OpenRCT2 |
| `--sin-seguridad` | sin auditoría de redes |
| `--sin-herramientas` | sin Docker, gh, lazydocker, mise, tte ni Flatpak |
| `--sin-brave` | Firefox ESR en vez de Brave |
| `--sin-autologin` | al encender pide usuario y contraseña |
| `--idioma CODIGO` | idioma del sistema (defecto `es_MX.UTF-8`) |
| `--teclado DISTRIB` | teclado (defecto: el de la imagen) |
| `--usuario NOMBRE` | usuario a configurar (defecto: quien ejecuta `sudo`) |
| `--quickshell-obs` | quickshell del OBS (defecto: el de Debian, como pide DMS) |
| `--forzar` | seguir aunque no sea la Orange Pi 4 Pro o ya haya escritorio |
| `--seco` | solo revisa y muestra el plan |
| `--si` | desatendido total |

## Atajos principales

| Atajo | Acción |
|---|---|
| Super+Espacio | menú de apps |
| Super+Enter | terminal (Alacritty) |
| Super+B / Super+E | navegador / archivos |
| Super+V | portapapeles |
| Super+C | ajustes de DMS |
| Super+Y | fondos de pantalla |
| Super+X | apagar / reiniciar |
| Super+Alt+L | bloquear |
| Super+Q | cerrar ventana |
| Super+1..9 | escritorios |
| Impr | captura de pantalla |
| Super+Shift+/ | todos los atajos |

## Qué se quitó y por qué

Respecto a `debian13-hyprland-dms` (para PC):

| Se quitó | Por qué |
|---|---|
| Firmware de Debian (27 paquetes) | 5 chocan con `armbian-firmware` y apt **lo quitaría**: ahí viene el WiFi/BT AIC8800 de la placa |
| MX Linux y deb-multimedia | repos de PC; deb-multimedia reemplaza las librerías de video de Debian |
| Wine y Liquorix | solo existen para PC (amd64) |
| SDDM | arrastra Xorg y KWin; greetd basta |
| Ghostty y Kitty | piden OpenGL 3.3 de escritorio y esta GPU solo da OpenGL ES |
| Blender | pide OpenGL de escritorio |
| SimpleScreenRecorder | solo graba en X11 (en su lugar va `wf-recorder`) |
| Batería, Secure Boot, migración de `ifupdown` | no aplican en la placa |
| Backports para todo el sistema | aquí solo para el escritorio: SSH y el arranque siguen en Debian estable |

## La red

Armbian maneja la red con **netplan + systemd-networkd**, que DMS no ve. El script:

1. Mientras instala, le dice a NetworkManager que **no toque nada**
   (`/etc/NetworkManager/conf.d/99-opi4pro-transicion.conf`).
2. Cambia el `renderer` de tus archivos de netplan a `NetworkManager` y quita el "DHCP para
   todas" de fábrica (`10-dhcp-all-interfaces.yaml`), igual que `armbian-config`.
3. Lo prueba con `netplan generate` y comprueba que **cada IP fija** siga en lo generado; si
   no, no cambia nada y la red se queda con systemd-networkd.
4. Al reiniciar, `opi4pro-red-nm.service` quita la transición y NetworkManager toma la red.

Para regresar: los archivos originales están en `/var/backups/orangepi4pro-hyprland-dms/`.

## Si algo sale mal

- **Pantalla negra o Hyprland no arranca**: Ctrl+Alt+F2 (o entra por SSH) y ejecuta
  `diagnostico-gpu`. Muestra el módulo `pvrsrvkm`, los dispositivos de `/dev/dri`, qué
  librerías usa Hyprland, EGL/Vulkan y el final del registro de Hyprland.
- **Falló la instalación**: el mensaje dice la sección y la línea; el registro está en
  `/var/log/orangepi4pro-hyprland-dms.log`. Se puede volver a ejecutar.
- **Se cayó un servidor**: si el de Armbian no responde, el script sigue con su índice
  anterior (del escritorio no sale nada de ahí). Si falla Debian o el OBS de DMS, se
  detiene y lo dice.

## Cómo se probó

Validado en un **contenedor `systemd-nspawn` arm64 que reproduce la imagen CLI de Armbian**
para la placa (BSP `orangepi4pro-vendor`, `armbian-firmware`, `linux-image-vendor-sun60iw2`,
netplan con IP estática + WiFi con espacios, sin escritorio), mientras el host de repos de
Armbian (`beta.armbian.com`) estaba **caído con error 502**:

- **Instalación completa (corrida 6): `EXIT 0`** en ~50 min, 2,000+ paquetes. Verificación final:
  - `Hyprland 0.55.2+ds-1~bpo13+1`, `dms 2.1.2db1`, `quickshell 0.3.0-1~bpo13+1` (Debian).
  - **`hyprland.lua` → `config ok`** con `Hyprland --verify-config` y `LD_BIND_NOW=1`
    (enlaza completo con las librerías de PowerVR: `libgbm`/`libEGL` → `/usr/local/lib`).
  - GPU: drivers instalados desde el paquete de Orange Pi (comprobado por `sha256`), módulo
    `pvrsrvkm` presente, `ldd /usr/bin/Hyprland` sin faltantes.
  - Red: netplan pasa a NetworkManager al reiniciar (IP fija y WiFi conservados, validados
    con `netplan generate` antes de tocar nada).
  - **Paquetes de Armbian intactos (4/4) y `/boot` sin cambios** (`Image` y `uInitrd`
    siguen apuntando al kernel vendor).
  - greetd habilitado con autologin, Brave por defecto, `es_MX.UTF-8`, teclado latam.
  - Único aviso: 2 addons de Kodi (`kodi-audiodecoder-modplug`, `kodi-vfs-rar`) que en arm64
    no existen; el script los reporta y los salta.
- **Recuperación del repo caído probada en la misma corrida**: con `beta` en 502, el script
  cambió solo a un mirror vivo y **fresco** (rechaza `tnahosting`, que sirve un `InRelease`
  de enero-2025), y actualizó la llave de Armbian cuando el `keyring` de la imagen no alcanzaba.
- **Re-ejecución (corrida 7)**: sobre el sistema ya instalado, `EXIT 0` sin cambios nuevos.
- Menú probado con `dialog` (lo que trae la imagen minimal) en pty: 5 casos (aceptar,
  desmarcar, "No" para volver, cancelar con ESC).
- `bash -n` y `shellcheck` sin advertencias; pruebas unitarias de `adoptar_repo`,
  `arreglar_mirror_armbian` (3 pasadas = 0 respaldos) y del módulo de fuentes.

**No probado aquí** (hace falta la placa): arrancar la sesión gráfica en la GPU real y
verificar el enchufe físico; si la pantalla sale negra, `diagnostico-gpu` da el diagnóstico.

## Notas

- La GPU usa el DDK privativo de Imagination (OpenGL ES 3.2, Vulkan 1.3): las apps que piden
  OpenGL de escritorio no tienen aceleración.
- `quickshell` sale de Debian (backports), como recomienda la documentación de DMS.
- Los paquetes de backports se actualizan solos con `sudo apt upgrade`.

## Créditos

- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) y su OBS
  (AvengeMedia).
- [Hyprland](https://hypr.land) y los backports de Debian.
- [Armbian](https://www.armbian.com) y su soporte para la Orange Pi 4 Pro (`sun60iw2`).
- [Omarchy](https://omarchy.org), por la idea.
