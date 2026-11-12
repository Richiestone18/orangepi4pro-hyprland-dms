#!/bin/bash
# ============================================================================
#  orangepi4pro-hyprland-dms.sh  v1.0
#  Orange Pi 4 Pro (Allwinner A733) con Armbian CLI (Debian 13 trixie, kernel
#  vendor) -> escritorio estilo Omarchy: Hyprland (config Lua) + Quickshell +
#  DankMaterialShell (dms) sobre la GPU PowerVR, red con NetworkManager,
#  Brave por defecto, tema oscuro, idioma y teclado configurables.
#  Hermano de debian13-hyprland-dms v2.1, sin lo que choca con Armbian o con
#  la GPU de la placa.
#
#  Uso:    sudo ./orangepi4pro-hyprland-dms.sh [opciones]     (sin opciones: menu)
#  Ayuda:  ./orangepi4pro-hyprland-dms.sh --ayuda
#  Repo:   https://github.com/Richiestone18/orangepi4pro-hyprland-dms
# ============================================================================
set -Eeuo pipefail
umask 022

VER="1.0"
NOMBRE="orangepi4pro-hyprland-dms"
RUN_TS="$(date +%Y%m%d-%H%M%S)"
LOG="/var/log/${NOMBRE}-${RUN_TS}.log"
LOG_ACTIVO=""
TEE_PID=""
RESPALDO_SIS="/var/backups/${NOMBRE}/${RUN_TS}"

RED=$'\e[0;31m'; GREEN=$'\e[0;32m'; YELLOW=$'\e[1;33m'; CYAN=$'\e[0;36m'; BOLD=$'\e[1m'; NC=$'\e[0m'

# ---- valores por defecto: todo lo compatible se instala ---------------------
IDIOMA="es_MX.UTF-8"
TECLADO=""                 # vacio = el de la imagen (/etc/default/keyboard)
TECLADO_VAR=""
USUARIO_ARG=""
EXTRAS="si"; KODI="si"; SEGURIDAD="si"; HERRAMIENTAS="si"; BRAVE="si"; AUTOLOGIN="si"
QSH_PRIO="-1"              # quickshell: el de Debian (doc de DMS); 995 = el del OBS (--quickshell-obs)
SECO="no"; SI="no"; FORZAR="no"
SECCION="0. Comprobaciones previas"
AVISOS=(); NOTAS=(); RESPALDOS=()
REINTENTAR=()   # paquetes que fallaron: se vuelven a intentar en la ultima pasada
NAVEGADOR=""; FONDO=""; HYPR_ESTADO="sin revisar"; DMS_ESTADO="sin revisar"
RED_ESTADO="sin revisar"; GPU_ESTADO="sin revisar"
PLACA=""; PLACA_NOMBRE=""; FAMILIA=""; RAMA=""; ARMBIAN_VER=""; LIBRE_GB="?"

# Drivers de la GPU (DDK 24.2 de Imagination): el MISMO paquete y commit que usa Armbian
# para esta placa (armbian/build: config/sources/families/sun60iw2.conf)
GPU_DEB_URL="https://raw.githubusercontent.com/orangepi-xunlong/rk-rootfs-build/7b6d78d4f5eaefd5456777fbea5057a0876e8f4d/bullseye/xserver/xserver-xorg-img-bxm_1.21.1-2_arm64.deb"
GPU_DEB_SHA256="c8e606db1abdea40a5b97f7905ea86901b50c5fe1b76a55356ab70dde3304c3a"
NP_DIR="/etc/netplan"
NM_TRANS="/etc/NetworkManager/conf.d/99-opi4pro-transicion.conf"

export DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
# --no-remove: el script NUNCA quita paquetes (asi no se puede llevar armbian-firmware, el kernel ni
# el BSP de la placa). dpkg no pregunta por configuraciones y apt espera si otro apt tiene el candado.
APT_OPTS=(-y -q --no-remove -o Acquire::Retries=5 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o DPkg::Lock::Timeout=600)

log()    { echo "${GREEN}[OK]${NC} $*"; }
nota()   { echo "${CYAN}[NOTA]${NC} $*"; NOTAS+=("$*"); }
warn()   { echo "${YELLOW}[AVISO]${NC} $*"; AVISOS+=("$*"); }
err()    { echo "${RED}[ERROR]${NC} $*" >&2; }
header() {
  SECCION="$*"
  echo; echo "${CYAN}============================================================${NC}"
  echo "${CYAN}  $*${NC}"; echo "${CYAN}============================================================${NC}"
}
falla() {
  err "$*"
  if [[ -n "$LOG_ACTIVO" ]]; then echo "        Registro completo: $LOG" >&2; fi
  exit 1
}
al_fallar() {
  local rc=$? linea="$1" cmd="$2"
  trap - ERR
  echo
  err "Fallo en la seccion \"$SECCION\" (linea $linea, codigo $rc): $cmd"
  if [[ -n "$LOG_ACTIVO" ]]; then echo "        Registro completo: $LOG" >&2; fi
  echo "        Es seguro volver a ejecutar el script: retoma lo que falte." >&2
  exit "$rc"
}
trap 'al_fallar "$LINENO" "$BASH_COMMAND"' ERR

# /var/tmp (disco): /tmp es memoria (tmpfs)
TMPD="$(mktemp -d /var/tmp/opi4hdms.XXXXXX)"
chmod 755 "$TMPD"   # apt lee los .deb locales como el usuario _apt
export GNUPGHOME="$TMPD/gnupg"; mkdir -m 700 "$GNUPGHOME"
al_salir() {
  rm -rf "$TMPD"
  if [[ -n "$TEE_PID" ]]; then exec 1>&- 2>&-; wait "$TEE_PID" 2>/dev/null || true; fi
}
trap al_salir EXIT

texto_ayuda() {
cat <<'AYUDA'
orangepi4pro-hyprland-dms.sh v1.0 - Orange Pi 4 Pro + Armbian CLI -> Hyprland + DankMaterialShell

Uso:  sudo ./orangepi4pro-hyprland-dms.sh [opciones]

Para la imagen CLI (sin escritorio) de Armbian con Debian 13 "trixie" y kernel
vendor en la Orange Pi 4 Pro. Sin opciones aparece un MENU: marcas lo que quieres,
eliges idioma y teclado, ves el resumen y puedes volver atras. Al confirmar, todo
sigue DESATENDIDO hasta el final y termina con un reporte. Por tuberia
(curl ... | sudo bash) no hay menu: se instala todo lo de por defecto.

Por defecto lo instala todo. Estas banderas sirven para OMITIR:
  --sin-extras         sin diseno y multimedia (GIMP, Inkscape, Krita, Darktable...)
  --sin-kodi           sin Kodi, RetroArch ni OpenRCT2
  --sin-seguridad      sin auditoria de redes (wifite, hashcat, wireshark...)
  --sin-herramientas   sin Docker, gh, lazydocker, mise, tte ni Flatpak
  --sin-brave          sin Brave (el navegador sera Firefox ESR)
  --sin-autologin      al encender pide usuario y contrasena (no entra solo)

Otras opciones:
  --idioma CODIGO      idioma del sistema (defecto es_MX.UTF-8)
  --teclado DISTRIB    teclado (defecto: el de la imagen, ej. latam)
  --usuario NOMBRE     usuario a configurar (defecto: quien ejecuta sudo)
  --quickshell-obs     quickshell del OBS de DankLinux (defecto: el de Debian, como pide DMS)
  --forzar             seguir aunque no sea la Orange Pi 4 Pro o ya haya un escritorio
  --seco               solo revisa requisitos y muestra el plan; no cambia nada
  --si                 desatendido total: sin menu ni preguntas
  --ayuda              esta ayuda

No instala (choca con Armbian o no sirve con la GPU PowerVR): firmware de Debian,
MX Linux, deb-multimedia, Wine, Liquorix, SDDM, Blender, Ghostty y Kitty.
Registro: /var/log/orangepi4pro-hyprland-dms.log    Reporte: ~/reporte-instalacion-*.txt
AYUDA
}

# ---- banderas ----------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --idioma)            IDIOMA="${2:?falta el codigo de idioma (ej. es_MX.UTF-8)}"; shift 2 ;;
    --teclado)           TECLADO="${2:?falta la distribucion de teclado (ej. latam, es, us)}"; shift 2 ;;
    --usuario)           USUARIO_ARG="${2:?falta el nombre de usuario}"; shift 2 ;;
    --sin-extras)        EXTRAS="no"; shift ;;
    --sin-kodi)          KODI="no"; shift ;;
    --sin-seguridad)     SEGURIDAD="no"; shift ;;
    --sin-herramientas)  HERRAMIENTAS="no"; shift ;;
    --sin-brave)         BRAVE="no"; shift ;;
    --sin-autologin)     AUTOLOGIN="no"; shift ;;
    --quickshell-obs)    QSH_PRIO="995"; shift ;;
    --quickshell-debian) QSH_PRIO="-1"; shift ;;
    --forzar)            FORZAR="si"; shift ;;
    --seco)              SECO="si"; shift ;;
    --si|--yes|-y)       SI="si"; shift ;;
    --ayuda|-h|--help)   texto_ayuda; exit 0 ;;
    *) echo "Opcion desconocida: $1  (usa --ayuda)" >&2; exit 2 ;;
  esac
done

# ============================================================================
# === FUNCIONES ===
# ============================================================================
onoff() { if [[ "$1" == si ]]; then echo ON; else echo OFF; fi; }

