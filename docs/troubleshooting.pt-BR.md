# Solução de problemas

[English](troubleshooting.md) · **Português**

Por sintoma. Instalação e configuração ficam no
[guia de instalação](installation-guide.pt-BR.md).

| Sintoma | Seção |
|---|---|
| Não boota, ou boota em modo de emergência | [Recuperar por snapshot](#recuperar-por-snapshot) |
| `initrd` com poucos KB, ESP cheia | [Kernel truncado](#kernel-truncado-por-falta-de-espaço) |
| Fundo preto, sem ícones e sem "Iniciar" | [Área de trabalho sem painel](#área-de-trabalho-sem-painel) |
| Windows não aparece no menu de boot | [Windows sumiu do menu](#windows-sumiu-do-menu) |
| `mkdir ~/HD` dá "permissão negada" | [Disco de dados não montou](#disco-de-dados-não-montou) |
| Atalhos da barra lateral do Dolphin não abrem | [Locais do Dolphin](#locais-do-dolphin) |
| `ls ~/Windows` dá "Dispositivo inexistente" | [Disco do Windows não monta](#disco-do-windows-não-monta) |
| "Sem espaço" com o disco aparentemente livre | [Btrfs cheio de snapshot](#btrfs-cheio-de-snapshot) |
| `zypper dup` para pedindo para escolher uma solução | [Conflito no dup](#conflito-no-dup) |
| Pede a senha da carteira do KDE ao entrar na sessão | [Carteira do KDE trancada](#carteira-do-kde-trancada) |
| `zypper dup` aborta com "Destino vazio no URI" | [Repositório da mídia](#repositório-da-mídia-de-instalação) |
| Sem GPU depois de um `dup` com kernel novo | [Kernel sem driver NVIDIA](#kernel-sem-driver-nvidia) |
| Sessão abre em 640x480 e só oferece essa resolução | [Monitor sem EDID](#monitor-sem-edid) |
| Aviso de atualização insiste depois do `dup` | [Notificador com número velho](#notificador-com-número-velho) |

---

## Recuperar por snapshot

`snapper rollback` não funciona com systemd-boot: aponta o padrão para um snapshot
somente-leitura e o boot cai em emergência.

1. No menu do systemd-boot, escolha uma entrada `Snapper:` recente.
   Nunca a "after installation": contém `/etc/selinux/.autorelabel` e não boota.
2. O sistema sobe somente-leitura. Rede e SSH funcionam.
3. Tornar gravável e permanente:

```bash
findmnt -no SOURCE /
sudo btrfs property set -f /.snapshots/<N>/snapshot ro false
sudo mount -o remount,rw /
sudo btrfs subvolume list / | grep "snapshots/<N>/snapshot"
sudo btrfs subvolume set-default <ID> /
sudo reboot
```

Escolher um snapshot no menu não muda o padrão: sem o `set-default`, o próximo boot volta ao
subvolume anterior. Confira que os dois batem:

```bash
findmnt -no SOURCE /
sudo btrfs subvolume get-default /
```

`@/.snapshots/1/snapshot` é a raiz normal do openSUSE, não um rollback. Achar snapshots que não
bootam, com o sistema saudável:

```bash
for n in $(ls /.snapshots | sort -n); do [ -e "/.snapshots/$n/snapshot/etc/selinux/.autorelabel" ] && echo "snapshot $n NÃO BOOTA"; done
```

---

## Kernel truncado por falta de espaço

```bash
df -h /boot/efi
find /boot/efi -name 'initrd*' -printf '%s\t%p\n' | sort -n
sudo sdbootutil mkinitrd
```

Arquivos de kernel já desinstalado ficam presos por snapshots:

```bash
sudo snapper delete <N> <N>
sudo sdbootutil cleanup
```

O `snapper-cleanup.timer` faz isso de hora em hora.

---

## Área de trabalho sem painel

A sessão entra e as janelas funcionam, mas o fundo fica preto, sem ícones nem barra. Não é
driver de vídeo: é tema Breeze sem o pacote de papel de parede.

```bash
cat ~/.config/kdedefaults/package
ls -d /usr/share/wallpapers/Next
sudo zypper install breeze6-wallpapers
```

Depois encerre a sessão e entre de novo. Sem painel: Ctrl+Alt+Del ou
`qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout`.

A quebra aparece só no login seguinte à troca de tema — parece culpa de outra mudança.

Não reinicie o `plasmashell` por systemd nesse estado: derruba portal, `kded6` e `kioworker`
em cascata até a tela ficar preta de verdade.

`Atomic modeset commit failed!` no log do `kwin_wayland` é ruído com NVIDIA. Confirme com
`qdbus6 org.kde.KWin /KWin supportInformation | grep "Compositing is"`.

---

## Windows sumiu do menu

Se `EFI/Microsoft` sumiu da ESP, devolva a partir da própria partição do Windows, que guarda uma
cópia da árvore em `EFI/Microsoft/Boot/` — `bootmgfw.efi` e o BCD juntos. Exige `~/Windows`
montado (§4 do guia) ⚠️ não testado aqui:

```bash
sudo ls /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi
ls ~/Windows/EFI/Microsoft/Boot/bootmgfw.efi
sudo cp -a ~/Windows/EFI/Microsoft /boot/efi/EFI/Microsoft
sudo bootctl update
```

Sem essa pasta na partição, o carregador sozinho está em `~/Windows/Windows/Boot/EFI/bootmgfw.efi`,
mas sem o BCD não basta — aí o caminho é a recuperação do próprio Windows.

`bootctl list` não mostra o Windows mesmo com tudo certo: só lista entradas BLS. A
conferência real é reiniciar e olhar o menu. Enquanto isso, o menu de boot da BIOS serve.

---

## Disco de dados não montou

`~/HD` continua a pasta vazia `root:root` do SSD; o `nofail` escondeu o erro. Causa quase
certa: UUID errado no `fstab`. Como os links da home apontam para dentro dele, o sintoma costuma
aparecer antes como `~/Documentos` quebrado, ou como programa que não consegue salvar.

```bash
findmnt ~/HD
grep HD /etc/fstab
lsblk -f
```

Feche o Dolphin e o editor antes (senão "target is busy"):

```bash
DISCO=/dev/sdXN
sudo sed -i "s|^UUID=.*$HOME/HD|UUID=$(lsblk -no UUID $DISCO)  $HOME/HD|" /etc/fstab
udisksctl unmount -b $DISCO
sudo systemctl daemon-reload && sudo mount ~/HD
findmnt ~/HD && ls -ld ~/HD
```

Com a montagem de pé, refaça o `user-dirs.dirs` do §4 do guia: o `xdg-user-dirs-update` já
devolveu tudo para `$HOME`.

---

## Locais do Dolphin

Depois do §4 do guia, os atalhos da barra lateral (Documentos, Downloads, Imagens…) não abrem.
Eles guardam caminho absoluto em `~/.local/share/user-places.xbel` e não acompanham o
`user-dirs.dirs`; são itens de sistema, editar um a um não resolve.

Feche todas as janelas do Dolphin antes — aberto, ele regrava os caminhos velhos.

```bash
cp -a ~/.local/share/user-places.xbel ~/.local/share/user-places-pre-HD.xbel
rm ~/.local/share/user-places.xbel
```

Abra o Dolphin. Conferir:

```bash
grep -o 'file:///home/[^"]*' ~/.local/share/user-places.xbel
```

Atalhos criados por você se perdem; refaça arrastando a pasta para a barra.

O `user-places.xbel.bak` ao lado é reescrito pelo próprio KDE a cada gravação — não serve de
cópia de segurança.

---

## Repositório da mídia de instalação

O instalador se registra como repositório apontando para o DVD ou pendrive. Sem a mídia
conectada o `ref` falha nele e o `dup` aborta sem alterar nada.

```bash
zypper lr -u
sudo zypper rr <alias com URI hd:/ ou cd:/>
```

---

## Kernel sem driver NVIDIA

Depois de um `dup` que trouxe kernel novo, `nvidia-smi` falha e a sessão abre sem aceleração.
O KMP da NVIDIA atrasa alguns dias em relação ao kernel do Tumbleweed.

No menu do systemd-boot escolha a entrada do kernel anterior (`latest-1` do §2 do guia) e
repita o `dup` daí a alguns dias. O nome do KMP traz a versão do kernel para o qual foi
compilado:

```bash
rpm -qa kernel-default 'nvidia*kmp*'
```

---

## Disco do Windows não monta

`ls ~/Windows` responde "Dispositivo inexistente" e o journal mostra o motivo real:

```bash
sudo journalctl -b -u "$(systemd-escape -p --suffix=mount ~/Windows)" -n 20 --no-pager
```

`tipo de sistema de arquivos desconhecido "ntfs3"` significa que o módulo não carregou: o
openSUSE o mantém na lista negra e o desbloqueio automático só funciona em terminal
interativo — o `mount` disparado pelo systemd nunca cumpre essa condição.

```bash
sudo ln -s /dev/null /etc/modprobe.d/60-blacklist_fs-ntfs3.conf
sudo systemctl reset-failed "$(systemd-escape -p --suffix=mount ~/Windows)"
ls ~/Windows
```

O disco em si não tem culpa: o `lsblk -f` mostra a partição com `ntfs` e o UUID do `fstab`.

---

## Btrfs cheio de snapshot

Sintoma: "sem espaço em disco" com o `df` mostrando espaço livre. O btrfs conta os snapshots,
o `df` não.

```bash
sudo btrfs filesystem usage /
snapper list
sudo snapper delete 100-140          # intervalo de snapshots antigos
```

Se nem apagar snapshot resolver, o espaço está preso em blocos meio usados:

```bash
sudo btrfs balance start -dusage=5 /
```

O `snapper-cleanup.timer` faz a limpeza de hora em hora pelo `NUMBER_LIMIT` (padrão `2-10`) —
encher significa que algo criou snapshots mais rápido do que isso, em geral uma sequência de
`zypper dup` grandes. Para a ESP cheia, que é outro problema, veja
[Kernel truncado](#kernel-truncado-por-falta-de-espaço).

---

## Conflito no dup

O `zypper dup` para e apresenta soluções numeradas. Leia antes de escolher: a opção mais
"fácil" costuma ser trocar o fornecedor do pacote para um repositório de terceiro, o que arrasta
a pilha inteira depois.

```bash
zypper dup --dry-run            # veja o estrago antes
zypper lr -u                    # repositório fora do ar ou obsoleto causa conflito
```

Ordem de preferência: manter o fornecedor `openSUSE`; se o conflito for de codec, resolver só o
pacote envolvido com `--from packman-essentials`; desinstalar o pacote problemático; e só então
aceitar troca de fornecedor. Nunca responda "sim" para um `dup` que queira mudar dezenas de
pacotes de vendor — é o cenário do §3.3 do guia.

---

## Carteira do KDE trancada

Ao entrar na sessão aparece *"O aplicativo `xdg-desktop-portal` solicitou a abertura da carteira
`kdewallet`"*. Quem pede não é o portal: é algum Flatpak que subiu no autostart e precisa guardar
um segredo — sem acesso direto ao chaveiro, ele passa pelo portal, que no KDE é atendido pelo
`kwalletd6`.

O desbloqueio automático já está configurado (`pam_kwallet5` no `common-auth-pc` e no
`common-session-pc`) e só funciona quando **a senha da carteira é igual à senha de login**. A
caixa aparecer significa que são diferentes.

```bash
kwalletmanager5 &
```

Selecione `kdewallet` → **Abrir...** (senha atual) → o botão **Alterar senha...** habilita → use
a senha do login nos dois campos. Vale a partir do próximo boot. Confira a tentativa do PAM:

```bash
journalctl --user -b | grep -i pam_kwallet
```

Senha vazia também elimina a pergunta, mas deixa a carteira sem cifra no disco — ela guarda
segredos de vários aplicativos. Tirar o aplicativo do autostart só adia a pergunta para a hora
em que você o abrir.

---

## Monitor sem EDID

Só com placa NVIDIA e monitor no DisplayPort.

A sessão abre em 640x480 e essa é a única resolução oferecida. Quando o PC boota com o monitor
desligado ou em sono profundo, a leitura do EDID pelo canal AUX do DisplayPort falha e o driver
fabrica um EDID sintético, de um modo só.

```bash
kscreen-doctor -o | grep Modes
grep -o '"edidIdentifier": "[^"]*"' ~/.config/kwinoutputconfig.json
```

`NVD 0 0 0 0 0` é o EDID inventado; o do monitor traz fabricante e ano. Note que
`/sys/class/drm/card*-DP-1/edid` fica com 0 byte mesmo com tudo funcionando — o driver
proprietário não publica o EDID ali, então quem vale é a lista de modos.

Ligue o monitor e desconecte e reconecte o cabo DP: o hotplug re-sonda o link e o KDE volta
sozinho ao perfil salvo. Não há conserto por software — com um modo só na lista, o
`kscreen-doctor` não tem para onde mudar.

Para não repetir, ligue o monitor antes do PC, ou passe para DVI-D ou HDMI, onde o EDID vai por
DDC/I²C alimentado pelos +5 V da própria placa e é lido com o monitor dormindo ⚠️ não testado
aqui. Forçar por `drm.edid_firmware` não resolve: o driver proprietário não busca EDID pelo
caminho dos helpers do DRM.

Cada ocorrência deixa um perfil a mais em `~/.config/kwinoutputconfig.json`, inofensivo. Apagar
não previne nada: os 640x480 vêm do driver, não do perfil.

`Atomic modeset commit failed!` no log aparece nos dois casos e não ajuda a distinguir, veja
[Área de trabalho sem painel](#área-de-trabalho-sem-painel).

---

## Notificador com número velho

O aviso continua marcando pacotes pendentes depois de um `sudo zypper dup` feito na mão. O
número não é medido na hora: o `dup-notify` e o aviso do terminal apenas leem
`/var/lib/dup-count`, gravado pelo `dup-check.timer`, que roda uma vez por dia.

```bash
cat /var/lib/dup-count
stat -c '%y' /var/lib/dup-count
systemctl list-timers dup-check.timer
```

Contador com data anterior à do último `dup` é o caso. Confirme que não há nada pendente de
verdade:

```bash
zypper --no-refresh lu
flatpak remote-ls --updates
zypper --no-refresh se -s openSUSE-release
```

`i+` na linha do `openSUSE-release` significa que o repositório está no mesmo snapshot já
instalado. Para acertar o número agora:

```bash
sudo /usr/local/bin/dup-check
```

A notificação que já está na tela não expira sozinha, por opção do script: feche na central de
notificações do Plasma.

O `install-dup-notifier.sh` desta pasta já traz a correção permanente — o `dup-check.path`
recalcula depois de cada transação rpm, e os dois leitores ficam calados quando o rpmdb está
mais novo que o contador. Reinstale com `sudo ./scripts/install-dup-notifier.sh`.

