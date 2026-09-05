# Video — DaVinci Resolve and conversion

**English** · [Português](video-davinci.pt-BR.md)

Requires the Packman codecs (guide §3.3) and an NVIDIA GPU with the proprietary driver.

## 1. DaVinci Resolve

```bash
./scripts/install-davinci.sh --check
./scripts/install-davinci.sh
```

The script finds the current version through Blackmagic's API, installs the dependencies under
their Tumbleweed names, runs the installer with `SKIP_PACKAGE_CHECK=1` and moves `libgio*`,
`libglib*`, `libgmodule*` and `libgobject*` into `_disabled` — without that, Resolve closes as it
opens. The whole glib family goes: leaving one of them behind mixes versions and breaks it again.
Every update restores those libraries; run the script again.

Executable: `/opt/resolve/bin/resolve`. If it does not open under Wayland:
`QT_QPA_PLATFORM=xcb`.

The free version does not import H.264/H.265 on Linux. Transcode first (§2).
`ffmpeg_encoder_plugin` is not a way around it: it only covers export and requires Studio.

## 2. Conversion menus in Dolphin

```bash
mkdir -p ~/.local/bin ~/.local/share/kio/servicemenus
cp scripts/convert-video ~/.local/bin/ && chmod +x ~/.local/bin/convert-video
cp scripts/convert-video.desktop ~/.local/share/kio/servicemenus/
chmod +x ~/.local/share/kio/servicemenus/convert-video.desktop
```

Right-click a video → **Convert video**. The menu follows the session language. It opens a
Konsole window with the progress, accepts multiple selection and never overwrites the source.

| Profile | Use | 1080p30 |
|---|---|---|
| DNxHR LB | phone footage, cuts only | 19 GB/h |
| DNxHR SQ | dedicated camera, ordinary editing | 61 GB/h |
| DNxHR HQX | 10-bit, heavy grading, chroma key | 92 GB/h |
| H.264 NVENC | web delivery | — |
| H.265 NVENC | smaller delivery, modern players | — |

Choose by the bitrate of the source: for phone video, LB already holds 4× the information in the
file and loses 0.15 % SSIM in the final export; SQ and HQX spend 13× and 20× for nothing. DNxHR
is intra-frame, which is why the file grows so much (300 MB of H.264 becomes ~13 GB in SQ) — that
is what makes the timeline scrub smoothly. Delete the `.mov` once you have exported.

HQ is not in the menu (same size as HQX, 8-bit). ProRes is not worth it: same size as SQ and 8×
slower in ffmpeg.

By hand:

```bash
ffmpeg -i entrada.mp4 -c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p -c:a pcm_s16le -ar 48000 timeline.mov
ffmpeg -i "Timeline 1.mov" -vf format=yuv420p -c:v h264_nvenc -preset p6 -cq 18 -profile:v high -spatial-aq 1 -rc-lookahead 20 -bf 3 -c:a aac -b:a 192k -movflags +faststart saida.mp4
ffmpeg -i "Timeline 1.mov" -vf format=yuv420p -c:v hevc_nvenc -preset p6 -cq 20 -spatial-aq 1 -rc-lookahead 20 -c:a aac -b:a 192k -movflags +faststart -tag:v hvc1 saida.mp4
```

`-profile:v high`, `-spatial-aq 1`, `-rc-lookahead 20` and `-preset p6` improve on the NVENC
defaults at no cost in time; `p7` is not worth it. `-tag:v hvc1` is for Apple players.

`-bf` on H.264 only: Pascal and older GPUs do not do B-frames in HEVC and ffmpeg aborts with
`No capable devices found`. Turing onwards accepts it.