normalizar_idioma() {
  local l="${1// /}"
  if [[ "$l" != *.* ]]; then l="${l}.UTF-8"; fi
  case "$l" in *.utf8|*.utf-8|*.UTF8|*.Utf-8) l="${l%.*}.UTF-8" ;; esac
  printf '%s' "$l"
}
idioma_valido() {   # existe en la lista de glibc (si la lista esta instalada); sin modificadores @
  [[ "$1" =~ ^[A-Za-z]{2,3}(_[A-Z]{2})?\.UTF-8$ ]] || return 1
  if [[ -r /usr/share/i18n/SUPPORTED ]]; then grep -qx -- "$1 UTF-8" /usr/share/i18n/SUPPORTED; fi
}
teclado_por_idioma() {
  case "$1" in
    es_ES*) echo es ;; es_*) echo latam ;; en_GB*) echo gb ;; en_*) echo us ;;
    pt_BR*) echo br ;; pt_*) echo pt ;; fr_CA*) echo ca ;; fr_*) echo fr ;;
    de_*) echo de ;; it_*) echo it ;; ru_*) echo ru ;; ja_*) echo jp ;; ko_*) echo kr ;;
    *) echo us ;;
  esac
}
teclado_valido() {  # cada distribucion (separadas por coma) existe en xkb
  local lst=/usr/share/X11/xkb/rules/evdev.lst l
  [[ "$1" =~ ^[a-z0-9_,()-]+$ ]] || return 1
  [[ -r "$lst" ]] || return 0
  for l in ${1//,/ }; do
    awk -v l="$l" '/^! layout/{f=1;next} /^!/{f=0} f && $1==l {ok=1} END{exit !ok}' "$lst" || return 1
  done
}
armbian_valor() {   # armbian_valor CLAVE: su valor en /etc/armbian-release
  [[ -r /etc/armbian-release ]] || return 0
  sed -n -E "s/^$1=\"?([^\"]*)\"?[[:space:]]*\$/\1/p" /etc/armbian-release | head -1
}
descargar() {   # descargar <url> <destino>
  curl -fsSL --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 900 -o "$2" "$1"
}
instalar_llave() {   # instalar_llave <url> <destino>: acepta llave armada o binaria
  local tmp="$TMPD/llave.$RANDOM"
  descargar "$1" "$tmp" || return 1
  if grep -q -- '-----BEGIN PGP' "$tmp"; then gpg --batch --yes --dearmor -o "$2" "$tmp" || return 1
  else install -m 0644 "$tmp" "$2" || return 1; fi
  chmod 0644 "$2"
}
respaldar() {   # copia un archivo antes de cambiarlo (una vez por corrida)
  local f="$1" dst
  [[ -e "$f" || -L "$f" ]] || return 0
  if [[ "$f" == "$HOME_USR"/* ]]; then dst="$f.bak-$RUN_TS"; else dst="$RESPALDO_SIS$f"; fi
  [[ -e "$dst" || -L "$dst" ]] && return 0
  mkdir -p "$(dirname "$dst")"
  cp -a -- "$f" "$dst"
  RESPALDOS+=("$dst")
}
escribir_sistema() {   # escribir_sistema <archivo>  (contenido por stdin; respalda solo si cambia)
  mkdir -p "$(dirname "$1")"
  cat > "$TMPD/nuevo"
  if [[ -f "$1" && ! -L "$1" ]] && cmp -s "$TMPD/nuevo" "$1"; then return 0; fi
  respaldar "$1"
  rm -f "$1"
  cat "$TMPD/nuevo" > "$1"
}
como_usuario() {   # ejecuta como el usuario real, con su HOME y su PATH
  local rt="/run/user/$UID_USR" extra=()
  if [[ -d "$rt" ]]; then extra+=(XDG_RUNTIME_DIR="$rt"); fi
  if [[ -S "$rt/bus" ]]; then extra+=(DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus"); fi
  runuser -u "$USUARIO" -- env HOME="$HOME_USR" USER="$USUARIO" LOGNAME="$USUARIO" \
    PATH="$HOME_USR/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" "${extra[@]}" "$@"
}
escribir_usuario() {   # escribir_usuario <archivo> [modo]  (contenido por stdin, dueno: el usuario)
  local f="$1" modo="${2:-644}"
  como_usuario mkdir -p -- "$(dirname -- "$f")"
  cat > "$TMPD/nuevo"
  if [[ -f "$f" && ! -L "$f" ]] && cmp -s "$TMPD/nuevo" "$f"; then return 0; fi
  respaldar "$f"
  rm -f -- "$f"
  cat "$TMPD/nuevo" > "$f"
  chown "$USUARIO:$USUARIO" "$f"
  chmod "$modo" "$f"
}
retirar() {   # respalda y quita un archivo
  respaldar "$1"
  rm -f -- "$1"
}

# ---- apt ----------------------------------------------------------------------
instalar() { apt-get "${APT_OPTS[@]}" install "$@"; }
reparar_dpkg() {   # deja dpkg/apt consistentes despues de un fallo
  local rotos
  dpkg --configure -a >/dev/null 2>&1 || true
  rotos="$(dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null | awk '$1 !~ /^(ii|rc|un|pn)/ {print $2}' || true)"
  if [[ -n "$rotos" ]]; then
    warn "Paquetes que quedaron a medias y se quitan: $(echo "$rotos" | tr '\n' ' ')"
    # shellcheck disable=SC2086
    dpkg --purge --force-remove-reinstreq $rotos >/dev/null 2>&1 || true
  fi
  apt-get "${APT_OPTS[@]}" -f install >/dev/null 2>&1 || true
}
apti() {   # imprescindible: si falla dos veces, el script se detiene con un mensaje claro
  if instalar "$@"; then return 0; fi
  reparar_dpkg
  sleep 20   # a veces un servidor solo falla un momento
  instalar "$@" || falla "No se pudo instalar algo imprescindible: $*  (si arriba dice \"Failed to fetch\", fallo el servidor de descarga: vuelve a ejecutar el script mas tarde, retoma donde se quedo)"
}
filtrar_existentes() {   # imprime los paquetes que tienen version candidata
  local out
  out="$(apt-cache policy "$@" 2>/dev/null || true)"
  awk '/^[^ ].*:$/ {p=substr($0, 1, length($0)-1)} /^  Candidate:/ { if ($2 != "(none)") print p }' <<< "$out"
}
apti_try() {   # instala lo que exista; lo que falte o falle se avisa, se salta y se guarda para el reintento final
  local opts=() p
  while [[ "${1:-}" == -* ]]; do opts+=("$1"); shift; done
  local -a existen=() faltan=()
  local -A hay=()
  mapfile -t existen < <(filtrar_existentes "$@")
  for p in "${existen[@]}"; do hay["$p"]=1; done
  for p in "$@"; do if [[ -z "${hay[$p]:-}" ]]; then faltan+=("$p"); fi; done
  if (( ${#faltan[@]} )); then warn "No estan en los repos (se saltan): ${faltan[*]}"; fi
  if (( ${#existen[@]} == 0 )); then return 0; fi
  if instalar "${opts[@]}" "${existen[@]}"; then return 0; fi
  warn "Fallo la instalacion en grupo; reintento paquete por paquete"
  reparar_dpkg
  for p in "${existen[@]}"; do
    if ! instalar "${opts[@]}" "$p"; then
      warn "No se pudo instalar: $p (se salta)"
      REINTENTAR+=("$p")   # se vuelve a intentar al final, cuando todos los repos esten activos
      reparar_dpkg
    fi
  done
  return 0
}
instalado() { [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" == ii* ]]; }
version_de() {
  if instalado "$1"; then dpkg-query -W -f='${Version}' "$1"; else echo "(no instalado)"; fi
}
paquetes_armbian() {   # lo que trae la imagen de Armbian y no debe desaparecer
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'armbian-*' 'linux-image-*' 'linux-dtb-*' \
    'linux-u-boot-*' 'linux-headers-*' 2>/dev/null | awk '$1 ~ /^ii/ {print $2}' || true
}

# ---- fuentes de apt (formato clasico y deb822) ---
APT_DIR="${APT_DIR:-/etc/apt}"
TERCEROS_RE='(opensuse|brave)'
# mirrors oficiales de Armbian (listado en apt.armbian.com/mirrors): se prueban en orden y solo se
# acepta uno con InRelease fresco, porque el redirector sirve InRelease viejo (firado en 2025 con
# SHA1, que la política de sqv rechaza) y asi el escritorio/kernel no dependen de un mirror podrido.
MIRRORS_ARMBIAN=(https://mirrors.netix.net/armbian/apt/ https://armbian.systemonachip.net/apt/ https://mirrors.dotsrc.org/armbian-apt/ https://armbian.hosthatch.com/apt/ https://armbian.tnahosting.net/apt/)
mirror_reciente() {   # mirror_reciente <uri>: responde y su InRelease tiene menos de 15 dias
  local fecha dd
  curl -fsSL --max-time 15 "${1%/}/dists/trixie/InRelease" -o "$TMPD/mir.ir" 2>/dev/null || return 1
  fecha="$(grep -m1 '^Date:' "$TMPD/mir.ir" | sed 's/^Date:[[:space:]]*//')"
  [[ -n "$fecha" ]] || return 1
  dd=$(( ( $(date -u +%s) - $(date -u -d "$fecha" +%s 2>/dev/null || echo 0) ) / 86400 ))
  (( dd >= 0 && dd <= 15 ))
}
repo_armbian_responde() {   # 0 si el host de Armbian (imagen o mirror) responde Y esta fresco
  local h
  h="$(fuentes_apt | awk '$1 ~ /armbian/ {print $1; exit}')"
  [[ -n "$h" ]] || return 1
  mirror_reciente "$h"
}
arreglar_llave_armbian() {   # el keyring de la imagen puede ser anterior a la llave que firma hoy
  local actual mir
  actual="$(fuentes_apt | awk '$1 ~ /armbian/ {print $1; exit}')"
  [[ -n "$actual" ]] || return 0
  command -v sqv >/dev/null 2>&1 || return 0
  # si apt verificaria el InRelease actual, no hace falta tocar nada
  if curl -fsSL --max-time 20 "${actual%/}/dists/trixie/InRelease" -o "$TMPD/ir.asc" 2>/dev/null \
     && sqv --keyring=/usr/share/keyrings/armbian-archive-keyring.gpg --cleartext \
            --output="$TMPD/ir.out" "$TMPD/ir.asc" >/dev/null 2>&1; then
    return 0
  fi
  for mir in "$actual" "${MIRRORS_ARMBIAN[@]}"; do
    if curl -fsSL --max-time 25 "${mir%/}/armbian.key" -o "$TMPD/armbian.key" 2>/dev/null && [[ -s "$TMPD/armbian.key" ]]; then
      respaldar /usr/share/keyrings/armbian-archive-keyring.gpg
      gpg --batch --no-default-keyring --keyring /usr/share/keyrings/armbian-archive-keyring.gpg \
        --import "$TMPD/armbian.key" >/dev/null 2>&1 || true
      if [[ -f "$TMPD/ir.asc" ]] && sqv --keyring=/usr/share/keyrings/armbian-archive-keyring.gpg \
           --cleartext --output="$TMPD/ir.out2" "$TMPD/ir.asc" >/dev/null 2>&1; then
        nota "Llave de Armbian actualizada desde ${mir%/}/armbian.key (el keyring de la imagen era anterior)"
        return 0
      fi
    fi
  done
  return 0
}
arreglar_mirror_armbian() {   # cambia el host de Armbian por un mirror que responda y este fresco
  local actual mir f
  actual="$(fuentes_apt | awk '$1 ~ /armbian/ {print $1; exit}')"
  [[ -n "$actual" ]] || return 0   # no hay repo de Armbian en las fuentes
  repo_armbian_responde && return 0   # el actual responde y esta fresco: nada que cambiar
  arreglar_llave_armbian
  for mir in "${MIRRORS_ARMBIAN[@]}"; do
    [[ "${mir%/}" == "${actual%/}" ]] && continue   # no probar el mismo
    if mirror_reciente "$mir"; then
      while read -r f; do
        if grep -qF "$actual" "$f"; then
          respaldar "$f"
          sed -i "s|$actual|${mir%/}|g" "$f"   # fijo: una URL no trae caracteres especiales
        fi
      done < <(archivos_fuentes)
      nota "El repo de Armbian ($actual) no responde o esta podrido: fuentes cambiadas al mirror ${mir}"
      return 0
    fi
  done
  warn "El repo de Armbian ($actual) no responde y ningun mirror fresco contesto: sus paquetes (kernel, firmware, fastfetch, gh, bluez...) se descargaran cuando vuelva"
  return 1
}
archivos_fuentes() {   # todas las listas de fuentes que existan
  local f
  for f in "$APT_DIR/sources.list" "$APT_DIR"/sources.list.d/*.list "$APT_DIR"/sources.list.d/*.sources; do
    if [[ -f "$f" ]]; then printf '%s\n' "$f"; fi
  done
}
fuentes_apt() {   # "uri suite firma componentes..." de cada fuente deb ACTIVA (clasico y deb822)
  local f
  while read -r f; do
    case "$f" in
      *.sources)
        awk 'BEGIN { RS = "" } {
          n = split($0, L, "\n"); t = ""; u = ""; s = ""; c = ""; k = "-"; e = "yes"
          for (i = 1; i <= n; i++) {
            if (L[i] ~ /^#/) continue
            v = L[i]; sub(/^[^:]*:[ \t]*/, "", v)
            if (L[i] ~ /^Types:/) t = v
            else if (L[i] ~ /^URIs:/) u = v
            else if (L[i] ~ /^Suites:/) s = v
            else if (L[i] ~ /^Components:/) c = v
            else if (L[i] ~ /^Signed-By:/) k = (v == "" ? "bloque" : v)
            else if (L[i] ~ /^Enabled:/) e = tolower(v)
          }
          if (t !~ /(^|[ \t])deb([ \t]|$)/ || e == "no") next
          nu = split(u, U, /[ \t]+/); ns = split(s, S, /[ \t]+/)
          for (a = 1; a <= nu; a++) for (b = 1; b <= ns; b++) print U[a], S[b], k, c
        }' "$f" ;;
      *)
        awk '/^[ \t]*deb[ \t]/ {
          l = $0; sub(/^[ \t]*deb[ \t]+/, "", l); k = "-"
          if (l ~ /^\[/) {
            o = substr(l, 2, index(l, "]") - 2); l = substr(l, index(l, "]") + 1); sub(/^[ \t]+/, "", l)
            if (match(o, /signed-by=[^ \t]+/)) k = substr(o, RSTART + 10, RLENGTH - 10)
          }
          split(l, P, /[ \t]+/); c = l; sub(/^[^ \t]+[ \t]+[^ \t]+[ \t]*/, "", c)
          print P[1], P[2], k, c
        }' "$f" ;;
    esac
  done < <(archivos_fuentes)
}
es_de_debian() {   # $1 uri  $2 firma: Debian oficial o espejo (sin llave propia de un tercero)
  [[ "$1" == *debian* && ! "$1" =~ $TERCEROS_RE && "$1" != cdrom:* ]] || return 1
  [[ "$2" == "-" || "$2" == *debian-archive-keyring* ]]
}
hay_fuente_debian() {   # $1 = regex de suite (ej. '^(trixie|stable)$')
  local uri suite firma
  while read -r uri suite firma _; do
    if [[ "$suite" =~ $1 ]] && es_de_debian "$uri" "$firma"; then return 0; fi
  done < <(fuentes_apt)
  return 1
}
adoptar_repo() {   # adoptar_repo <regex de la URI> <archivo propio>: una sola definicion por repo
  # si otra lista ya define el mismo repo con otra llave (la guia oficial de DMS o de Brave),
  # apt se niega a leer TODAS las fuentes: "Conflicting values set for option Signed-By"
  local re="$1" propio="$2" f
  while read -r f; do
    [[ "$f" == "$propio" ]] && continue
    case "$f" in
      *.sources)
        if grep -qE "^URIs:.*${re}" "$f"; then retirar "$f"; nota "Fuente duplicada retirada: $f"; fi ;;
      *)
        if grep -qE "^[[:space:]]*deb(-src)?[[:space:]].*${re}" "$f"; then
          respaldar "$f"
          sed -i -E "\\#^[[:space:]]*deb(-src)?[[:space:]].*${re}#s/^/# (duplicada, la maneja $NOMBRE) /" "$f"
          nota "Fuente duplicada desactivada en $f"
        fi ;;
    esac
  done < <(archivos_fuentes)
}
espacio_critico() {   # imprime los puntos de montaje con menos de 100 MB libres
  df -P -k / /var /tmp 2>/dev/null | awk 'NR > 1 && $4 < 102400 && !v[$6]++ {printf "%s (%d MB libres) ", $6, $4 / 1024}'
}
apt_update() {   # apt update que distingue lo imprescindible (Debian, OBS) de lo que puede esperar
  local salida="$TMPD/apt-update.txt" intento lleno malos=""
  for intento in 1 2 3; do
    if apt-get -o Acquire::Retries=5 update > "$salida" 2>&1; then
      cat "$salida"
      # apt solo avisa (W:) si un repo no responde y usa su indice anterior: que quede en el reporte
      malos="$(grep -E '^Err:' "$salida" | grep -oE 'https?://[^/ ]+' | sort -u | tr '\n' ' ' || true)"
      if [[ -n "$malos" ]]; then nota "Estos repos no respondieron y se uso su indice anterior: ${malos% }"; fi
      return 0
    fi
    cat "$salida" 2>/dev/null || true
    lleno="$(espacio_critico)"
    if [[ -n "$lleno" ]] || grep -qs 'No space left on device' "$salida"; then
      falla "Sin espacio libre: ${lleno:-revisa df -h}. Libera espacio y vuelve a ejecutar el script."
    fi
    malos="$(grep -E '^(Err|E):' "$salida" | grep -oE 'https?://[^/ ]+' | sort -u | tr '\n' ' ' || true)"
    # Brave es opcional: si su repo falla se desactiva (queda Firefox ESR)
    if [[ "$malos" == *brave* && -e /etc/apt/sources.list.d/brave-browser-release.sources ]]; then
      mkdir -p "$RESPALDO_SIS"
      mv -f /etc/apt/sources.list.d/brave-browser-release.sources "$RESPALDO_SIS/brave-browser-release.sources.desactivado"
      BRAVE="no"; warn "El repo de Brave no responde: lo desactivo (se guardo en $RESPALDO_SIS) y el navegador sera Firefox ESR"
      continue
    fi
    # si SOLO falla Armbian se sigue con su indice anterior: del escritorio no sale nada de ahi
    if [[ -n "$malos" ]] && ! tr ' ' '\n' <<< "$malos" | grep -v '^$' | grep -qv armbian; then
      warn "El repo de Armbian no responde (${malos% }): sigo con su indice anterior. El kernel y el firmware se actualizan despues con  sudo apt update && sudo apt upgrade"
      return 0
    fi
    warn "apt update fallo (intento $intento): ${malos:-sin detalle}"
    sleep 10
  done
  # ultimo intento: si el fallo es de Armbian, llave vieja u otro mirror fresco
  if [[ "$malos" == *armbian* ]]; then
    if arreglar_mirror_armbian; then
      apt-get -o Acquire::Retries=5 update && return 0
    fi
  fi
  if [[ "$malos" == *opensuse* ]]; then
    falla "No llego al OBS de AvengeMedia (download.opensuse.org), de donde sale DankMaterialShell: vuelve a ejecutar el script mas tarde."
  fi
  falla "apt update sigue fallando (${malos:-revisa la red, la fecha y hora y el proxy}): detalle en el registro."
}

