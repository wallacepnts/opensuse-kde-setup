# openSUSE Tumbleweed e Slowroll — Instalação

[English](installation-guide.md) · **Português**

KDE Plasma · systemd-boot · btrfs com snapshots. Vale para qualquer máquina e para as duas
variantes; o que depende de hardware está marcado (NVIDIA, WiFi, Windows, disco de dados) e
o que muda no Slowroll está indicado no lugar.

---

## 1. Instalador

Tela travada ao iniciar: tecla `E` no menu, `nomodeset` depois de `splash=silent`, `F10`.

### Particionamento

**Particionador avançado → Iniciar com as partições existentes.** A proposta guiada cria ESP de
1 GB; com systemd-boot kernel e initrd moram na ESP e ela enche.

| Partição | Tamanho | Papel |
|---|---|---|
| ESP | **2 GiB** | Partição de inicialização EFI |
| raiz | restante | Sistema operacional → Btrfs em `/`, ☑ **Habilitar Snapshots** |
| swap | 2 GiB | Troca |

Confira os subvolumes `@/home`, `@/opt`, `@/root`, `@/srv`, `@/usr/local`, `@/var` na partição
raiz — sem eles o snapper não funciona. Não toque nos outros discos.

Marcar **Habilitar Snapshots** faz mais do que ligar o snapper: o instalador troca quatro valores
do `/etc/snapper/configs/root` em relação ao modelo do pacote — cria a cota do btrfs
(`QGROUP="1/0"`), aperta `NUMBER_LIMIT` de 50 para `2-10`, `NUMBER_LIMIT_IMPORTANT` de 10 para
`4-10` e desliga `TIMELINE_CREATE`. É a cota que faz valer o `SPACE_LIMIT="0.5"` e o
`FREE_LIMIT="0.2"`, isto é, o que impede a raiz encher de snapshot. Criando a configuração à mão
depois (`snapper -c root create-config /`) você fica com o modelo cru, sem cota.

### Demais opções

| | |
|---|---|
| Bootloader | **Boot do Systemd** |
| Secure Boot | ver §3.2 |
| SELinux | `enforcing` |
| SSH | habilitar serviço **e** abrir a porta, se for usar |
| Usuário | desmarque "usar esta senha para o administrador" |
| Repositórios online | pular |

---

## 2. Antes do primeiro `zypper dup`

```bash
sudo tee /etc/zypp/zypp.conf > /dev/null <<'EOT'
[main]
multiversion = provides:multiversion(kernel)
multiversion.kernels = latest,latest-1,running
EOT
sudo systemctl enable purge-kernels.service

sudo tee /etc/dracut.conf.d/99-enxuto.conf > /dev/null <<'EOT'
hostonly="yes"
hostonly_mode="strict"
compress="zstd"
EOT
sudo sdbootutil mkinitrd
```

Se o `zypp.conf` já existir, insira as linhas dentro do `[main]` — sem o cabeçalho o libzypp
ignora o arquivo. Sempre `sdbootutil mkinitrd`, nunca `dracut -f`: o dracut não copia o initrd
para a ESP. `latest-1` permite bootar o kernel anterior se o driver NVIDIA atrasar. Troca de
placa-mãe pode exigir `dracut -f --no-hostonly` uma vez.

---

## 3. Repositórios e drivers

```bash
echo 'export ZYPP_MEDIANETWORK=1' >> ~/.bashrc
export ZYPP_MEDIANETWORK=1
echo 'Defaults env_keep += "ZYPP_MEDIANETWORK"' | sudo tee /etc/sudoers.d/zypp-medianetwork
zypper lr -u
sudo zypper rr <alias-do-repo-hd:/-ou-cd:/>
sudo zypper ref && sudo zypper dup && sudo reboot
```

O `rr` remove o repositório da mídia de instalação (URI `hd:/` ou `cd:/`); com ele o `dup`
aborta sem a mídia conectada.

### 3.1 NVIDIA

*Só com GPU NVIDIA.* Descubra o chip:

```bash
lspci -nn | grep -i vga
# 01:00.0 VGA ... NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82]
```

O prefixo do codinome (`GP107` → `GP`) define a arquitetura, e ela define o driver:

