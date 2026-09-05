# openSUSE KDE Setup

[English](README.md) · **Português**

Documentação e scripts que levam uma máquina do disco vazio a uma área de trabalho
**openSUSE Tumbleweed ou Slowroll** funcionando, com **KDE Plasma**, systemd-boot e snapshots
btrfs.

Escrito para qualquer máquina, não para uma montagem específica: o que depende de hardware
(NVIDIA, WiFi, dual boot com Windows, um segundo disco para dados) vai marcado no lugar.

Todo documento existe nos dois idiomas, com link de troca no topo.

## Documentação

| Documento | O que cobre |
|---|---|
| [Guia de instalação](docs/installation-guide.pt-BR.md) | particionamento, rede de segurança do kernel, repositórios, drivers, codecs, aplicativos, disco de dados |
| [Solução de problemas](docs/troubleshooting.pt-BR.md) | por sintoma, para quando algo quebra |
| [SSH e git](docs/ssh-and-git.pt-BR.md) | chaves SSH guardadas no cofre do Bitwarden, sem chave privada no disco |
| [Vídeo e DaVinci Resolve](docs/video-davinci.pt-BR.md) | instalação do Resolve, menus de conversão de vídeo no Dolphin |

## Scripts

Rode a partir da raiz do repositório — é o que o `./` significa nos documentos.

| Script | O que faz |
|---|---|
| `scripts/install-dup-notifier.sh` | aviso de atualizações do `zypper` e do Flatpak, sem PackageKit |
| `scripts/install-davinci.sh` | baixa, instala e corrige o DaVinci Resolve |
| `scripts/convert-video` + `.desktop` | menus de conversão de vídeo no Dolphin |

## Ordem

1. **Instalação** — guia §1. Particionador avançado, ESP de 2 GiB, btrfs com snapshots,
   systemd-boot.
2. **Rede de segurança do kernel** — guia §2, antes do primeiro `zypper dup`. Mantém o kernel
   anterior bootável (`latest-1`) e gera um initrd enxuto.
3. **Sistema e programas** — guia §3. `sudo zypper ref && sudo zypper dup && sudo reboot`, depois
   driver, codecs pelo Packman Essentials, aplicativos e `sudo ./scripts/install-dup-notifier.sh`.
4. **Disco de dados** — guia §4. Montagem, pastas XDG, Baloo, partição do Windows.
5. **Extras** — SSH e git, vídeo e DaVinci Resolve.
6. **Conferência** — guia §5.

Quebrou → [solução de problemas](docs/troubleshooting.pt-BR.md).

## Escopo

Só rolling release. Tumbleweed e Slowroll são cobertos juntos, e a diferença entre eles vai
indicada no lugar, não em seção à parte. Sempre `zypper dup`, nunca `zypper update`.

Codecs vêm do Packman **Essentials**, não de vendor-change completo. Fora do escopo: Android,
câmera do emulador e máquinas virtuais.

## Licença

[MIT](LICENSE).
