# Vídeo — DaVinci Resolve e conversão

[English](video-davinci.md) · **Português**

Requer os codecs do Packman (§3.3 do guia) e GPU NVIDIA com driver proprietário.

## 1. DaVinci Resolve

```bash
./scripts/install-davinci.sh --check
./scripts/install-davinci.sh
```

O script descobre a versão atual na API da Blackmagic, instala as dependências com os nomes do
Tumbleweed, roda o instalador com `SKIP_PACKAGE_CHECK=1` e move `libgio*`, `libglib*`,
`libgmodule*` e `libgobject*` para `_disabled` — sem isso o Resolve fecha ao abrir. A família
glib vai inteira: deixar uma delas para trás mistura versões e volta a quebrar. Toda atualização
restaura essas bibliotecas; rode o script de novo.

Executável: `/opt/resolve/bin/resolve`. Se não abrir em Wayland: `QT_QPA_PLATFORM=xcb`.

A versão gratuita não importa H.264/H.265 no Linux. Transcodifique antes (§2). O
`ffmpeg_encoder_plugin` não resolve: é só exportação e exige o Studio.

## 2. Menus de conversão no Dolphin

```bash
mkdir -p ~/.local/bin ~/.local/share/kio/servicemenus
cp scripts/convert-video ~/.local/bin/ && chmod +x ~/.local/bin/convert-video
cp scripts/convert-video.desktop ~/.local/share/kio/servicemenus/
chmod +x ~/.local/share/kio/servicemenus/convert-video.desktop
```

Botão direito num vídeo → **Converter vídeo**. O menu segue o idioma da sessão. Abre um Konsole
com o progresso, aceita seleção múltipla e nunca sobrescreve a origem.

| Perfil | Uso | 1080p30 |
|---|---|---|
| DNxHR LB | celular, só corte | 19 GB/h |
| DNxHR SQ | câmera dedicada, edição comum | 61 GB/h |
| DNxHR HQX | 10 bits, colorização pesada, chroma key | 92 GB/h |
| H.264 NVENC | entrega para web | — |
| H.265 NVENC | entrega menor, players modernos | — |

Escolha pela taxa da origem: para vídeo de celular o LB já guarda 4× a informação do
arquivo e perde 0,15 % de SSIM na exportação final; SQ e HQX gastam 13× e 20× por nada. O DNxHR é
intraquadro, por isso o arquivo cresce muito (300 MB de H.264 viram ~13 GB em SQ) — é o que dá
arraste fluido na linha do tempo. Apague o `.mov` depois de exportar.

HQ não está no menu (mesmo tamanho do HQX, 8 bits). ProRes não compensa: mesmo tamanho do SQ e
8× mais lento no ffmpeg.

Na mão:

```bash
ffmpeg -i entrada.mp4 -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p -c:a pcm_s16le -ar 48000 timeline.mov
ffmpeg -i "Timeline 1.mov" -vf format=yuv420p -c:v h264_nvenc -preset p6 -cq 18 -profile:v high -spatial-aq 1 -rc-lookahead 20 -bf 3 -c:a aac -b:a 192k -movflags +faststart saida.mp4
ffmpeg -i "Timeline 1.mov" -vf format=yuv420p -c:v hevc_nvenc -preset p6 -cq 20 -spatial-aq 1 -rc-lookahead 20 -c:a aac -b:a 192k -movflags +faststart -tag:v hvc1 saida.mp4
```

`-profile:v high`, `-spatial-aq 1`, `-rc-lookahead 20` e `-preset p6` melhoram sobre os padrões
do NVENC sem custo de tempo; `p7` não compensa. `-tag:v hvc1` é para players Apple.

`-bf` só no H.264: GPUs Pascal e anteriores não fazem quadros B em HEVC e o ffmpeg aborta com
`No capable devices found`. Turing em diante aceita.