| Arquitetura | Codinome | Driver |
|---|---|---|
| Turing a Blackwell | `TU` `GA` `AD` `GH` `GB` | `nvidia-open-driver-G07-signed-kmp-meta` — aberto e assinado |
| Maxwell, Pascal, Volta | `GM` `GP` `GV` | `nvidia-driver-G06-kmp-meta` — proprietário |
| Kepler | `GK` | `x11-video-nvidiaG05 nvidia-glG05 nvidia-computeG05` — legado |
| Fermi e anteriores | `GF` `NV` `G8` `GT2` | não funcionam com kernel 6.6+ — use `nouveau` |

O módulo aberto exige Turing ou mais novo; o proprietário G06 é o único que serve para
Maxwell, Pascal e Volta. Turing em diante pode usar os dois, mas o aberto assinado dispensa o
ritual do MOK com Secure Boot ligado (§3.2) — e é o que a NVIDIA recomenda. Se precisar do
aberto na série 580 em vez da 595, existe `nvidia-open-driver-G06-signed-kmp-meta`.

Se o `lspci` não trouxer o codinome, a [lista da
Wikipédia](https://en.wikipedia.org/wiki/List_of_Nvidia_graphics_processing_units) mapeia cada
modelo (GTX 1050 Ti → GP107 → Pascal → G06).

```bash
sudo zypper install openSUSE-repos-Tumbleweed-NVIDIA
sudo zypper install <pacote da tabela>
```

Slowroll: `openSUSE-repos-Slowroll-NVIDIA`. Os dois apontam para o mesmo repositório.

Confirmar antes de instalar que o proprietário atende a placa — só ele declara os IDs PCI, e
a lista cobre exatamente Maxwell, Pascal e Volta:

```bash
ID=$(lspci -nn | grep -i vga | grep -oiE "10de:[0-9a-f]{4}" | cut -d: -f2 | tr a-f A-F)
sudo zypper download nvidia-driver-G06-kmp-default
rpm -qp --supplements /var/cache/zypp/packages/*/*/nvidia-driver-G06-kmp-default-*.rpm | grep -i "d0000$ID" && echo SUPORTADA
```

Sem resultado, a placa é Turing ou mais nova: vá de aberto assinado. Os pacotes abertos não
declaram IDs, então para eles vale a tabela.

Com o driver instalado o initrd salta para ~130-140 MB, contra menos de 80 MB sem ele: o
`kernel-firmware-nvidia` traz o firmware de todas as gerações e o dracut copia o pacote inteiro,
mesmo com `hostonly` (§2). Não há opção que filtre por modelo — é o motivo da ESP de 2 GiB do §1,
e não vale tentar enxugar.

### 3.2 Secure Boot

Driver aberto assinado (Turing em diante): pode ficar ligado. Driver proprietário G06 ou
anterior: desligue, ou aceite o MOK a cada atualização — no primeiro reboot o `mokutil` abre:
**Enroll MOK → Continue → Yes → senha do root (teclado US)**. Sem NVIDIA: ligado.

### 3.3 Codecs

```bash
sudo zypper addrepo -cfp 90 'https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/Essentials/' packman-essentials
sudo zypper refresh
sudo zypper install --allow-vendor-change --from packman-essentials ffmpeg gstreamer-plugins-{good,bad,ugly,libav} libavcodec vlc-codecs
```

Slowroll: `openSUSE_Slowroll` no lugar de `openSUSE_Tumbleweed` na URL.

Conferir:

```bash
rpm -q --qf '%{VENDOR} %{NAME}\n' Mesa Mesa-dri libgbm1
rpm -q --qf '%{VENDOR} %{NAME}\n' ffmpeg vlc-codecs
sudo zypper dup --dry-run
```

Mesa é `openSUSE`, ffmpeg e vlc-codecs são `packman`, o `dup` diz "Nada a fazer".
`gstreamer-plugins-libav` continua `openSUSE` mesmo com tudo certo.

Nunca `zypper dup --from packman --allow-vendor-change`: troca a pilha gráfica inteira. O
Packman versiona o ffmpeg (`ffmpeg-8`, `ffmpeg-9`…); confira sempre pelo pacote sem sufixo.

### 3.4 Aplicativos

```bash
sudo zypper install git-core fetchmsttfonts btop fastfetch elisa mpv kwrite kdeconnect-kde steam gamemode earlyoom flatpak krita krita-plugin-gmic foliate
sudo systemctl enable --now earlyoom
sudo zypper install tailscale && sudo systemctl enable --now tailscaled && sudo tailscale up
sudo zypper install -t pattern container_runtime_podman
sudo zypper rm discover6-backend-packagekit discover6-notifier
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub \
  app.katvan.Katvan com.bitwarden.desktop com.github.tchx84.Flatseal \
  com.vysp3r.ProtonPlus io.anytype.anytype \
  io.github.CyberTimon.RapidRAW io.github.alainm23.planify org.jeffvli.feishin \
  org.jellyfin.JellyfinDesktop org.localsend.localsend_app \
  org.onlyoffice.desktopeditors rocks.koreader.KOReader
flatpak install --user ~/HD/Downloads/melia_*.flatpak
flatpak install --user ~/HD/Downloads/naps2-*-linux-x64.flatpak
curl -f https://zed.dev/install.sh | sh
```

- `git-core` é o Git completo; `git` é só um meta com Perl.
- PackageKit trava o `zypper` e aplica semântica de `update`. O Discover fica para Flatpak e
  firmware. Não use `zypper install-new-recommends`: reinstala os dois pacotes removidos.
- Flatpak sempre `--user`, inclusive no `remote-add` — sem o `--user` ali o repositório entra
  só no escopo do sistema e o `install --user` responde *nenhuma ref de remoto localizada*. Não
  instale pelo Discover, que usa `--system` e duplica o aplicativo.
- Krita e Foliate vão pelo `zypper`, não pelo Flathub — mesma versão nos dois lados. O Krita é
  Qt: nativo aproveita o Qt e o tema já instalados, os diálogos do KIO e o `krita-plugin-gmic`,
  que não existe no Flatpak, e o Flatpak ainda ocupa 634 MB com `filesystems=host` (sandbox
  nenhum na prática). O Foliate costuma ser o único aplicativo preso a uma versão antiga do
  `org.gnome.Platform`, e cada versão dessa runtime custa 1,1 GB.
- LocalSend precisa da porta 53317 aberta no firewall (§5) para **receber**; sem ela, enviar
  funciona e receber não, sem erro que explique.
- Melia e NAPS2 não estão no Flathub ([melia](https://melia.buxjr.com) ·
  [naps2](https://www.naps2.com/download)); não recebem `flatpak update`. Guarde os arquivos.
- Zed fica em `~/.local/zed.app`, fora do `zypper` e do `flatpak`; atualiza sozinho.
- Contêineres não vêm na instalação. O padrão `container_runtime_podman` traz o `podman` com o
  `buildah` (construir imagem passo a passo, sem `Containerfile`) e o `skopeo` (inspecionar e
  copiar imagem entre registros sem baixar nem executar). Só para rodar e construir por
  `Containerfile`, `sudo zypper install podman` basta — ele já embute o buildah.

De onde instalar cada coisa:

| Origem | Quando | Exemplos aqui |
|---|---|---|
| `zypper` (repos oficiais) | tudo que existir empacotado — integra com snapshot e `dup` | sistema, drivers, KDE |
| Packman Essentials | só os codecs (§3.3) | `ffmpeg`, `vlc-codecs` |
| Repositório do fabricante | driver que o openSUSE não empacota | NVIDIA (§3.1) |
| OBS (`network:chromium`) | pacote fora dos repos oficiais, mantido por terceiro | Ungoogled Chromium (§3.5) |
| Flatpak `--user` | aplicativo gráfico que não existe no `zypper`, ou versão mais nova | Anytype, KOReader, Bitwarden |
| Instalador próprio | sem pacote em lugar nenhum; atualiza sozinho | Zed, ícones Tela |

Cada linha abaixo da primeira é uma exceção assumida: quanto mais fundo na tabela, mais o
`zypper dup` e o snapper deixam de enxergar o que você instalou.

**Ícones Tela** — sem pacote; script em `~/.local/share/icons`, sem `sudo`:

```bash
git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git ~/HD/Downloads/Tela-icon-theme
~/HD/Downloads/Tela-icon-theme/install.sh green
kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-green-dark
```

Uma cor ocupa ~185 MB; `-a` (todas) passa de 2 GB. Atualizar é `git pull` e rodar de novo;
remover é `install.sh -r`.

A cor é argumento posicional; `-c` é outra opção.

### 3.5 Ungoogled Chromium

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/network:chromium/openSUSE_Tumbleweed/network:chromium.repo
sudo zypper modifyrepo -f network_chromium
sudo zypper refresh && sudo zypper install ungoogled-chromium
```

Sem o `modifyrepo -f` o navegador não recebe atualizações. Slowroll: o `network:chromium` não
tem build; use o Flatpak `io.github.ungoogled_software.ungoogled_chromium` e pule o resto desta
seção.

O pacote reaproveita o `.desktop` genérico do Chromium (nome e ícone errados). Correção, com o
tema Tela instalado:

```bash
I=io.github.ungoogled_software.ungoogled_chromium
mkdir -p ~/.local/share/icons/hicolor/scalable/apps ~/.local/share/applications
cp ~/.local/share/icons/Tela-green/scalable/apps/$I.svg ~/.local/share/icons/hicolor/scalable/apps/
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
cp /usr/share/applications/chromium-browser.desktop ~/.local/share/applications/
sed -i '0,/^\[Desktop Action/{s/^Name=.*/Name=Ungoogled Chromium/}' ~/.local/share/applications/chromium-browser.desktop
sed -i "s|^Icon=chromium-browser$|Icon=$I|" ~/.local/share/applications/chromium-browser.desktop
kbuildsycoca6 --noincremental
```

Só o ícone de nome longo é o do Ungoogled; `ungoogled-chromium.svg` e os `com.github.Eloston.*`
são links para o logo do Chromium comum.

### 3.6 Vídeo e DaVinci Resolve

→ **[vídeo e DaVinci Resolve](video-davinci.pt-BR.md)** · `./scripts/install-davinci.sh`

### 3.7 Microcódigo da CPU

```bash
sudo zypper install ucode-intel
sudo sdbootutil mkinitrd && sudo reboot
```

CPU AMD: `ucode-amd`. Conferir depois:

```bash
grep -r . /sys/devices/system/cpu/vulnerabilities/ | grep -i "no microcode"
```

Sem o pacote várias mitigações ficam desligadas; a saída acima tem que vir vazia.

### 3.8 WiFi

*Só com WiFi.*

```bash
sudo zypper install wireless-regdb && sudo reboot
sudo journalctl -k -b | grep -i regulatory
```

Sem o pacote o WiFi fica no domínio regulatório "mundo", com menos alcance. O log não pode
dizer `failed to load`.

### 3.9 Nome da máquina

```bash
sudo hostnamectl hostname nome-da-maquina
grep -q " $(hostname)$" /etc/hosts || echo "127.0.0.1  $(hostname)" | sudo tee -a /etc/hosts
```

Sem nome definido o sistema fica como `localhost.localdomain` — é o padrão quando o campo é
deixado em branco no instalador. Use letras minúsculas, dígitos e hífen. O verbo `hostname` é
obrigatório: `hostnamectl <nome>` responde *Unknown command verb*.

A linha no `/etc/hosts` não é decoração: o `nsswitch.conf` do openSUSE não traz o módulo
`myhostname`, então o próprio nome da máquina não resolve sozinho e programas que consultam o
DNS local reclamam. Confira depois com `getent hosts $(hostname)`.

O nome só aparece no prompt de terminais abertos depois da troca. Programas que gravaram o
nome antigo (KDE Connect, Tailscale) precisam ser reapontados na interface deles.

---

## 4. Disco de dados

*Só com um segundo disco para dados.* Ele não é formatado; só o que mora no SSD é refeito.

```bash
lsblk -f
DISCO=/dev/sdXN
sudo mkdir -p ~/HD
udisksctl unmount -b $DISCO 2>/dev/null
echo "UUID=$(lsblk -no UUID $DISCO)  $HOME/HD  btrfs  defaults,noatime,compress=zstd:1,nofail  0  0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
findmnt ~/HD && ls -ld ~/HD
```

O `findmnt` tem que responder e o dono de `~/HD` tem que ser você. Disco ext4: troque
`btrfs defaults,noatime,compress=zstd:1,nofail` por `ext4 defaults,noatime,nofail` e pule o scrub e
o `chattr`.

O `nofail` cala erro de UUID, por isso a conferência. O `sudo mkdir` é proposital: a pasta de
root barra escrita se o disco não montar.

```bash
sudo sed -i "s|^BTRFS_SCRUB_MOUNTPOINTS=.*|BTRFS_SCRUB_MOUNTPOINTS=\"/:$HOME/HD\"|" /etc/sysconfig/btrfsmaintenance
sudo systemctl restart btrfs-scrub.timer

mkdir -p ~/HD/{Desktop,Documents,Downloads,Music,Pictures,Projects,Public,Templates,Videos}
rmdir ~/"Área de trabalho" ~/Documentos ~/Downloads ~/Imagens ~/Modelos ~/"Músicas" ~/Projetos ~/"Público" ~/"Vídeos" 2>/dev/null
ln -s HD/Desktop   ~/"Área de trabalho"
ln -s HD/Documents ~/Documentos
ln -s HD/Downloads ~/Downloads
ln -s HD/Music     ~/"Músicas"
ln -s HD/Pictures  ~/Imagens
ln -s HD/Projects  ~/Projetos
ln -s HD/Public    ~/"Público"
ln -s HD/Templates ~/Modelos
ln -s HD/Videos    ~/"Vídeos"
xdg-user-dirs-update
rm -f ~/.local/share/user-places.xbel

grep -q '^\[General\]' ~/.config/baloofilerc 2>/dev/null || echo '[General]' >> ~/.config/baloofilerc
printf 'exclude folders[$e]=%s\n' "$HOME/HD/Games/,$HOME/HD/.pnpm-store/,$HOME/HD/VMs/,$HOME/HD/old/,$HOME/HD/.Trash-$(id -u)/,$HOME/Windows/" >> ~/.config/baloofilerc
balooctl6 disable && balooctl6 enable

mkdir -p ~/HD/VMs && chattr +C ~/HD/VMs
```

Os arquivos ficam no disco e a home recebe um link para cada pasta: o caminho do dia a dia é
`~/Documentos`, e o `ls -l ~` mostra para onde ele aponta. O link é relativo (`HD/Documents`),
para sobreviver a uma troca de nome da home, e o `rmdir` vem antes do `ln -s`, senão o link não
nasce.

O nome do link segue o locale; o do disco não. No disco valem os nomes do
`/etc/xdg/user-dirs.defaults`, em inglês — em português só `Downloads` coincide nos dois lados. O
disco sobrevive à reinstalação e o idioma não, então os nomes lá dentro ficam neutros e o locale
mora só na camada de links, que é descartável. É também o que dispensa escrever o
`user-dirs.dirs`: com os links já nomeados como o locale espera, o `xdg-user-dirs-update` gera o
arquivo certo sozinho, e segue gerando a cada login. Escrevê-lo à mão com outros nomes é brigar
com ele.

Link simbólico, não bind mount: o conteúdo existe num lugar só, o Baloo indexa uma vez (ele não
segue link) e o `du ~` não conta em dobro. Em troca, `realpath` responde o caminho real dentro de
`~/HD`, e alguns programas mostram esse — a trilha do Dolphin, por exemplo. Com o disco
desmontado os links ficam pendurados e a gravação falha, melhor do que gravar no SSD achando que
deu certo; o `xdg-user-dirs-update` não troca link pendurado por pasta de verdade, mas cria no
SSD qualquer uma das nove que esteja faltando.

O `rm` do `user-places.xbel` regenera os locais do Dolphin, que não acompanham a mudança — rode
com o Dolphin fechado. `chattr +C` só vale para arquivos criados depois.

`Projetos` está no template do sistema (`/etc/xdg/user-dirs.defaults`), mas o Dolphin não a cria
nos locais. Arraste a pasta para a barra lateral e dê a ela o ícone `folder-development`:

```bash
printf '[Desktop Entry]\nIcon=folder-development\nType=Directory\n' > ~/Projetos/.directory
```

No atalho da barra lateral vai uma engrenagem sozinha: o `folder-development` sairia colorido
ali, porque o Tela (§3.4) só o tem em 16 px e no `scalable`, e o `scalable` é um link para
`default-folder-system`. A arte vem do [SVG Repo](https://www.svgrepo.com/svg/479390/gear),
recolorida para seguir o esquema de cores e reduzida para sobrar margem; vai no `hicolor`, que o
Tela herda e o `install.sh` dele não sobrescreve:

```bash
mkdir -p ~/.local/share/icons/hicolor/scalable/places
curl -sS https://www.svgrepo.com/show/479390/gear.svg |
  sed -e 's|<style type="text/css">|<style id="current-color-scheme" type="text/css">|' \
      -e 's|\.st0{fill:#000000;}|.ColorScheme-Text { color:#aaaaaa; }|' \
      -e 's|class="st0"|class="ColorScheme-Text" style="fill:currentColor"|' \
      -e 's|<g>|<g transform="translate(71.7 71.7) scale(0.72)">|' \
  > ~/.local/share/icons/hicolor/scalable/places/gear-projetos.svg
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

Use `gear-projetos` no atalho. A URL de download do SVG Repo cai num desafio da Vercel; a de
exibição (`/show/`) entrega o arquivo. Sem o `gtk-update-icon-cache` o ícone novo não aparece:
o índice pronto do tema continua mais novo que a pasta e o Qt não relê o diretório.

**Home já em uso.** Os passos acima assumem pastas vazias. Com conteúdo, mova antes de trocar o
`user-dirs.dirs`: apontar primeiro deixa o sistema olhando para pastas vazias e some com o acesso
ao que já existe.

Comece conferindo para onde cada pasta aponta hoje, com o disco montado:

```bash
findmnt ~/HD
for k in DESKTOP DOWNLOAD DOCUMENTS PICTURES VIDEOS MUSIC TEMPLATES PUBLICSHARE; do
  printf '%-12s %s\n' "$k" "$(xdg-user-dir $k)"
done
```

Nenhuma linha pode responder exatamente `$HOME`. Quando responde, a variável está vazia — e a
home inteira viraria origem da cópia do passo seguinte. Corrija o `user-dirs.dirs` antes de
prosseguir.

O `--ignore-existing` preserva o que já estiver no destino e o `--remove-source-files` esvazia a
origem conforme copia, de modo que o comando pode ser repetido sem duplicar nada:

```bash
mkdir -p ~/HD/{Desktop,Documents,Downloads,Music,Pictures,Projects,Public,Templates,Videos}
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir DESKTOP)/"     ~/HD/Desktop/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir DOWNLOAD)/"    ~/HD/Downloads/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir DOCUMENTS)/"   ~/HD/Documents/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir PICTURES)/"    ~/HD/Pictures/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir VIDEOS)/"      ~/HD/Videos/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir MUSIC)/"       ~/HD/Music/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir TEMPLATES)/"   ~/HD/Templates/
rsync -a --ignore-existing --remove-source-files "$(xdg-user-dir PUBLICSHARE)/" ~/HD/Public/
rsync -a --ignore-existing --remove-source-files ~/Projetos/                    ~/HD/Projects/
```

`Projetos` vai pelo nome porque, ao contrário das outras oito, o Dolphin não a cria — pode
simplesmente não existir ainda. Se não existir, o `rsync` reclama e o resto segue.

O que sobrou tem nome igual a um arquivo que já estava no destino — nada foi sobrescrito, e essas
colisões continuam na home para você resolver a mão. Rode **antes** de criar os links, porque é o
`user-dirs.dirs` de agora que ainda aponta para as pastas antigas; depois dos links o laço passa a
olhar para o destino e conta como colisão tudo o que acabou de ser movido:

```bash
for k in DESKTOP DOWNLOAD DOCUMENTS PICTURES VIDEOS MUSIC TEMPLATES PUBLICSHARE; do
  d=$(xdg-user-dir $k)
  n=$(find "$d" -type f 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && printf '%s: %s arquivo(s) não movido(s)\n' "$d" "$n"
done
find ~/"Área de trabalho" ~/Documentos ~/Downloads ~/Imagens ~/Modelos ~/"Músicas" ~/Projetos ~/"Público" ~/"Vídeos" -type d -empty -delete 2>/dev/null
```

Resolvidas as colisões, guarde cópia dos dois arquivos que serão reescritos e siga o bloco acima
a partir do `rmdir`, que agora encontra as pastas de origem vazias.

```bash
cp -a ~/.config/user-dirs.dirs ~/.config/user-dirs.dirs.bak
cp -a ~/.local/share/user-places.xbel ~/.local/share/user-places-pre-HD.xbel
```

Encerre a sessão e entre de novo. Conferir:

```bash
xdg-user-dir DOWNLOAD
grep -o 'file:///home/[^"]*' ~/.local/share/user-places.xbel
```

Depois, varra o que gravou o caminho antigo do disco (`/run/media/...`): Steam, libvirt, Zed,
documentos recentes.

```bash
grep -rl "/run/media/$USER" ~/.config ~/.local/share 2>/dev/null
```

Pela interface: pasta do Spectacle e do Elisa. Arquivos apagados de dentro do HD vão para
`~/HD/.Trash-$(id -u)`, que o KDE não esvazia — confira com `du -sh`.

**Jogos.** Uma pasta no disco para eles, com o link de sempre na home:

```bash
mkdir -p ~/HD/Games
rmdir ~/Jogos 2>/dev/null
ln -s HD/Games ~/Jogos
```

O `rmdir` é o mesmo cuidado do bloco das pastas: com `~/Jogos` já existindo, o `ln -s` criaria o
link *dentro* dela e sairia com sucesso, deixando um link pendurado e a biblioteca no SSD.

No Steam, **Configurações → Downloads → Pastas da biblioteca**: adicione `~/Jogos` e marque como
padrão pelo botão direito. Ele cria `SteamLibrary` lá dentro — esse nome é dele, não se troca.

Faça isso **antes de instalar qualquer jogo**: assim nada vai parar no SSD e não há o que mover
depois. Jogo já instalado só muda de lugar por **Propriedades → Arquivos instalados → Mover pasta
de instalação**, nunca movendo a pasta à mão.

**Windows na mesma máquina** — montar o disco dele somente-leitura e devolver o carregador a
partir dele:

```bash
sudo ln -s /dev/null /etc/modprobe.d/60-blacklist_fs-ntfs3.conf
WIN=/dev/sdXN
sudo mkdir -p ~/Windows
echo "UUID=$(sudo blkid -s UUID -o value $WIN)  $HOME/Windows  ntfs3  ro,uid=$(id -u),gid=$(id -g),umask=022,noatime,nofail,x-systemd.automount,x-systemd.idle-timeout=300  0  0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount ~/Windows
ls ~/Windows

sudo cp -a ~/Windows/EFI/Microsoft /boot/efi/EFI/Microsoft && sudo bootctl update
```

O carregador vem da própria partição do Windows, que guarda uma cópia da árvore da ESP em
`EFI/Microsoft/Boot/` — `bootmgfw.efi` e o BCD juntos. Por isso a montagem vem antes, e por isso
não é preciso ter feito backup antes de formatar ⚠️ não testado aqui. Se essa pasta não existir na
sua instalação, o carregador sozinho fica em `Windows/Boot/EFI/bootmgfw.efi`, mas sem o BCD ele
não basta: aí o caminho é a recuperação do próprio Windows (`bcdboot C:\Windows /s S:`).

`WIN` é a partição grande, não a "Microsoft reserved". Se o `lsblk -f` mostrar `BitLocker` no
lugar de `ntfs`, o disco está cifrado e não monta: desligue ou suspenda o BitLocker pelo Windows.

Com dual boot, acerte também o relógio — os dois sistemas leem o relógio de hardware de formas
diferentes e a hora fica errada em um deles a cada troca:

```bash
timedatectl                      # "RTC in local TZ: yes" é o problema
sudo timedatectl set-local-rtc 0
```

O Linux passa a usar UTC, que é o certo; do lado do Windows, crie o DWORD `RealTimeIsUniversal`
com valor 1 em `HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation`. A
receita inversa — pôr o Linux em hora local — funciona, mas o systemd a desaconselha: quebra no
horário de verão e no boot antes de a base de fusos carregar.

O openSUSE vem com o `ntfs3` na lista negra (`/usr/lib/modprobe.d/60-blacklist_fs-ntfs3.conf`,
"isn't actively supported by SUSE"); o desbloqueio automático só funciona em terminal
interativo, então sem o `ln -s` acima a montagem falha com *tipo de sistema de arquivos
desconhecido*. O mesmo efeito, de forma interativa: `sudo modprobe ntfs3` e responder `y`.
Alternativa: usar `ntfs-3g` no lugar de `ntfs3` no `fstab` — é FUSE, mais lento, e não passa
pela lista negra.

`ro` fica: com Fast Startup ligado o Windows descarta o que o Linux gravar no NTFS. Só passe
para `rw` depois de desligar o Fast Startup.

**Rótulos dos discos** — o nome que aparece no Dolphin e no gerenciador de partições. Nada aqui é
obrigatório, e como o `fstab` usa `UUID=`, trocar rótulo não afeta montagem nem boot.

```bash
sudo btrfs filesystem label / Sistema
sudo btrfs filesystem label ~/HD Dados
sudo umount ~/Windows
sudo sfdisk --part-label /dev/sdX N Windows
sudo udevadm trigger --settle --subsystem-match=block
```

O btrfs troca o rótulo com o sistema de arquivos montado, e o comando **não responde nada quando
dá certo** — silêncio é sucesso. Mas o `lsblk` e o KDE leem do cache do udev, que não re-sonda
sozinho um dispositivo em uso: sem o `udevadm trigger` acima, ou um reboot, o valor antigo
continua na tela e parece que o comando falhou.

No Windows a troca é no **nome da partição no GPT** (`/dev/sdX` e `N` são o disco e o número do
`WIN` de cima), não no NTFS. Aquela partição costuma vir sem rótulo de sistema de arquivos e com o
nome GPT `Basic data partition`, que é justamente o que os gerenciadores exibem. Mexer só no GPT
não escreve byte nenhum no NTFS — o que importa com Fast Startup ligado — e o tipo da partição não
muda, então o boot do Windows não é afetado. O `ntfslabel` faria o mesmo gravando dentro do NTFS,
com a partição desmontada; evite pelo mesmo motivo do `ro`.

---

## 5. Verificação

```bash
df -h /boot/efi
ls -lh /boot/initrd-*
rpm -qa kernel-default | wc -l
bootctl status
lsmod | grep nvidia && nvidia-smi
rpm -q --qf '%{VENDOR} %{NAME}\n' Mesa
grep -r . /sys/devices/system/cpu/vulnerabilities/ | grep -i "no microcode"
xdg-user-dir DOWNLOAD
findmnt ~/HD
ls ~/Windows
snapper list
timedatectl
sudo firewall-cmd --state && firewall-cmd --list-services
```

ESP abaixo de 50 %; initrd ~130-140 MB com NVIDIA, < 80 MB sem; até 3 kernels; Mesa
`openSUSE`; nenhum "no microcode"; Downloads em `~/Downloads`, apontando para o disco;
`RTC in local TZ: no`.

O `firewalld` vem ativo da instalação, com a interface de rede na zona `public`: tudo que entra é
bloqueado, o que sai é livre. O KDE Connect se libera sozinho ao ser instalado; o resto é manual.

```bash
firewall-cmd --list-all                                          # o que está aberto hoje
sudo firewall-cmd --permanent --add-service=ssh                  # se for usar SSH
sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp   # LocalSend
sudo firewall-cmd --reload
```

O LocalSend não tem serviço pronto no firewalld e não recebe arquivo com a porta fechada —
enviar funciona, receber não, sem erro que explique. Para alcançar esta máquina pela VPN,
`sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0` (§3.4).

---

## 6. Manutenção

```bash
sudo zypper dup
df -h /boot/efi
snapper list
```

Sempre `dup`, nunca `update` — no Tumbleweed e no Slowroll. Uma ou duas vezes por semana basta;
meses sem atualizar pedem alguns ciclos de `dup` seguidos.

O tamanho que o `flatpak list` mostra é o custo isolado de cada item, não o que se recupera ao
removê-lo: as runtimes compartilham objetos por hardlink, e apagar uma cuja irmã continua
instalada libera uma fração do número anunciado.

| Ação | Comando |
|---|---|
| Atualizar o sistema | `sudo zypper dup` |
| Ver o que mudaria antes | `zypper dup --dry-run` |
| Procurar pacote | `zypper se <nome>` |
| Listar o que está instalado | `zypper se -i` |
| Origem e versão de um pacote | `rpm -q --qf '%{VENDOR} %{VERSION}\n' <nome>` |
| Instalar um padrão | `sudo zypper in -t pattern <nome>` · `zypper se -t pattern` lista |
| Travar versão de um pacote | `sudo zypper addlock <nome>` · `removelock` desfaz |
| Liberar cache de download | `sudo zypper clean` |
| Atualizar Flatpaks | `flatpak update --user` |
| Recolher runtimes órfãs | `flatpak uninstall --unused` |
| Ver snapshots e o que cada um ocupa | `sudo snapper list` · `sudo btrfs qgroup show -p --sort=excl /` |

Os snapshots se limitam sozinhos, em três frentes: por **quantidade** (`NUMBER_LIMIT="2-10"`,
com `NUMBER_MIN_AGE=3600` protegendo a última hora), por **espaço** (`SPACE_LIMIT="0.5"` e
`FREE_LIMIT="0.2"` — no máximo metade do sistema de arquivos, e ao menos 20 % do disco livre) e
por **tempo**, que na raiz vem desligado (`TIMELINE_CREATE="no"`: só existem os pares pre/post do
`zypper`). Quem executa é o `snapper-cleanup.timer`, de hora em hora. A coluna `excl` do
`qgroup show` é o que cada snapshot ocupa sozinho — o que se recupera de fato ao apagá-lo.

---

## 7. Recuperação

→ **[solução de problemas](troubleshooting.pt-BR.md)**, por sintoma.

---

## Fontes

[Tumbleweed installation](https://en.opensuse.org/openSUSE:Tumbleweed_installation) · [SDB:NVIDIA drivers](https://en.opensuse.org/SDB:NVIDIA_drivers) · [SDB:Packman codecs](https://en.opensuse.org/SDB:Installing_codecs_from_Packman_repositories) · [doc.opensuse.org](https://doc.opensuse.org/documentation/tumbleweed/)