# ---- GPU PowerVR ----------------------------------------------------------------
gpu_powervr_presente() {   # librerias del DDK de Imagination + firmware de la GPU
  [[ -e /usr/local/lib/libgbm.so.1 && -e /usr/local/lib/libEGL.so.1 && -e /usr/local/lib/dri/pvr_dri.so \
     && -e /usr/lib/libVK_IMG.so.1 ]] && compgen -G '/usr/lib/firmware/rgx.fw.*' >/dev/null
}
instalar_gpu_powervr() {   # lo mismo que hace Armbian al fabricar la imagen (sin escritorio X11)
  local deb="$TMPD/gpu.deb" x="$TMPD/gpu"
  descargar "$GPU_DEB_URL" "$deb" || { warn "No pude bajar el paquete de la GPU"; return 1; }
  if [[ "$(sha256sum "$deb" | cut -d' ' -f1)" != "$GPU_DEB_SHA256" ]]; then
    warn "El paquete de la GPU no coincide con su sha256: no lo instalo"; return 1
  fi
  rm -rf "$x"; mkdir -p "$x"
  dpkg-deb -x "$deb" "$x"
  # el paquete trae lib/ (firmware) aparte de usr/lib/: con /lib -> usr/lib se juntan
  if [[ -d "${x:?}/lib" ]]; then cp -a "${x:?}/lib/." "${x:?}/usr/lib/"; rm -rf "${x:?}/lib"; fi
  # solo librerias, firmware y pkg-config: sin el Xorg parchado (X11), su lightdm ni /etc/environment
  rm -rf "${x:?}/etc" "${x:?}/usr/bin" "${x:?}/usr/lib/xorg" "${x:?}/usr/lib/systemd" "${x:?}"/usr/lib/libxcvt*
  cp -a --no-preserve=ownership "$x/." /
  install -d -m 0755 /usr/share/vulkan/icd.d /etc/OpenCL/vendors
  escribir_sistema /usr/share/vulkan/icd.d/img_icd.json <<'EOF'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "/usr/lib/libVK_IMG.so.1",
        "api_version": "1.3.277"
    }
}
EOF
  escribir_sistema /etc/OpenCL/vendors/pvr.icd <<< "/usr/lib/libPVROCL.so.1"
  ldconfig
  gpu_powervr_presente
}

# ---- red: netplan -----------------------------------------------------------------
copia_netplan() {   # copia_netplan <raiz>: /etc/netplan -> <raiz>/etc/netplan
  rm -rf "$1"; mkdir -p "$1/etc"
  cp -a "$NP_DIR" "$1/etc/netplan"
}
netplan_salida() {   # netplan_salida <raiz>: deja en <raiz>/run lo que generaria netplan
  rm -rf "$1/run"
  netplan generate --root-dir "$1" > "$1/generate.txt" 2>&1
}
estado_netplan() {   # imprime: sin-netplan | error | networkd | networkmanager
  if [[ ! -d "$NP_DIR" ]] || ! command -v netplan >/dev/null 2>&1; then echo sin-netplan; return 0; fi
  local r="$TMPD/np-hoy"
  copia_netplan "$r"
  if ! netplan_salida "$r"; then echo error; return 0; fi
  if compgen -G "$r/run/systemd/network/*.network" >/dev/null; then echo networkd; else echo networkmanager; fi
}

resumen_texto() {
  echo "Resumen de la instalacion (v$VER):"
  echo "  Placa .......... ${PLACA_NOMBRE:-${PLACA:-?}}  (Armbian ${ARMBIAN_VER:-?}, kernel ${RAMA:-?})"
  echo "  Usuario ........ $USUARIO"
  echo "  Escritorio ..... Hyprland (config Lua) + Quickshell + DankMaterialShell, terminal Alacritty"
  if [[ $AUTOLOGIN == si ]]; then echo "  Inicio ......... greetd, entrando directo al escritorio"
  else echo "  Inicio ......... greetd, pide usuario y contrasena"; fi
  echo "  Idioma ......... $IDIOMA    Teclado: ${TECLADO}${TECLADO_VAR:+ ($TECLADO_VAR)}"
  if [[ $BRAVE == si ]]; then echo "  Navegador ...... Brave (repo oficial, por defecto)"
  else echo "  Navegador ...... Firefox ESR"; fi
  echo "  Programas ...... extras=$EXTRAS  kodi=$KODI  seguridad=$SEGURIDAD  herramientas=$HERRAMIENTAS"
  echo "  GPU ............ PowerVR BXM-4-64 con los drivers que usa Armbian (OpenGL ES 3.2)"
  echo "  Red ............ netplan -> NetworkManager al reiniciar (se conserva la IP fija)"
  echo "  Politica apt ... sistema en Debian estable + Armbian; escritorio desde backports"
  echo "  Seguridad apt .. nunca quita paquetes ni instala kernels de Debian"
  echo "  Disco libre .... ${LIBRE_GB} GB en /  (se recomiendan 12 GB o mas)"
}

