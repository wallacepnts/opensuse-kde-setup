#!/bin/bash
# Installs DaVinci Resolve and disables its bundled glib, which makes it crash.
#
#   ./install-davinci.sh --check   report the available version and exit
#
# The download API expects a registration form; the script sends generic data,
# as the AUR package does. Resolve is free — no licence is bypassed.
set -euo pipefail

# Messages follow the session language; empty locale falls back to the system one.
L="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
[ -n "$L" ] || L=$(sed -n 's/^LC_MESSAGES=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
[ -n "$L" ] || L=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
case "$L" in pt*) PT=1;; *) PT=0;; esac
say(){ if [ "$PT" = 1 ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }

API=https://www.blackmagicdesign.com/api/support/latest-stable-version/davinci-resolve/linux
REFERID=dfd43085ef224766b06b579ce8a6d097
DEST=${DEST:-$(xdg-user-dir DOWNLOAD 2>/dev/null || echo "$HOME/Downloads")}

info=$(curl -sL --max-time 30 "$API") || {
  say "could not reach the API" "falha ao consultar a API"; exit 1; }
parsed=$(printf '%s' "$info" | python3 -c '
import sys,json
d=json.load(sys.stdin)["linux"]
maj,mi,rel=d["major"],d["minor"],d["releaseNum"]
ver=f"{maj}.{mi}.{rel}"
print(ver, ver if rel else f"{maj}.{mi}", d["downloadId"])') || {
  say "could not read the API response" "não foi possível ler a resposta da API"; exit 1; }
read -r VER FILEVER DLID <<<"$parsed"
if [ -z "$VER" ] || [ -z "$FILEVER" ] || [ -z "$DLID" ]; then
  say "unexpected API response" "resposta inesperada da API"
  exit 1
fi

say "available version: $VER" "versão disponível: $VER"
[ "${1:-}" = "--check" ] && exit 0

# Fail early if sudo is unavailable, then keep the timestamp warm: the download
# below outlasts the default sudo timeout, and the install would stop to ask.
sudo -v || { say "this script needs sudo to install" "este script precisa de sudo para instalar"; exit 1; }
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null' EXIT

if [ -d /opt/resolve ]; then
  atual=$(grep -oE 'Resolve [0-9]+\.[0-9]+\.[0-9]+' /opt/resolve/docs/Release_Notes.html 2>/dev/null | head -1 | awk '{print $2}' || true)
  [ -n "${atual:-}" ] && say "installed now:     $atual" "instalado hoje:    $atual"
fi

ARQ="DaVinci_Resolve_${FILEVER}_Linux"
mkdir -p "$DEST"; cd "$DEST"

if [ ! -f "$ARQ.run" ]; then
  say "### getting the download URL" "### obtendo a URL de download"
  req='{"firstname":"Linux","lastname":"User","email":"user@example.com","phone":"000-000-0000","country":"us","street":"1 Main St","state":"New York","city":"New York","product":"DaVinci Resolve"}'
  url=$(curl -s --max-time 60 \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json;charset=UTF-8' \
    -H "Referer: https://www.blackmagicdesign.com/support/download/${REFERID}/Linux" \
    -H 'Origin: https://www.blackmagicdesign.com' \
    -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36' \
    --data-ascii "$req" \
    "https://www.blackmagicdesign.com/api/register/us/download/${DLID}")
  case "$url" in http*) ;; *)
    say "unexpected API response: ${url:0:120}" "resposta inesperada da API: ${url:0:120}"; exit 1;; esac

  say "### downloading (~3 GB)" "### baixando (~3 GB)"
  # -f so an HTTP error page is never saved as the archive, which would then
  # poison the '-C -' resume offset on every later run.
  curl -fL -C - --max-time 3600 -o "$ARQ.zip" "$url"
  unzip -o "$ARQ.zip" || { rm -f "$ARQ.zip"
    say "corrupt archive, removed — run again" "arquivo corrompido, removido — rode de novo"; exit 1; }
  rm -f "$ARQ.zip"
fi

say "### dependencies" "### dependências"
sudo zypper -n install libxcb-dri2-0 libxcb-dri2-0-32bit libgthread-2_0-0 \
  libgthread-2_0-0-32bit libapr1-0 libapr-util1-0 libQt5Gui5 \
  libglib-2_0-0 libglib-2_0-0-32bit libgio-2_0-0 libgmodule-2_0-0

say "### installing" "### instalando"
chmod +x "$ARQ.run"
sudo SKIP_PACKAGE_CHECK=1 "./$ARQ.run" -i

# Every update restores these libs, so this repeats on each install.
say "### disabling the bundled libraries" "### desativando as bibliotecas empacotadas"
sudo mkdir -p /opt/resolve/libs/_disabled
for l in /opt/resolve/libs/libgio* /opt/resolve/libs/libglib* /opt/resolve/libs/libgmodule* \
         /opt/resolve/libs/libgobject*; do
  [ -e "$l" ] || continue
  sudo mv "$l" /opt/resolve/libs/_disabled/
done

echo
say "done. Run it with:  /opt/resolve/bin/resolve" \
    "pronto. Execute com:  /opt/resolve/bin/resolve"
say "On Wayland, if the window does not open:  QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve" \
    "Em sessão Wayland, se a janela não abrir:  QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve"
echo
say "Remember: the free version does not IMPORT H.264/H.265 on Linux. Transcode first:" \
    "Lembre: a versão gratuita não IMPORTA H.264/H.265 no Linux. Transcodifique antes:"
echo "  ffmpeg -i entrada.mp4 -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p -c:a pcm_s16le saida.mov"