# ---- menu interactivo (whiptail; en la imagen minimal de Armbian, dialog) ------
MENU_BIN=""; MENU_OPTS=()
aplicar_seleccion() {   # $1 = un elemento marcado por linea (--separate-output)
  local sel="$1"
  marcado() { if grep -qx -- "$1" <<< "$sel"; then echo si; else echo no; fi; }
  EXTRAS="$(marcado extras)"; KODI="$(marcado kodi)"; SEGURIDAD="$(marcado seguridad)"
  HERRAMIENTAS="$(marcado herramientas)"; BRAVE="$(marcado brave)"; AUTOLOGIN="$(marcado autologin)"
}
menu_interactivo() {
  local sel idioma tecl items
  if command -v whiptail >/dev/null 2>&1; then MENU_BIN=whiptail
  elif command -v dialog >/dev/null 2>&1; then MENU_BIN=dialog; MENU_OPTS=(--clear)
  else menu_texto; return; fi
  while true; do
    items=(extras       "Diseno y multimedia (GIMP, Inkscape, Krita, Darktable, Audacity...)" "$(onoff "$EXTRAS")"
           kodi         "Kodi + RetroArch + OpenRCT2" "$(onoff "$KODI")"
           seguridad    "Auditoria de redes (wifite, hashcat, wireshark...)" "$(onoff "$SEGURIDAD")"
           herramientas "Docker, gh, lazydocker, mise, tte y Flatpak" "$(onoff "$HERRAMIENTAS")"
           brave        "Brave (repo oficial) como navegador por defecto" "$(onoff "$BRAVE")"
           autologin    "Entrar directo al escritorio al encender" "$(onoff "$AUTOLOGIN")")
    sel=$("$MENU_BIN" "${MENU_OPTS[@]}" --title "Orange Pi 4 Pro estilo Omarchy v$VER - componentes" \
      --separate-output --checklist "ESPACIO marca o desmarca, TAB cambia a los botones, ENTER acepta" \
      20 86 $(( ${#items[@]} / 3 )) "${items[@]}" 3>&1 1>&2 2>&3) || return 1
    aplicar_seleccion "$sel"
    while true; do
      idioma=$("$MENU_BIN" "${MENU_OPTS[@]}" --title "Idioma del sistema" --inputbox \
        "Codigo de idioma (ej: es_MX.UTF-8, es_ES.UTF-8, en_US.UTF-8, pt_BR.UTF-8)" 10 72 "$IDIOMA" 3>&1 1>&2 2>&3) || return 1
      idioma="$(normalizar_idioma "$idioma")"
      if idioma_valido "$idioma"; then IDIOMA="$idioma"; break; fi
      "$MENU_BIN" "${MENU_OPTS[@]}" --title "Idioma no valido" --msgbox "\"$idioma\" no existe. Usa un codigo como es_MX.UTF-8" 8 66
    done
    while true; do
      tecl=$("$MENU_BIN" "${MENU_OPTS[@]}" --title "Teclado" --inputbox \
        "Distribucion de teclado (latam, es, us, br...). Detectada: ${TECLADO}" 10 72 "$TECLADO" 3>&1 1>&2 2>&3) || return 1
      if [[ -z "$tecl" ]]; then break; fi
      if teclado_valido "$tecl"; then
        if [[ "$tecl" != "$TECLADO" ]]; then TECLADO_VAR=""; fi
        TECLADO="$tecl"; break
      fi
      "$MENU_BIN" "${MENU_OPTS[@]}" --title "Teclado no valido" --msgbox "\"$tecl\" no existe. Prueba con latam, es o us" 8 66
    done
    if "$MENU_BIN" "${MENU_OPTS[@]}" --title "Confirmar" --yesno \
      "$(resumen_texto)\n\nEmpezar la instalacion DESATENDIDA con esta seleccion?\n(No = volver al menu para cambiar algo)" 24 90; then
      return 0
    fi
  done
}
menu_texto() {   # respaldo sin whiptail ni dialog
  resp() {
    local r
    read -rp "$1 [$(if [[ $2 == si ]]; then echo S/n; else echo s/N; fi)] " r || r=""
    r="${r:-$2}"; r="${r,,}"
    if [[ "$r" =~ ^(s|si|sí|y|yes)$ ]]; then echo si; else echo no; fi
  }
  echo "${BOLD}Seleccion de componentes (Enter = valor entre corchetes)${NC}"
  EXTRAS="$(resp 'Diseno y multimedia?' "$EXTRAS")"
  KODI="$(resp 'Kodi + RetroArch?' "$KODI")"
  SEGURIDAD="$(resp 'Auditoria de redes?' "$SEGURIDAD")"
  HERRAMIENTAS="$(resp 'Docker, gh, mise, Flatpak?' "$HERRAMIENTAS")"
  BRAVE="$(resp 'Brave por defecto?' "$BRAVE")"
  AUTOLOGIN="$(resp 'Entrar directo al escritorio al encender?' "$AUTOLOGIN")"
  local r
  read -rp "Idioma [$IDIOMA]: " r || r=""
  if [[ -n "$r" ]]; then
    r="$(normalizar_idioma "$r")"
    if idioma_valido "$r"; then IDIOMA="$r"; else echo "Idioma no valido; sigo con $IDIOMA"; fi
  fi
  read -rp "Teclado [$TECLADO]: " r || r=""
  if [[ -n "$r" ]]; then
    if teclado_valido "$r"; then TECLADO="$r"; TECLADO_VAR=""; else echo "Teclado no valido; sigo con $TECLADO"; fi
  fi
  echo; resumen_texto
  read -rp "Empezar la instalacion desatendida? [s/N] " r || r=""
  [[ "${r,,}" =~ ^(s|si|sí|y|yes)$ ]]
}

iniciar_log() {
  mkdir -p /var/log
  : > "$LOG"; chmod 640 "$LOG"
  ln -sfn "$LOG" "/var/log/${NOMBRE}.log"
  exec > >(tee >(sed -u 's/\x1b\[[0-9;]*m//g' >> "$LOG")) 2>&1
  TEE_PID=$!
  LOG_ACTIVO=si
}
# === FIN FUNCIONES ===

# ============================================================================
header "0. Comprobaciones previas  (v$VER)"
# ============================================================================
[[ $EUID -eq 0 ]] || falla "Ejecuta como root:  sudo $0"
USUARIO="${USUARIO_ARG:-${SUDO_USER:-}}"
if [[ -z "$USUARIO" || "$USUARIO" == root ]]; then USUARIO="$(logname 2>/dev/null || true)"; fi
if [[ -z "$USUARIO" || "$USUARIO" == root ]]; then
  # como root directo (su -): si hay un solo usuario normal, es el
  mapfile -t CANDIDATOS < <(awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd)
  if (( ${#CANDIDATOS[@]} == 1 )); then USUARIO="${CANDIDATOS[0]}"; fi
fi
if [[ -z "$USUARIO" || "$USUARIO" == root ]]; then
  falla "No pude detectar tu usuario normal. Usa:  sudo $0   o   $0 --usuario TU_USUARIO"
fi
getent passwd "$USUARIO" >/dev/null || falla "El usuario $USUARIO no existe"
HOME_USR="$(getent passwd "$USUARIO" | cut -d: -f6)"
UID_USR="$(id -u "$USUARIO")"
[[ -n "$HOME_USR" && -d "$HOME_USR" ]] || falla "No existe la carpeta personal de $USUARIO"
CFG="$HOME_USR/.config"
log "Usuario: $USUARIO  (home: $HOME_USR)"

# shellcheck source=/dev/null
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == trixie ]] || falla "Este script es para Armbian con Debian 13 (trixie). Detectado: ${PRETTY_NAME:-desconocido}"
ARQ="$(dpkg --print-architecture)"
[[ $ARQ == arm64 ]] || falla "Este script es para la Orange Pi 4 Pro (arm64); este equipo es $ARQ. Para PC usa debian13-hyprland-dms."
[[ -r /etc/armbian-release ]] || falla "No encuentro /etc/armbian-release: este script es para la imagen de Armbian (para Debian puro usa debian13-hyprland-dms)"
PLACA="$(armbian_valor BOARD)"; PLACA_NOMBRE="$(armbian_valor BOARD_NAME)"; FAMILIA="$(armbian_valor LINUXFAMILY)"
ARMBIAN_VER="$(armbian_valor VERSION)"
# rama del kernel: la del paquete instalado (linux-image-vendor-sun60iw2 -> vendor); si no, armbian-release
RAMA="$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' "linux-image-*-${FAMILIA:-x}" 2>/dev/null \
  | awk '$1 ~ /^ii/ {print $2}' | sed -E "s/^linux-image-(.*)-${FAMILIA:-x}\$/\1/" | head -1 || true)"
[[ -n "$RAMA" ]] || RAMA="$(armbian_valor BRANCH)"
[[ -n "$RAMA" ]] || RAMA="$(armbian_valor KERNEL_TARGET)"
if [[ "$PLACA" == orangepi4pro ]]; then
  log "Armbian ${ARMBIAN_VER:-?} en ${PLACA_NOMBRE:-Orange Pi 4 Pro} (familia ${FAMILIA:-?}, kernel ${RAMA:-?})"
elif [[ $FORZAR == si ]]; then
  warn "Placa ${PLACA:-desconocida} (${FAMILIA:-?}): este script es para la Orange Pi 4 Pro; sigo por --forzar"
else
  falla "Placa detectada: ${PLACA:-desconocida} (${FAMILIA:-?}). Este script es solo para la Orange Pi 4 Pro (con --forzar se intenta en otra placa A733)"
fi
if [[ "$RAMA" != vendor ]]; then warn "Kernel de Armbian \"${RAMA:-?}\": la GPU PowerVR solo tiene drivers con el kernel vendor"; fi

ESCRITORIO_PREVIO=""
for DM in lightdm gdm3 sddm lxdm slim nodm xdm; do
  if instalado "$DM"; then ESCRITORIO_PREVIO+="$DM "; fi
done
if [[ -n "$ESCRITORIO_PREVIO" ]]; then
  if [[ $FORZAR == si ]]; then
    warn "Ya hay un escritorio instalado (${ESCRITORIO_PREVIO% }): se desactiva su pantalla de acceso; sigo por --forzar"
  else
    falla "Esta imagen ya trae escritorio (${ESCRITORIO_PREVIO% }). El script es para la imagen CLI pura de Armbian (con --forzar se instala encima)"
  fi
fi
KERNEL_EN_USO="$(uname -r)"
if [[ "$KERNEL_EN_USO" != *sun60iw2* ]]; then
  nota "El kernel en uso ($KERNEL_EN_USO) no es el de la placa (sun60iw2): contenedor o chroot. La GPU se comprueba al arrancar en la placa."
fi
mapfile -t ARMBIAN_ANTES < <(paquetes_armbian)
if (( ${#ARMBIAN_ANTES[@]} == 0 )); then warn "No encontre paquetes de Armbian instalados (kernel, firmware, BSP)"; fi
# como arranca hoy la placa (u-boot de Armbian lee /boot/Image y /boot/uInitrd): se comprueba al final
ARRANQUE_ANTES="$(readlink /boot/Image 2>/dev/null || echo -) $(readlink /boot/uInitrd 2>/dev/null || echo -)"
KERNELS_DEBIAN="$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'linux-image-*' 2>/dev/null \
  | awk '$1 ~ /^ii/ && $2 ~ /(-arm64(-16k)?(-unsigned)?|\+deb[0-9]+.*)$/ {printf "%s ", $2}' || true)"
if [[ -n "$KERNELS_DEBIAN" ]]; then
  warn "Hay kernels de Debian instalados (${KERNELS_DEBIAN% }): la placa arranca con el vendor de Armbian; revisa que /boot/uInitrd apunte al vendor"
fi

if command -v curl >/dev/null 2>&1; then
  curl -fsS -o /dev/null --max-time 25 https://deb.debian.org/debian/dists/trixie/Release \
    || falla "Sin conexion a internet: no llego a deb.debian.org por HTTPS"
else
  getent hosts deb.debian.org >/dev/null || falla "Sin conexion a internet: no resuelvo deb.debian.org"
fi
log "Internet OK"

LIBRE_GB="$(df -BG --output=avail / | tail -1 | tr -dc '0-9')"
if (( LIBRE_GB < 8 )); then falla "Solo hay ${LIBRE_GB} GB libres en /. La instalacion completa necesita unos 12 GB."; fi
if (( LIBRE_GB < 12 )); then warn "Hay ${LIBRE_GB} GB libres en /: puede quedar justo (se recomiendan 12 GB)"; fi
RAM_GB="$(awk '/^MemTotal:/ {printf "%d", ($2 + 524288) / 1048576}' /proc/meminfo)"
if (( RAM_GB < 4 )); then nota "La placa tiene ${RAM_GB} GB de RAM: si va lenta, quita Kodi y diseno (--sin-kodi --sin-extras)"; fi

if [[ -z "$TECLADO" && -r /etc/default/keyboard ]]; then
  # shellcheck source=/dev/null
  TECLADO="$(. /etc/default/keyboard; echo "${XKBLAYOUT:-}")"
  # shellcheck source=/dev/null
  TECLADO_VAR="$(. /etc/default/keyboard; echo "${XKBVARIANT:-}")"
fi
if [[ -z "$TECLADO" ]]; then TECLADO="$(teclado_por_idioma "$IDIOMA")"; fi
IDIOMA="$(normalizar_idioma "$IDIOMA")"
idioma_valido "$IDIOMA" || falla "Idioma no valido: $IDIOMA (ejemplos: es_MX.UTF-8, es_ES.UTF-8, en_US.UTF-8)"
teclado_valido "$TECLADO" || falla "Distribucion de teclado no valida: $TECLADO (ejemplos: latam, es, us)"
[[ "$TECLADO_VAR" =~ ^[a-z0-9_,-]*$ ]] || TECLADO_VAR=""

if [[ $SECO == si ]]; then
  echo; resumen_texto; echo
  log "Modo seco: los requisitos se cumplen. NO se modifico nada."
  echo "  Quita --seco para instalar."
  exit 0
fi

if [[ $SI == si ]]; then
  resumen_texto
  log "Modo desatendido (--si): sin preguntas."
elif [[ -t 0 && -t 1 ]]; then
  echo "${BOLD}Menu de instalacion${NC}  (--si = desatendido | --ayuda = banderas)"
  [[ -n "${TERM:-}" ]] || export TERM=xterm
  menu_interactivo || { echo "Cancelado. No se cambio nada."; exit 0; }
else
  resumen_texto
  warn "Sin terminal interactiva (curl | sudo bash): se instala todo lo de por defecto (equivale a --si)"
fi

iniciar_log
echo "$NOMBRE.sh v$VER  -  $(date '+%F %T')  -  usuario $USUARIO  -  ${PLACA:-?} ($KERNEL_EN_USO)"
resumen_texto
if (( ${#AVISOS[@]} )); then printf '[AVISO] %s\n' "${AVISOS[@]}"; fi
log "Paquetes de Armbian protegidos (se comprueban al final): ${#ARMBIAN_ANTES[@]}"
log "Seleccion confirmada. Desde aqui TODO es desatendido. Registro: $LOG"

# ============================================================================
header "1. Repositorios: Armbian y Debian (de la imagen) + OBS de DankMaterialShell + Brave"
# ============================================================================
install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d
D=/etc/apt/sources.list.d
# si el host de Armbian de la imagen esta caido, irse a un mirror vivo ANTES de usar apt
arreglar_mirror_armbian
# una sola definicion por cada repo que maneja este script (antes de usar apt)
adoptar_repo 'AvengeMedia:/?danklinux' "$D/avengemedia-danklinux.sources"
adoptar_repo 'AvengeMedia:/?dms/' "$D/avengemedia-dms.sources"
if [[ $BRAVE == si ]]; then adoptar_repo 'brave-browser-apt-release' "$D/brave-browser-release.sources"; fi

FUENTES="$(fuentes_apt)"
if grep -qE 'armbian' <<< "$FUENTES"; then
  log "Repo de Armbian presente (de ahi salen el kernel, el firmware y el BSP de la placa)"
else
  warn "No veo el repo de Armbian en las fuentes de apt: de ahi salen las actualizaciones del kernel y del firmware de la placa"
fi
if ! hay_fuente_debian '^(trixie|stable)$'; then
  escribir_sistema /etc/apt/sources.list.d/debian.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  log "No habia fuentes de Debian: creadas en /etc/apt/sources.list.d/debian.sources"
fi
# aqui solo hacen falta Armbian y Debian: un repo de terceros roto se reescribe mas abajo
arreglar_llave_armbian   # el keyring de la imagen puede quedar viejo para el mirror
if ! apt-get update; then nota "apt update inicial con errores en algun repo de terceros: se rehacen a continuacion"; fi
apti curl ca-certificates gnupg

# Backports OFICIALES de Debian (de aqui salen Hyprland y sus piezas). La imagen de Armbian ya
# los trae; con prioridad 500 lo de Armbian sigue ganando: backports no tiene nada mas nuevo.
if hay_fuente_debian '^(trixie|stable)-backports$'; then
  log "Backports de Debian ya presentes"
else
  escribir_sistema /etc/apt/sources.list.d/debian-backports.sources <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  log "Backports de Debian agregados"
fi

# OBS de AvengeMedia (DankMaterialShell, matugen, dgop...): publica arm64
for REPO in danklinux dms; do
  BASE="https://download.opensuse.org/repositories/home:/AvengeMedia:/${REPO}/Debian_13/"
  instalar_llave "${BASE}Release.key" "/etc/apt/keyrings/avengemedia-${REPO}.gpg" \
    || falla "No pude bajar la llave del OBS ($REPO). Sin ella no hay DankMaterialShell."
  escribir_sistema "/etc/apt/sources.list.d/avengemedia-${REPO}.sources" <<EOF
Types: deb
URIs: ${BASE}
Suites: /
Signed-By: /etc/apt/keyrings/avengemedia-${REPO}.gpg
EOF
done
log "Repos del OBS de AvengeMedia listos (danklinux + dms)"

if [[ $BRAVE == si ]]; then
  if instalar_llave https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
       /usr/share/keyrings/brave-browser-archive-keyring.gpg; then
    if [[ -e /etc/apt/sources.list.d/brave-browser-release.list ]]; then retirar /etc/apt/sources.list.d/brave-browser-release.list; fi
    escribir_sistema /etc/apt/sources.list.d/brave-browser-release.sources <<'EOF'
Types: deb
URIs: https://brave-browser-apt-release.s3.brave.com/
Suites: stable
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/brave-browser-archive-keyring.gpg
EOF
    log "Repo oficial de Brave listo (arm64)"
  else
    BRAVE="no"; warn "No pude bajar la llave de Brave: se instalara Firefox ESR"
  fi
fi

escribir_sistema "/etc/apt/preferences.d/99-${NOMBRE}.pref" <<EOF
# Generado por $NOMBRE.sh v$VER
# Politica para la placa: Debian estable + Armbian mandan en el SISTEMA (SSH, arranque,
# red). Backports se queda en 100 (como en Debian): de ahi sale solo el escritorio, que
# el script instala con -t trixie-backports, y eso se sigue actualizando desde backports.
# El OBS de AvengeMedia (DMS, matugen, dgop...) y Brave, a 500.

# quickshell: el de Debian, como pide la doc de DMS (con --quickshell-obs, el del OBS)
Package: quickshell
Pin: origin download.opensuse.org
Pin-Priority: $QSH_PRIO

Package: *
Pin: origin download.opensuse.org
Pin-Priority: 500

Package: *
Pin: origin brave-browser-apt-release.s3.brave.com
Pin-Priority: 500

# Lo de escritorio del repo de Armbian (trixie-desktop: Mesa git, libdrm, una copia de
# Brave...) por debajo de Debian: en esta placa la GPU usa las librerias de PowerVR (van por
# delante de Mesa) y asi el escritorio no depende del servidor beta de Armbian. El kernel,
# el firmware y el BSP (main y trixie-utils) siguen saliendo de Armbian como siempre.
Package: *
Pin: release o=Armbian, c=trixie-desktop
Pin-Priority: 100

# NUNCA un kernel de Debian: la placa arranca con el kernel vendor de Armbian, y Armbian
# apunta /boot/uInitrd al ultimo initramfs generado (un kernel de Debian la dejaria sin
# arrancar). Llegaria solo, p. ej. por la recomendacion wireguard-modules de wireguard-tools.
Package: linux-image-* linux-headers-* linux-kbuild-* linux-support-*
Pin: release o=Debian
Pin-Priority: -1

Package: linux-image-* linux-headers-* linux-kbuild-* linux-support-*
Pin: release n=trixie-backports
Pin-Priority: -1
EOF
log "Pinning escrito en /etc/apt/preferences.d/99-${NOMBRE}.pref"

debconf-set-selections <<'EOF'
wireshark-common wireshark-common/install-setuid boolean true
macchanger macchanger/automatically_run boolean false
EOF

apt_update
if ! apt-get "${APT_OPTS[@]}" dist-upgrade; then
  reparar_dpkg
  apt-get "${APT_OPTS[@]}" dist-upgrade || warn "La actualizacion inicial (dist-upgrade) no se completo (si pedia quitar paquetes, el script no lo hace); sigo"
fi
log "Sistema al dia con todos los repos"

# ============================================================================
header "2. GPU PowerVR BXM-4-64: drivers de la placa"
# ============================================================================
if gpu_powervr_presente; then
  log "Drivers de la GPU presentes (DDK 24.2 de Imagination, como los pone Armbian)"
else
  nota "La imagen no trae los drivers de la GPU: los instalo igual que Armbian (paquete de Orange Pi, comprobado por sha256)"
  if instalar_gpu_powervr; then log "Drivers de la GPU instalados (librerias en /usr/local/lib y /usr/lib, firmware rgx)"
  else warn "No pude instalar los drivers de la GPU: Hyprland no tendria aceleracion"; fi
fi
if gpu_powervr_presente && [[ ! -f /etc/ld.so.conf.d/00-pvr-priority.conf ]]; then
  # las librerias de la GPU van ANTES que las de Mesa
  escribir_sistema /etc/ld.so.conf.d/00-pvr-priority.conf <<'EOF'
/usr/local/lib
/usr/lib
EOF
fi
if [[ ! -f /etc/udev/rules.d/99-sun60iw2-permissions.rules ]]; then
  # los mismos permisos que pone Armbian: GPU, video y NPU para los grupos video y render
  escribir_sistema /etc/udev/rules.d/99-sun60iw2-permissions.rules <<'EOF'
KERNEL=="system", SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
KERNEL=="reserved", SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
KERNEL=="sunxi_soc_info", GROUP="video", MODE="0660"
KERNEL=="renderD128", SUBSYSTEM=="drm", GROUP="render", MODE="0660"
KERNEL=="cedar_dev", GROUP="video", MODE="0660"
KERNEL=="cedar_dev_ve2", GROUP="video", MODE="0660"
KERNEL=="g2d", GROUP="video", MODE="0660"
KERNEL=="vipcore", GROUP="video", MODE="0660"
EOF
fi
for G in video render input; do
  if getent group "$G" >/dev/null; then usermod -aG "$G" "$USUARIO"; fi
done
apti_try clinfo vulkan-tools mesa-utils
ldconfig
if compgen -G "/lib/modules/*/extra/pvrsrvkm.ko*" >/dev/null; then
  log "Modulo de la GPU (pvrsrvkm) presente en el kernel de Armbian"
else
  warn "No encontre el modulo pvrsrvkm en /lib/modules/*/extra: sin el, la GPU no funciona (usa el kernel vendor de Armbian)"
fi
if gpu_powervr_presente; then GPU_ESTADO="drivers presentes"; else GPU_ESTADO="SIN drivers"; fi

# ============================================================================
header "3. Base del sistema: utilidades, fuentes y temas"
# ============================================================================
nota "El firmware de la placa lo pone armbian-firmware (WiFi/BT AIC8800): el firmware de Debian choca con el y no se instala"
# antes de instalar NetworkManager: que no toque la red que hoy lleva systemd-networkd
if [[ -f "$NM_TRANS" ]]; then
  log "Transicion de la red pendiente de una corrida anterior (termina al reiniciar)"
elif ! instalado network-manager && [[ "$(estado_netplan)" == networkd ]]; then
  escribir_sistema "$NM_TRANS" <<'EOF'
# Generado por orangepi4pro-hyprland-dms.sh: NetworkManager no toca NINGUNA interfaz
# hasta el proximo arranque (hoy la red la maneja systemd-networkd por netplan).
# Al arrancar, opi4pro-red-nm.service borra este archivo antes de NetworkManager.
[keyfile]
unmanaged-devices=*
EOF
  log "NetworkManager no tocara la red actual hasta reiniciar (hoy la maneja systemd-networkd)"
fi
apti_try sudo git curl wget rsync htop btop net-tools gdebi unzip zip p7zip-full build-essential \
  pkg-config cmake python3 python3-pip pipx xdg-utils xdg-user-dirs jq yq man-db \
  bash-completion acl dconf-cli netplan.io
apti_try ripgrep fzf bat eza zoxide fd-find tree ncdu duf fastfetch gum alacritty foot neovim \
  vim tmux lazygit git-delta wl-clipboard cliphist grim slurp swappy brightnessctl playerctl \
  pavucontrol network-manager network-manager-gnome blueman
apti_try fonts-noto fonts-noto-color-emoji fonts-noto-cjk fonts-jetbrains-mono fonts-font-awesome \
  fonts-materialdesignicons-webfont fonts-firacode fonts-inter papirus-icon-theme arc-theme \
  bibata-cursor-theme adwaita-icon-theme gnome-themes-extra
log "Utilidades, fuentes, temas, iconos y cursor procesados"

# Material Symbols: la fuente de iconos de DankMaterialShell
install -d -m 0755 /usr/share/fonts/truetype/material-symbols
for V in Rounded Outlined; do
  if descargar "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbols${V}%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" \
       "/usr/share/fonts/truetype/material-symbols/MaterialSymbols${V}.ttf"; then
    log "Fuente Material Symbols $V instalada"
  else
    warn "No pude bajar Material Symbols $V (algunos iconos de DMS saldrian vacios)"
  fi
done
fc-cache -f >/dev/null 2>&1 || true

# ============================================================================
header "4. Audio: PipeWire + WirePlumber"
# ============================================================================
apti_try pipewire pipewire-alsa pipewire-audio pipewire-bin pipewire-pulse pipewire-jack \
  pipewire-v4l2 wireplumber libspa-0.2-bluetooth libspa-0.2-jack libspa-0.2-modules qpwgraph alsa-ucm-conf
if instalado pipewire-pulse; then log "PipeWire listo ($(version_de pipewire))"; else warn "PipeWire no quedo instalado"; fi

# ============================================================================
header "5. Idioma ($IDIOMA) y teclado ($TECLADO)"
# ============================================================================
apti_try locales
if ! idioma_valido "$IDIOMA"; then warn "El idioma $IDIOMA no existe; uso es_MX.UTF-8"; IDIOMA="es_MX.UTF-8"; fi
LANG_BASE="${IDIOMA%%.*}"; LANG_ISO="${LANG_BASE%%_*}"
IDIOMA_RE="${IDIOMA//./\\.}"
if grep -qE "^#[[:space:]]*${IDIOMA_RE} UTF-8" /etc/locale.gen; then
  sed -i -E "s/^#[[:space:]]*(${IDIOMA_RE} UTF-8)/\1/" /etc/locale.gen
elif ! grep -qE "^${IDIOMA_RE} UTF-8" /etc/locale.gen; then
  echo "$IDIOMA UTF-8" >> /etc/locale.gen
fi
locale-gen
update-locale "LANG=$IDIOMA" "LANGUAGE=${LANG_BASE}:${LANG_ISO}"
log "Idioma $IDIOMA generado y fijado (vale desde el proximo inicio de sesion)"

mapfile -t DICC < <(filtrar_existentes "hunspell-${LANG_ISO}" "hunspell-$(tr '[:upper:]_' '[:lower:]-' <<< "$LANG_BASE")")
if (( ${#DICC[@]} )); then apti_try "${DICC[@]}"; fi
case "$LANG_ISO" in
  ja) apti_try ibus ibus-mozc mozc-utils-gui ;;
  ko) apti_try ibus ibus-hangul ;;
  zh) apti_try ibus ibus-libpinyin ibus-chewing ;;
esac

# teclado de la consola y de greetd: el mismo que tendra Hyprland
if [[ -f /etc/default/keyboard ]]; then
  # shellcheck source=/dev/null
  TEC_ACTUAL="$(. /etc/default/keyboard; echo "${XKBLAYOUT:-}|${XKBVARIANT:-}")"
  if [[ "$TEC_ACTUAL" != "$TECLADO|$TECLADO_VAR" ]]; then
    respaldar /etc/default/keyboard
    sed -i -E -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$TECLADO\"/" -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$TECLADO_VAR\"/" /etc/default/keyboard
    log "Teclado del sistema cambiado a $TECLADO (consola y pantalla de acceso)"
  fi
fi
nota "DankMaterialShell trae sus propias traducciones (incluye espanol): se elige en Ajustes de DMS -> Idioma. Brave, GTK, Qt y las carpetas personales siguen el idioma del sistema."

# ============================================================================
header "6. Escritorio: Hyprland + Quickshell + DankMaterialShell"
# ============================================================================
apti --target-release=trixie-backports hyprland quickshell dms
# libxcb-dri2-0: libaquamarine (dependencia de Hyprland) usa libxcb-dri2.so.0 pero NO lo
# declara (bug de empaquetado de Debian); en escritorios normales llega de rebote y aqui no
apti_try libxcb-dri2-0
# sin ghostty ni kitty: piden OpenGL 3.3 de escritorio y la GPU PowerVR solo da OpenGL ES.
# La terminal es Alacritty (OpenGL ES) y foot queda de respaldo (dibuja con la CPU).
apti_try --target-release=trixie-backports hyprland-guiutils xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-desktop-portal \
  matugen hyprland-backgrounds hyprpicker xwayland dgop danksearch dankcalendar dux-files \
  cava upower power-profiles-daemon gnome-keyring libpam-gnome-keyring qt6-wayland qt6-svg-plugins \
  qt6-gtk-platformtheme qt5-gtk-platformtheme nautilus desktop-file-utils shared-mime-info
if [[ $BRAVE == si ]]; then apti_try brave-browser; fi
if ! instalado brave-browser; then
  BRAVE="no"
  apti_try firefox-esr
  mapfile -t FFL10N < <(filtrar_existentes "firefox-esr-l10n-$(tr '[:upper:]_' '[:lower:]-' <<< "$LANG_BASE")" "firefox-esr-l10n-${LANG_ISO}")
  if (( ${#FFL10N[@]} )); then apti_try "${FFL10N[0]}"; fi
fi
log "Hyprland $(version_de hyprland), DMS $(version_de dms), Quickshell $(version_de quickshell)"

# --- Inicio de sesion: greetd (ligero; SDDM no: arrastra Xorg y KWin) ---------
SESION_CMD="/usr/bin/start-hyprland"
[[ -x "$SESION_CMD" ]] || SESION_CMD="/usr/bin/Hyprland"
apti greetd
if ! getent passwd _greetd >/dev/null; then warn "No existe el usuario _greetd que crea el paquete greetd"; fi
config_greetd() {
  cat <<EOF
# Generado por $NOMBRE.sh v$VER
# Si cierras sesion aparece el acceso de texto de greetd (agreety); al entrar vuelve Hyprland.
# Si Hyprland no arranca, greetd tambien cae al acceso de texto (y SSH sigue entrando igual).
[terminal]
vt = 7

[default_session]
command = "/usr/sbin/agreety --cmd $SESION_CMD"
user = "_greetd"
EOF
  if [[ $AUTOLOGIN == si ]]; then
    printf '\n# al encender entra solo al escritorio\n[initial_session]\ncommand = "%s"\nuser = "%s"\n' "$SESION_CMD" "$USUARIO"
  fi
}
escribir_sistema /etc/greetd/config.toml < <(config_greetd)
for DM in gdm3 lightdm sddm lxdm xdm slim nodm; do
  systemctl disable "$DM" >/dev/null 2>&1 || true
done
systemctl enable greetd || warn "No pude habilitar greetd (revisalo con: systemctl status greetd)"
systemctl set-default graphical.target >/dev/null 2>&1 || true
if [[ $AUTOLOGIN == si ]]; then log "Inicio de sesion: greetd, entrando directo como $USUARIO"
else log "Inicio de sesion: greetd (pide usuario y contrasena)"; fi

# ============================================================================
header "7. Herramientas: Docker, gh, lazydocker, mise, tte y Flatpak"
# ============================================================================
if [[ $HERRAMIENTAS == si ]]; then
  apti_try docker.io docker-compose gh flatpak
  if getent group docker >/dev/null; then usermod -aG docker "$USUARIO"; fi
  # instaladores web como el usuario, en disco (no en /tmp, que es RAM) y en una carpeta suya
  TMPU="$TMPD/usuario"; install -d -o "$USUARIO" -g "$USUARIO" -m 0700 "$TMPU"
  instalador_web() {   # instalador_web <nombre> <binario que debe quedar> <comando>
    local nombre="$1" bin="$2" cmd="$3"
    if timeout 900 runuser -u "$USUARIO" -- env HOME="$HOME_USR" USER="$USUARIO" TMPDIR="$TMPU" \
         PATH="$HOME_USR/.local/bin:/usr/local/bin:/usr/bin:/bin" \
         bash -c "set -o pipefail; cd \"\$TMPDIR\" && $cmd" > "$TMPD/$nombre.txt" 2>&1 \
       && [[ -x "$HOME_USR/.local/bin/$bin" ]]; then
      log "$nombre instalado"
    else
      warn "$nombre no se pudo instalar (opcional): $(tail -2 "$TMPD/$nombre.txt" 2>/dev/null | tr '\n' ' ')"
    fi
  }
  instalador_web lazydocker lazydocker 'curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash'
  instalador_web mise mise 'curl -fsSL https://mise.run | sh'
  instalador_web tte tte 'pipx install --force terminaltexteffects'
  if command -v flatpak >/dev/null; then
    if TMPDIR="$TMPD" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo > "$TMPD/flathub.txt" 2>&1; then
      log "Flathub agregado"
    else
      warn "No pude agregar Flathub (opcional): $(tail -1 "$TMPD/flathub.txt" | tr '\n' ' ')"
    fi
  fi
else
  nota "Herramientas omitidas (--sin-herramientas)"
fi

# ============================================================================
header "8. Programas opcionales"
# ============================================================================
if [[ $EXTRAS == si ]]; then
  # sin Blender (pide OpenGL de escritorio) ni SimpleScreenRecorder (solo X11): wf-recorder graba en Wayland
  apti_try inkscape krita krita-l10n gimp gimp-data-extras scribus scribus-template darktable \
    openshot-qt audacity wf-recorder guvcview amule filezilla qbittorrent yt-dlp devede
  log "Diseno y multimedia procesados"
fi
if [[ $KODI == si ]]; then
  apti_try kodi kodi-audiodecoder-modplug kodi-audiodecoder-openmpt kodi-audioencoder-flac \
    kodi-audioencoder-lame kodi-audioencoder-vorbis kodi-inputstream-adaptive \
    kodi-inputstream-ffmpegdirect kodi-inputstream-rtmp kodi-peripheral-joystick \
    kodi-pvr-iptvsimple kodi-vfs-libarchive kodi-vfs-rar kodi-vfs-sftp retroarch openrct2
  log "Kodi, RetroArch y OpenRCT2 procesados (en arm64 usan OpenGL ES)"
fi
if [[ $SEGURIDAD == si ]]; then
  apti_try wifite bully hashcat hcxdumptool hcxtools wireshark macchanger aircrack-ng
  if getent group wireshark >/dev/null; then usermod -aG wireshark "$USUARIO"; fi
  log "Auditoria de redes procesada ($USUARIO puede capturar con Wireshark sin root)"
fi

# ============================================================================
header "9. Configuracion del usuario ($USUARIO)"
# ============================================================================
# 9.1 Carpetas de usuario sanas
for D in .config .local .local/bin .local/share .local/state .cache; do
  if [[ ! -d "$HOME_USR/$D" ]]; then install -d -o "$USUARIO" -g "$USUARIO" -m 0755 "$HOME_USR/$D"; fi
done
ARREGLADOS="$(find "$CFG" "$HOME_USR/.local" "$HOME_USR/Pictures" -xdev -user root -print -exec chown -h "$USUARIO:$USUARIO" {} + 2>/dev/null | wc -l || true)"
if (( ARREGLADOS > 0 )); then warn "Se devolvieron a $USUARIO $ARREGLADOS archivos/carpetas que eran de root"; fi
como_usuario env LANG="$IDIOMA" xdg-user-dirs-update >/dev/null 2>&1 || true
IMAGENES="$(como_usuario env LANG="$IDIOMA" xdg-user-dir PICTURES 2>/dev/null || true)"
if [[ -z "$IMAGENES" || "$IMAGENES" == "$HOME_USR" ]]; then IMAGENES="$HOME_USR/Pictures"; fi
FONDOS="$IMAGENES/Fondos"
ESTADO="$CFG/$NOMBRE"
como_usuario mkdir -p "$FONDOS" "$ESTADO" "$HOME_USR/.local/state/$NOMBRE"
log "Carpetas personales en $IDIOMA (imagenes: $IMAGENES)"

# 9.2 Fondos de pantalla de Hyprland (paquete hyprland-backgrounds)
while read -r W; do
  if [[ -f "$W" ]]; then install -o "$USUARIO" -g "$USUARIO" -m 0644 "$W" "$FONDOS/hyprland-$(basename "$W")"; fi
done < <(dpkg -L hyprland-backgrounds 2>/dev/null | grep -E '\.(png|jpe?g)$' || true)
for W in "$FONDOS"/*.png "$FONDOS"/*.jpg; do
  if [[ -f "$W" ]]; then FONDO="$W"; break; fi
done
if [[ -n "$FONDO" ]]; then
  escribir_usuario "$ESTADO/fondo" <<< "$FONDO"
  log "Fondos en $FONDOS (inicial: $(basename "$FONDO"))"
else
  warn "No encontre fondos de Hyprland: elige uno en DMS (Super+Y)"
fi

# 9.3 Navegador por defecto
if [[ $BRAVE == si ]] && instalado brave-browser; then NAVEGADOR=brave-browser; NAV_DESKTOP=brave-browser.desktop
elif instalado firefox-esr; then NAVEGADOR=firefox-esr; NAV_DESKTOP=firefox-esr.desktop
else NAVEGADOR=""; NAV_DESKTOP=""; warn "No quedo ningun navegador instalado"; fi
if [[ -n "$NAVEGADOR" ]]; then
  for ALT in x-www-browser gnome-www-browser; do
    update-alternatives --install "/usr/bin/$ALT" "$ALT" "/usr/bin/$NAVEGADOR" 250 >/dev/null
    update-alternatives --set "$ALT" "/usr/bin/$NAVEGADOR" >/dev/null
  done
  escribir_usuario "$CFG/mimeapps.list" <<EOF
[Default Applications]
text/html=$NAV_DESKTOP
application/xhtml+xml=$NAV_DESKTOP
x-scheme-handler/http=$NAV_DESKTOP
x-scheme-handler/https=$NAV_DESKTOP
x-scheme-handler/about=$NAV_DESKTOP
x-scheme-handler/unknown=$NAV_DESKTOP
EOF
  log "Navegador por defecto: $NAVEGADOR"
fi
ARCHIVOS="nautilus"
if ! instalado nautilus; then ARCHIVOS="dux-files"; fi

# 9.4 Hyprland + DankMaterialShell con la configuracion OFICIAL de DMS (terminal Alacritty)
HY="$CFG/hypr"
SETUP=(dms setup headless --compositor hyprland --terminal alacritty --skip-existing)
if como_usuario "${SETUP[@]}" > "$TMPD/dms-setup.txt" 2>&1; then
  DMS_ESTADO="configurado (dms setup)"
elif como_usuario "${SETUP[@]}" --no-systemd > "$TMPD/dms-setup.txt" 2>&1; then
  DMS_ESTADO="configurado (dms setup, sin systemd)"
else
  DMS_ESTADO="ERROR en dms setup"
  warn "dms setup fallo: $(tail -3 "$TMPD/dms-setup.txt" | tr '\n' ' ')"
fi
sed 's/^/    dms: /' "$TMPD/dms-setup.txt" | tail -25
if [[ ! -f "$HY/hyprland.lua" ]]; then
  falla "No quedo ~/.config/hypr/hyprland.lua (dms setup). Detalle arriba y en el registro."
fi
# teclado: es la base de hyprland.lua; los Ajustes de DMS (dms/input.lua) siguen mandando
if grep -qE '^[[:space:]]*kb_layout[[:space:]]*=' "$HY/hyprland.lua"; then
  sed -i -E "0,/^([[:space:]]*kb_layout[[:space:]]*=[[:space:]]*)\"[^\"]*\"/s//\1\"$TECLADO\"/" "$HY/hyprland.lua"
  if [[ -n "$TECLADO_VAR" ]] && ! grep -qE '^[[:space:]]*kb_variant[[:space:]]*=' "$HY/hyprland.lua"; then
    sed -i -E "0,/^([[:space:]]*)kb_layout([[:space:]]*=.*)$/s//&\n\1kb_variant = \"$TECLADO_VAR\",/" "$HY/hyprland.lua"
  fi
  log "Teclado de Hyprland: $TECLADO${TECLADO_VAR:+ ($TECLADO_VAR)}"
else
  warn "No encontre kb_layout en hyprland.lua: elige el teclado en Ajustes de DMS"
fi
# cursor Bibata como base (dms/cursor.lua se carga despues: lo que elijas en DMS manda)
if ! grep -q 'XCURSOR_THEME' "$HY/hyprland.lua" && grep -qE '^require\("dms\.colors"\)' "$HY/hyprland.lua"; then
  sed -i -E '0,/^require\("dms\.colors"\)/s//hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")\nhl.env("XCURSOR_SIZE", "24")\n&/' "$HY/hyprland.lua"
fi
# lo propio de esta instalacion va en un archivo aparte que se carga al final
escribir_usuario "$HY/opi4pro.lua" < <(sed -e "s|@@NAVEGADOR@@|${NAVEGADOR:-xdg-open}|" -e "s|@@ARCHIVOS@@|$ARCHIVOS|" <<'LUA'
-- ~/.config/hypr/opi4pro.lua  -  generado por orangepi4pro-hyprland-dms.sh v1.0
-- Extras estilo Omarchy sobre la configuracion oficial de DankMaterialShell.
-- Los atajos de DMS (Super+Espacio, Super+Enter, volumen, brillo...) estan en
-- dms/binds.lua; los tuyos van en dms/binds-user.lua o aqui.

local browser = "@@NAVEGADOR@@"
local files   = "@@ARCHIVOS@@"

hl.env("BROWSER", browser)
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_QPA_PLATFORMTHEME_QT6", "gtk3")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + E", hl.dsp.exec_cmd(files))
hl.bind("SUPER + C", hl.dsp.exec_cmd("dms ipc call settings focusOrToggle"))
-- (Impr, Ctrl+Impr y Alt+Impr para capturas ya vienen en dms/binds.lua)

-- primer inicio: fondo de pantalla (DMS saca de el los colores) y bienvenida
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/primer-inicio-dms")
end)
LUA
)
if ! grep -qE '^[[:space:]]*require\("opi4pro"\)' "$HY/hyprland.lua"; then
  printf '\n-- extras de orangepi4pro-hyprland-dms.sh\nrequire("opi4pro")\n' >> "$HY/hyprland.lua"
fi
chown "$USUARIO:$USUARIO" "$HY/hyprland.lua"

# 9.5 Validar con el propio Hyprland. LD_BIND_NOW=1 resuelve TODOS sus simbolos al arrancar:
#     si a las librerias de la GPU (libEGL/libgbm de PowerVR) les faltara algo, aqui se ve.
VRT="$TMPD/xdg-runtime"; install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "$VRT"
if runuser -u "$USUARIO" -- env HOME="$HOME_USR" XDG_RUNTIME_DIR="$VRT" PATH="/usr/bin:/bin" LD_BIND_NOW=1 \
     Hyprland --verify-config --config "$HY/hyprland.lua" > "$TMPD/verify.txt" 2>&1; then
  HYPR_ESTADO="valida (Hyprland --verify-config)"
  log "hyprland.lua validado por el propio Hyprland, que ademas enlaza completo con las librerias de la GPU"
elif grep -qE 'symbol lookup error|undefined symbol|cannot open shared object' "$TMPD/verify.txt"; then
  HYPR_ESTADO="NO ENLAZA con las librerias de la GPU"
  warn "Hyprland no enlaza con las librerias de la GPU: $(head -2 "$TMPD/verify.txt" | tr '\n' ' ')"
else
  HYPR_ESTADO="CON ERRORES (ver registro)"
  warn "Hyprland reporta errores en su configuracion: $(grep -iE 'error|fail' "$TMPD/verify.txt" | head -5 | tr '\n' ' ')"
  sed 's/^/    hyprland: /' "$TMPD/verify.txt" | tail -20
fi

# 9.6 Apariencia: GTK oscuro, iconos Papirus, cursor Bibata y fuente Inter
escribir_usuario "$CFG/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Inter 11
gtk-application-prefer-dark-theme=1
EOF
escribir_usuario "$CFG/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Inter 11
EOF
# valores por defecto del sistema en dconf (no necesita la sesion grafica abierta)
install -d -m 0755 /etc/dconf/profile /etc/dconf/db/local.d
if [[ ! -f /etc/dconf/profile/user ]]; then
  escribir_sistema /etc/dconf/profile/user <<'EOF'
user-db:user
system-db:local
EOF
elif ! grep -qs '^system-db:local' /etc/dconf/profile/user; then
  respaldar /etc/dconf/profile/user
  echo 'system-db:local' >> /etc/dconf/profile/user
fi
escribir_sistema "/etc/dconf/db/local.d/00-$NOMBRE" <<'EOF'
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
gtk-theme='Arc-Dark'
icon-theme='Papirus-Dark'
cursor-theme='Bibata-Modern-Classic'
cursor-size=24
font-name='Inter 11'
document-font-name='Inter 11'
monospace-font-name='JetBrains Mono 11'

[org/gnome/desktop/wm/preferences]
titlebar-font='Inter Bold 11'
EOF
if command -v dconf >/dev/null; then dconf update || warn "dconf update fallo"; fi
if [[ -d /usr/share/icons/Bibata-Modern-Classic ]]; then
  escribir_usuario "$HOME_USR/.icons/default/index.theme" <<'EOF'
[Icon Theme]
Inherits=Bibata-Modern-Classic
EOF
fi
escribir_usuario "$CFG/environment.d/10-$NOMBRE.conf" <<EOF
QT_QPA_PLATFORMTHEME=gtk3
QT_QPA_PLATFORMTHEME_QT6=gtk3
BROWSER=${NAVEGADOR:-xdg-open}
EOF
log "Apariencia: Arc-Dark + Papirus-Dark + cursor Bibata + fuente Inter (modo oscuro)"

# 9.7 foot, la terminal de respaldo (Alacritty ya la configuro DMS con sus colores)
if [[ ! -f "$CFG/foot/foot.ini" ]]; then
  escribir_usuario "$CFG/foot/foot.ini" <<'EOF'
# Terminal de respaldo: dibuja con la CPU (sirve aunque falle la GPU)
font=JetBrains Mono:size=11
pad=10x10
EOF
fi

# 9.8 Ayudantes: primer inicio, "tema desde un fondo", diagnostico de la GPU y llavero
escribir_usuario "$HOME_USR/.local/bin/primer-inicio-dms" 755 <<'EOF'
#!/bin/bash
# Se ejecuta al iniciar Hyprland; solo actua la primera vez: pone el fondo en DMS
# (que saca los colores de el) y da la bienvenida.
MARCA="$HOME/.local/state/orangepi4pro-hyprland-dms/primer-inicio"
[[ -e "$MARCA" ]] && exit 0
FONDO="$(cat "$HOME/.config/orangepi4pro-hyprland-dms/fondo" 2>/dev/null)"
for _ in $(seq 1 90); do
  if dms ipc call wallpaper get >/dev/null 2>&1; then
    if [[ -f "$FONDO" ]]; then dms ipc call wallpaper set "$FONDO" >/dev/null 2>&1; fi
    dms ipc call toast info "Bienvenido: Super+Espacio abre el menu, Super+Enter la terminal" >/dev/null 2>&1
    mkdir -p "$(dirname "$MARCA")" && date > "$MARCA"
    exit 0
  fi
  sleep 1
done
EOF
escribir_usuario "$HOME_USR/.local/bin/tema-desde-fondo" 755 <<'EOF'
#!/bin/bash
# Uso: tema-desde-fondo /ruta/imagen
# Pone la imagen de fondo en DankMaterialShell, que recalcula los colores de todo
# (barra, bordes, GTK, Qt y terminal). Tambien se puede con Super+Y.
set -e
IMG="$(readlink -f "${1:?uso: tema-desde-fondo /ruta/imagen}")"
[[ -f "$IMG" ]] || { echo "no existe: $IMG" >&2; exit 1; }
mkdir -p "$HOME/.config/orangepi4pro-hyprland-dms"
printf '%s\n' "$IMG" > "$HOME/.config/orangepi4pro-hyprland-dms/fondo"
dms ipc call wallpaper set "$IMG"
echo "Listo: fondo y colores actualizados."
EOF
escribir_usuario "$HOME_USR/.local/bin/diagnostico-gpu" 755 <<'EOF'
#!/bin/bash
# Diagnostico rapido de la GPU PowerVR de la Orange Pi 4 Pro (no necesita root).
# Si la pantalla se queda negra: Ctrl+Alt+F2 (o por SSH), entra y ejecuta  diagnostico-gpu
echo "Kernel ......... $(uname -r)"
if grep -q '^pvrsrvkm ' /proc/modules 2>/dev/null; then echo "Modulo GPU ..... pvrsrvkm cargado"
else echo "Modulo GPU ..... pvrsrvkm NO cargado  (prueba: sudo modprobe pvrsrvkm; dmesg | grep -i pvr)"; fi
echo "Dispositivos ... $(ls /dev/dri 2>/dev/null | tr '\n' ' ')"
echo "Tus grupos ..... $(id -nG)"
echo "Hyprland usa ... $(ldd /usr/bin/Hyprland 2>/dev/null | awk '$1 ~ /^lib(EGL|gbm|GLESv2)\.so/ {printf "%s ", $3}')"
if command -v eglinfo >/dev/null; then
  echo "EGL/GLES:"; eglinfo -B 2>/dev/null | grep -iE 'vendor|renderer|version' | sort -u | head -8 | sed 's/^/  /'
fi
if command -v vulkaninfo >/dev/null; then
  echo "Vulkan:"; vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName' | head -4 | sed 's/^/  /'
fi
L="$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/hyprland.log 2>/dev/null | head -1)"
if [[ -n "$L" ]]; then echo "Ultimas lineas de $L:"; tail -15 "$L" | sed 's/^/  /'; fi
EOF
# llavero sin contrasena (como Omarchy): con la entrada automatica no hay contrasena
# que lo desbloquee y Brave pediria una en cada inicio
KR="$HOME_USR/.local/share/keyrings"
if [[ ! -d "$KR" || -z "$(ls -A "$KR" 2>/dev/null)" ]]; then
  escribir_usuario "$KR/Default_keyring.keyring" 600 < <(printf '[keyring]\ndisplay-name=Default keyring\nctime=%s\nmtime=0\nlock-on-idle=false\nlock-after=false\n' "$(date +%s)")
  escribir_usuario "$KR/default" 644 <<< "Default_keyring"
  chmod 700 "$KR"
  log "Llavero por defecto sin contrasena (para la entrada automatica)"
fi
if [[ -x "$HOME_USR/.local/bin/mise" ]] && ! grep -qs 'mise activate bash' "$HOME_USR/.bashrc"; then
  # shellcheck disable=SC2016
  printf '\n# mise (gestor de versiones, como en Omarchy)\neval "$(~/.local/bin/mise activate bash)"\n' >> "$HOME_USR/.bashrc"
  chown "$USUARIO:$USUARIO" "$HOME_USR/.bashrc"
fi
log "Configuracion de $USUARIO lista (DMS, Hyprland, apariencia, terminales, navegador y ayudantes)"

# ============================================================================
header "10. Red: NetworkManager por netplan (igual que armbian-config)"
# ============================================================================
# Armbian maneja la red con netplan + systemd-networkd: DMS no la veria. Se hace lo mismo que
# armbian-config al instalar un escritorio (renderer NetworkManager), pero conservando la IP
# fija y el WiFi que ya tengas en netplan. Se valida con netplan ANTES de tocar nada y vale
# desde el proximo arranque: la conexion de ahora (SSH incluido) no se corta.
config_unidad_red() {
  cat <<EOF
[Unit]
Description=$NOMBRE: la red pasa a NetworkManager (una sola vez)
DefaultDependencies=no
After=local-fs.target
Before=NetworkManager.service network-pre.target
ConditionPathExists=$NM_TRANS

[Service]
Type=oneshot
ExecStart=/bin/rm -f $NM_TRANS

[Install]
WantedBy=NetworkManager.service
EOF
}
instalar_unidad_red() {
  escribir_sistema /etc/systemd/system/opi4pro-red-nm.service < <(config_unidad_red)
  systemctl enable opi4pro-red-nm.service >/dev/null 2>&1 || warn "No pude habilitar opi4pro-red-nm.service"
}
NP_ESTADO="$(estado_netplan)"
if [[ $NP_ESTADO == sin-netplan ]]; then
  if [[ -f /etc/network/interfaces ]] && grep -qE '^[[:space:]]*iface[[:space:]]+[^l[:space:]]' /etc/network/interfaces; then
    warn "La red esta en /etc/network/interfaces (ifupdown), no en netplan: no la toco (para manejarla desde DMS, pasala a NetworkManager con nmcli)"
  fi
  RED_ESTADO="sin netplan: sin cambios"
elif ! instalado network-manager; then
  warn "NetworkManager no quedo instalado: la red sigue con systemd-networkd"
  RED_ESTADO="systemd-networkd (sin NetworkManager)"
elif [[ $NP_ESTADO == error ]]; then
  warn "netplan tiene errores y no genera su configuracion: no toco la red ($(tail -2 "$TMPD/np-hoy/generate.txt" 2>/dev/null | tr '\n' ' '))"
  RED_ESTADO="netplan con errores: sin cambios"
  if [[ -f "$NM_TRANS" ]]; then instalar_unidad_red; fi
elif [[ $NP_ESTADO == networkmanager ]]; then
  if [[ -f "$NM_TRANS" ]]; then
    RED_ESTADO="pasa a NetworkManager al reiniciar"
    instalar_unidad_red
    log "La red ya esta lista para NetworkManager (cambia al reiniciar)"
  else
    RED_ESTADO="NetworkManager"
    log "La red ya la administra NetworkManager"
  fi
else
  # preparar el cambio en una copia y validarlo con netplan
  P="$TMPD/np-nuevo"; copia_netplan "$P"
  QUITAR=()
  for F in "$P/etc/netplan"/*.yaml; do
    [[ -f "$F" ]] || continue
    B="$(basename "$F")"
    if [[ "$B" == 10-dhcp-all-interfaces.yaml ]] && ! grep -qE '^[[:space:]]*(addresses|access-points|routes|nameservers):' "$F"; then
      # el "DHCP para todas" de fabrica: armbian-config tambien lo quita (NetworkManager ya hace DHCP solo)
      rm -f "$F"; QUITAR+=("$B")
    else
      sed -i -E 's/^([[:space:]]*renderer:[[:space:]]*)networkd[[:space:]]*$/\1NetworkManager/' "$F"
    fi
  done
  install -m 600 /dev/stdin "$P/etc/netplan/00-default-use-network-manager.yaml" <<'EOF'
# Generado por orangepi4pro-hyprland-dms.sh (igual que armbian-config al instalar un
# escritorio): NetworkManager maneja todas las interfaces.
network:
  version: 2
  renderer: NetworkManager
EOF
  FALTA=""
  if netplan_salida "$P" && ! compgen -G "$P/run/systemd/network/*.network" >/dev/null; then
    # cada IP fija (o ruta) de hoy tiene que aparecer en lo que se generaria para NetworkManager
    while read -r IPF; do
      [[ -n "$IPF" ]] || continue
      grep -rqsE "^(address|route)[0-9]+=${IPF//./\\.}(,|$)" "$P/run/NetworkManager/system-connections/" || FALTA+="$IPF "
    done < <(sed 's/#.*$//' "$NP_DIR"/*.yaml 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}' | sort -u || true)
  else
    FALTA="(netplan no acepto la configuracion: $(tail -2 "$P/generate.txt" 2>/dev/null | tr '\n' ' '))"
  fi
  if [[ -z "$FALTA" ]]; then
    for F in "$NP_DIR"/*.yaml; do
      B="$(basename "$F")"
      if [[ " ${QUITAR[*]} " == *" $B "* ]]; then retirar "$F"; continue; fi
      if [[ -f "$P/etc/netplan/$B" ]] && ! cmp -s "$F" "$P/etc/netplan/$B"; then
        respaldar "$F"; cat "$P/etc/netplan/$B" > "$F"
      fi
    done
    escribir_sistema "$NP_DIR/00-default-use-network-manager.yaml" < "$P/etc/netplan/00-default-use-network-manager.yaml"
    chmod 600 "$NP_DIR"/*.yaml
    # NetworkManager como en Armbian: WiFi sin MAC aleatoria al buscar y sin ahorro de energia
    escribir_sistema /etc/NetworkManager/conf.d/zz-10-override-wifi-random-mac-disable.conf <<'EOF'
[connection]
wifi.mac-address-randomization=1

[device]
wifi.scan-rand-mac-address=no
EOF
    escribir_sistema /etc/NetworkManager/conf.d/zz-20-override-wifi-powersave-disable.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
    # las esperas de red en el arranque (hasta 90 s) sobran con NetworkManager
    systemctl disable NetworkManager-wait-online.service systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    if [[ -f "$NM_TRANS" ]]; then instalar_unidad_red; fi
    CONEXIONES="$(find "$P/run/NetworkManager/system-connections" -name '*.nmconnection' -printf '%f ' 2>/dev/null | sed 's/netplan-//g; s/\.nmconnection//g')"
    RED_ESTADO="pasa a NetworkManager al reiniciar"
    log "La red pasa a NetworkManager al reiniciar (netplan: ${CONEXIONES:-sin conexiones propias}); la conexion de ahora no se corta"
  else
    warn "netplan no pudo pasar la red a NetworkManager sin perder configuracion ($FALTA): la red se queda con systemd-networkd"
    # NetworkManager solo para lo que systemd-networkd no maneja (p. ej. un WiFi nuevo desde DMS)
    mapfile -t NOMBRES < <(grep -h '^Name=' "$TMPD/np-hoy/run/systemd/network/"*.network 2>/dev/null | cut -d= -f2- | tr ' ' '\n' | sort -u || true)
    L=""
    for N in "${NOMBRES[@]}"; do if [[ -n "$N" ]]; then L+="interface-name:$N;"; fi; done
    escribir_sistema /etc/NetworkManager/conf.d/90-opi4pro-networkd.conf <<EOF
# Generado por $NOMBRE.sh: estas interfaces las sigue manejando systemd-networkd (netplan)
[keyfile]
unmanaged-devices=${L%;}
EOF
    if [[ -f "$NM_TRANS" ]]; then instalar_unidad_red; fi
    RED_ESTADO="systemd-networkd (NetworkManager solo para lo demas)"
  fi
fi

# ============================================================================
header "11. Ultima pasada: lo mas nuevo de los repos (sin quitar nada)"
# ============================================================================
apt_update
# lo que no pudo bajar antes (p. ej. si el mirror de Armbian estaba caido): aqui todos los
# repos ya estan activos
if (( ${#REINTENTAR[@]} )); then
  mapfile -t REINTENTAR_UNICOS < <(printf '%s\n' "${REINTENTAR[@]}" | sort -u)
  nota "Reintento final de paquetes que fallaron antes: ${REINTENTAR_UNICOS[*]}"
  apti_try "${REINTENTAR_UNICOS[@]}"
fi
if ! apt-get "${APT_OPTS[@]}" full-upgrade; then
  reparar_dpkg
  warn "full-upgrade final no se completo (si pedia quitar paquetes, el script no lo hace): revisalo con  sudo apt full-upgrade"
fi
apt-get -q autoclean || true
ldconfig

# ============================================================================
header "12. Verificacion final"
# ============================================================================
v() { printf '  %-30s %s\n' "$1" "$2"; }
DUENO_CFG="$(stat -c %U "$CFG" 2>/dev/null || echo '?')"
ROTOS="$(dpkg --audit 2>/dev/null | head -3 || true)"
FALTAN_ARMBIAN=()
for P in "${ARMBIAN_ANTES[@]}"; do instalado "$P" || FALTAN_ARMBIAN+=("$P"); done
ARRANQUE_DESPUES="$(readlink /boot/Image 2>/dev/null || echo -) $(readlink /boot/uInitrd 2>/dev/null || echo -)"
LIBS_HYPR="$(ldd /usr/bin/Hyprland 2>/dev/null | awk '$1 ~ /^lib(EGL|gbm)\.so\.1$/ {printf "%s ", $3}' || true)"
# revalidar la config de Hyprland al FINAL: asi, si la seccion 9 falto por un paquete que
# no se pudo bajar (mirror caido) y el reintento de la 11 lo instalo, aqui ya queda OK
if [[ "$HYPR_ESTADO" != valida* ]] && [[ -f "$HOME_USR/.config/hypr/hyprland.lua" ]]; then
  VRT2="$TMPD/xdg-runtime2"; install -d -m 0700 -o "$USUARIO" -g "$USUARIO" "$VRT2"
  if runuser -u "$USUARIO" -- env HOME="$HOME_USR" XDG_RUNTIME_DIR="$VRT2" PATH="/usr/bin:/bin" LD_BIND_NOW=1 \
       Hyprland --verify-config --config "$HOME_USR/.config/hypr/hyprland.lua" > "$TMPD/verify2.txt" 2>&1; then
    HYPR_ESTADO="valida (revalidada al final)"; log "hyprland.lua revalidada al final (con todos los paquetes puestos)"
  elif grep -qE 'symbol lookup error|undefined symbol|cannot open shared object' "$TMPD/verify2.txt"; then
    warn "Hyprland sigue sin enlazar con las librerias: $(head -2 "$TMPD/verify2.txt" | tr '\n' ' ')"
  fi
fi
if gpu_powervr_presente; then
  if [[ "$LIBS_HYPR" == */usr/local/lib/libEGL.so.1* && "$LIBS_HYPR" == */usr/local/lib/libgbm.so.1* ]]; then
    GPU_ESTADO="drivers presentes; Hyprland usa los de PowerVR"
  else
    GPU_ESTADO="drivers presentes, pero Hyprland NO los usa"
    warn "Hyprland no usa las librerias de la GPU ($LIBS_HYPR): revisa /etc/ld.so.conf.d/00-pvr-priority.conf y ejecuta sudo ldconfig"
  fi
fi
{
  v "Placa"                    "${PLACA_NOMBRE:-${PLACA:-?}} (Armbian ${ARMBIAN_VER:-?}, kernel ${RAMA:-?})"
  v "Hyprland"                 "$(version_de hyprland)"
  v "DankMaterialShell (dms)"  "$(version_de dms)"
  v "Quickshell"               "$(version_de quickshell)"
  v "Configuracion de DMS"     "$DMS_ESTADO"
  v "Config de Hyprland (Lua)" "$HYPR_ESTADO"
  v "GPU PowerVR"              "$GPU_ESTADO"
  v "Red"                      "$RED_ESTADO"
  v "Paquetes de Armbian"      "$(if (( ${#FALTAN_ARMBIAN[@]} )); then echo "FALTAN: ${FALTAN_ARMBIAN[*]}"; else echo "intactos (${#ARMBIAN_ANTES[@]})"; fi)"
  v "Arranque (/boot)"         "$(if [[ "$ARRANQUE_DESPUES" == "$ARRANQUE_ANTES" ]]; then echo "sin cambios: Image=${ARRANQUE_DESPUES% *}  uInitrd=${ARRANQUE_DESPUES#* }"; else echo "CAMBIO: $ARRANQUE_ANTES -> $ARRANQUE_DESPUES"; fi)"
  v "Navegador por defecto"    "${NAVEGADOR:-ninguno}"
  v "Inicio de sesion"         "greetd ($(systemctl is-enabled greetd 2>/dev/null || echo '?'), autologin=$AUTOLOGIN)"
  v "Idioma del sistema"       "$(grep -E '^LANG=' /etc/default/locale 2>/dev/null | cut -d= -f2 || echo '?')"
  v "Teclado"                  "${TECLADO}${TECLADO_VAR:+ ($TECLADO_VAR)}"
  v "Dueno de ~/.config"       "$DUENO_CFG"
  v "PipeWire"                 "$(version_de pipewire)"
  v "Kernels instalados"       "$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f ' 2>/dev/null | sed 's/vmlinuz-//g')"
  v "dpkg (paquetes a medias)" "$(if [[ -z "$ROTOS" ]]; then echo ninguno; else echo "HAY: revisa dpkg --audit"; fi)"
} | tee "$TMPD/verificacion.txt"
if (( ${#FALTAN_ARMBIAN[@]} )); then warn "Faltan paquetes de Armbian que estaban al empezar: ${FALTAN_ARMBIAN[*]}"; fi
if [[ "$ARRANQUE_DESPUES" != "$ARRANQUE_ANTES" ]]; then
  warn "Cambio con que arranca la placa (/boot/Image y /boot/uInitrd): antes $ARRANQUE_ANTES, ahora $ARRANQUE_DESPUES. Revisalo ANTES de reiniciar."
fi
if [[ "$DUENO_CFG" != "$USUARIO" ]]; then warn "$CFG no es de $USUARIO"; fi
if [[ -n "$ROTOS" ]]; then warn "dpkg reporta paquetes a medias: ejecuta sudo dpkg --configure -a"; fi
for P in hyprland dms quickshell greetd; do instalado "$P" || warn "Falta $P"; done

# ============================================================================
header "REPORTE DE LA INSTALACION"
# ============================================================================
REPORTE="$HOME_USR/reporte-instalacion-${RUN_TS}.txt"
{
  echo "Orange Pi 4 Pro + Hyprland + Quickshell + DankMaterialShell  (script v$VER)"
  echo "Fecha: $(date '+%Y-%m-%d %H:%M')    Placa: ${PLACA:-?}    Usuario: $USUARIO"
  echo
  resumen_texto
  echo
  echo "Verificacion:"
  cat "$TMPD/verificacion.txt"
  echo
  echo "Paquetes instalados: $(dpkg-query -W -f='${db:Status-Abbrev}\n' 2>/dev/null | grep -c '^ii' || true)"
  echo "Espacio usado en /:  $(df -h / | awk 'NR==2{print $3" de "$2" ("$5")"}')"
  echo "Repositorios:        $(find /etc/apt/sources.list.d -maxdepth 1 \( -name '*.list' -o -name '*.sources' \) -printf '%f ' 2>/dev/null)"
  echo
  echo "Avisos (${#AVISOS[@]}):"
  if (( ${#AVISOS[@]} )); then printf '  - %s\n' "${AVISOS[@]}"; else echo "  (ninguno)"; fi
  if (( ${#NOTAS[@]} )); then echo "Notas:"; printf '  - %s\n' "${NOTAS[@]}"; fi
  if (( ${#RESPALDOS[@]} )); then echo "Respaldos de lo que se cambio:"; printf '  - %s\n' "${RESPALDOS[@]}"; fi
  echo
  echo "Registro completo: $LOG"
} > "$REPORTE"
chown "$USUARIO:$USUARIO" "$REPORTE"
cat "$REPORTE"

header "LISTO"
if (( ${#AVISOS[@]} == 0 )); then log "Instalacion completada sin avisos."
else echo "${YELLOW}Instalacion completada con ${#AVISOS[@]} aviso(s): estan en el reporte.${NC}"; fi
cat <<EOF

${BOLD}Siguiente paso:${NC}  sudo reboot
  - Al arrancar, la red pasa a NetworkManager (tu IP fija y tu WiFi de netplan se conservan).
  - $(if [[ $AUTOLOGIN == si ]]; then echo "Entras directo al escritorio."; else echo "greetd te pide usuario y contrasena y abre el escritorio."; fi)
  - Si la pantalla se queda negra: Ctrl+Alt+F2 (o entra por SSH) y ejecuta  diagnostico-gpu

${BOLD}Atajos principales (DankMaterialShell):${NC}
  Super+Espacio  menu de apps              Super+Enter   terminal (Alacritty)
  Super+B        navegador                 Super+E       archivos
  Super+V        portapapeles              Super+C       ajustes de DMS
  Super+Y        fondos de pantalla        Super+X       apagar / reiniciar
  Super+Alt+L    bloquear                  Super+Q       cerrar ventana
  Super+1..9     escritorios               Impr          captura de pantalla
  Super+Shift+/  todos los atajos

${BOLD}Una sola vez, si quieres:${NC}
  - Idioma de la barra: Ajustes de DMS (Super+C) -> Idioma.
  - Colores en apps GTK: Ajustes de DMS -> Tema -> aplicar temas GTK.

Reporte: $REPORTE
EOF
