# openSUSE Tumbleweed and Slowroll — Installation

**English** · [Português](installation-guide.pt-BR.md)

KDE Plasma · systemd-boot · btrfs with snapshots. Good for any machine and for both variants;
whatever depends on hardware is marked (NVIDIA, WiFi, Windows, data disk) and whatever changes on
Slowroll is noted in place.

---

## 1. Installer

Screen frozen at startup: press `E` at the menu, add `nomodeset` after `splash=silent`, then
`F10`.

### Partitioning

**Expert Partitioner → Start with Existing Partitions.** The guided proposal creates a 1 GB ESP;
with systemd-boot the kernel and initrd live on the ESP and it fills up.

| Partition | Size | Role |
|---|---|---|
| ESP | **2 GiB** | EFI Boot Partition |
| root | the rest | Operating System → Btrfs on `/`, ☑ **Enable Snapshots** |
| swap | 2 GiB | Swap |

Check the `@/home`, `@/opt`, `@/root`, `@/srv`, `@/usr/local` and `@/var` subvolumes on the root
partition — without them snapper does not work. Do not touch the other disks.

Ticking **Enable Snapshots** does more than turn snapper on: the installer changes four values in
`/etc/snapper/configs/root` relative to the package's template — it creates the btrfs quota
(`QGROUP="1/0"`), tightens `NUMBER_LIMIT` from 50 to `2-10` and `NUMBER_LIMIT_IMPORTANT` from 10
to `4-10`, and turns `TIMELINE_CREATE` off. It is the quota that gives `SPACE_LIMIT="0.5"` and
`FREE_LIMIT="0.2"` any force, which is what keeps root from filling up with snapshots. Creating
the configuration by hand afterwards (`snapper -c root create-config /`) leaves you with the raw
template, with no quota.

### Other options

| | |
|---|---|
| Bootloader | **Systemd Boot** |
| Secure Boot | see §3.2 |
| SELinux | `enforcing` |
| SSH | enable the service **and** open the port, if you will use it |
| User | untick "use this password for the system administrator" |
| Online repositories | skip |

---

## 2. Before the first `zypper dup`

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

If `zypp.conf` already exists, insert the lines inside `[main]` — without the header libzypp
ignores the file. Always `sdbootutil mkinitrd`, never `dracut -f`: dracut does not copy the initrd
to the ESP. `latest-1` lets you boot the previous kernel if the NVIDIA driver falls behind.
Changing motherboard may call for `dracut -f --no-hostonly` once.

---

## 3. Repositories and drivers

```bash
echo 'export ZYPP_MEDIANETWORK=1' >> ~/.bashrc
export ZYPP_MEDIANETWORK=1
echo 'Defaults env_keep += "ZYPP_MEDIANETWORK"' | sudo tee /etc/sudoers.d/zypp-medianetwork
zypper lr -u
sudo zypper rr <alias-of-the-hd:/-or-cd:/-repo>
sudo zypper ref && sudo zypper dup && sudo reboot
```

The `rr` removes the installation media repository (`hd:/` or `cd:/` URI); with it in place, `dup`
aborts unless the media is connected.

### 3.1 NVIDIA

*Only with an NVIDIA GPU.* Find the chip:

```bash
lspci -nn | grep -i vga
# 01:00.0 VGA ... NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82]
```

The codename prefix (`GP107` → `GP`) sets the architecture, and the architecture sets the driver:

| Architecture | Codename | Driver |
|---|---|---|
| Turing to Blackwell | `TU` `GA` `AD` `GH` `GB` | `nvidia-open-driver-G07-signed-kmp-meta` — open and signed |
| Maxwell, Pascal, Volta | `GM` `GP` `GV` | `nvidia-driver-G06-kmp-meta` — proprietary |
| Kepler | `GK` | `x11-video-nvidiaG05 nvidia-glG05 nvidia-computeG05` — legacy |
| Fermi and older | `GF` `NV` `G8` `GT2` | do not work with kernel 6.6+ — use `nouveau` |

The open module requires Turing or newer; the proprietary G06 is the only one that serves
Maxwell, Pascal and Volta. Turing onwards can use either, but the signed open one spares you the
MOK ritual with Secure Boot on (§3.2) — and it is what NVIDIA recommends. If you need the open one
on the 580 series instead of 595, there is `nvidia-open-driver-G06-signed-kmp-meta`.

If `lspci` does not give you the codename, the [Wikipedia
list](https://en.wikipedia.org/wiki/List_of_Nvidia_graphics_processing_units) maps every model
(GTX 1050 Ti → GP107 → Pascal → G06).

```bash
sudo zypper install openSUSE-repos-Tumbleweed-NVIDIA
sudo zypper install <package from the table>
```

Slowroll: `openSUSE-repos-Slowroll-NVIDIA`. Both point at the same repository.

Confirm before installing that the proprietary one covers the card — only it declares the PCI IDs,
and the list covers exactly Maxwell, Pascal and Volta:

```bash
ID=$(lspci -nn | grep -i vga | grep -oiE "10de:[0-9a-f]{4}" | cut -d: -f2 | tr a-f A-F)
sudo zypper download nvidia-driver-G06-kmp-default
rpm -qp --supplements /var/cache/zypp/packages/*/*/nvidia-driver-G06-kmp-default-*.rpm | grep -i "d0000$ID" && echo SUPPORTED
```

No result means the card is Turing or newer: go with the signed open one. The open packages do not
declare IDs, so for them the table is what counts.

With the driver installed the initrd jumps to ~130-140 MB, against under 80 MB without it:
`kernel-firmware-nvidia` carries the firmware for every generation and dracut copies the whole
package, even with `hostonly` (§2). There is no option that filters by model — it is the reason
for the 2 GiB ESP in §1, and not worth trying to trim.

### 3.2 Secure Boot

Signed open driver (Turing onwards): can stay on. Proprietary G06 driver or older: turn it off, or
accept the MOK on every update — at the first reboot `mokutil` opens: **Enroll MOK → Continue →
Yes → root password (US keyboard)**. No NVIDIA: on.

### 3.3 Codecs

```bash
sudo zypper addrepo -cfp 90 'https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/Essentials/' packman-essentials
sudo zypper refresh
sudo zypper install --allow-vendor-change --from packman-essentials ffmpeg gstreamer-plugins-{good,bad,ugly,libav} libavcodec vlc-codecs
```

Slowroll: `openSUSE_Slowroll` in place of `openSUSE_Tumbleweed` in the URL.

To check:

```bash
rpm -q --qf '%{VENDOR} %{NAME}\n' Mesa Mesa-dri libgbm1
rpm -q --qf '%{VENDOR} %{NAME}\n' ffmpeg vlc-codecs
sudo zypper dup --dry-run
```

Mesa is `openSUSE`, ffmpeg and vlc-codecs are `packman`, and `dup` says "Nothing to do".
`gstreamer-plugins-libav` stays `openSUSE` even when everything is right.

Never `zypper dup --from packman --allow-vendor-change`: it swaps the entire graphics stack.
Packman versions ffmpeg (`ffmpeg-8`, `ffmpeg-9`…); always check by the package without a suffix.

### 3.4 Applications

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

- `git-core` is the complete Git; `git` is just a meta package that drags in Perl.
- PackageKit locks `zypper` and applies `update` semantics. Discover is left for Flatpak and
  firmware. Do not use `zypper install-new-recommends`: it reinstalls the two packages just
  removed.
- Flatpak always `--user`, including on `remote-add` — without `--user` there, the remote lands in
  the system scope only and `install --user` answers *no remote refs found*. Do not install
  through Discover, which uses `--system` and duplicates the application.
- Krita and Foliate come from `zypper`, not Flathub — same version either way. Krita is Qt: the
  native build reuses the Qt and the theme already installed, the KIO dialogs and
  `krita-plugin-gmic`, which does not exist in the Flatpak, and the Flatpak still takes 634 MB
  with `filesystems=host` (no sandbox at all, in practice). Foliate tends to be the only
  application pinned to an old version of `org.gnome.Platform`, and each version of that runtime
  costs 1.1 GB.
- LocalSend needs port 53317 open in the firewall (§5) in order to **receive**; without it,
  sending works and receiving does not, with no error to explain why.
- Melia and NAPS2 are not on Flathub ([melia](https://melia.buxjr.com) ·
  [naps2](https://www.naps2.com/download)); they get no `flatpak update`. Keep the files.
- Zed lives in `~/.local/zed.app`, outside `zypper` and `flatpak`; it updates itself.
- Containers do not come with the installation. The `container_runtime_podman` pattern brings
  `podman` along with `buildah` (building an image step by step, without a `Containerfile`) and
  `skopeo` (inspecting and copying images between registries without downloading or running them).
  To only run and build from a `Containerfile`, `sudo zypper install podman` is enough — it
  already embeds buildah.

Where to install each thing from:

| Source | When | Examples here |
|---|---|---|
| `zypper` (official repos) | anything that exists packaged — integrates with snapshots and `dup` | system, drivers, KDE |
| Packman Essentials | codecs only (§3.3) | `ffmpeg`, `vlc-codecs` |
| Vendor repository | a driver openSUSE does not package | NVIDIA (§3.1) |
| OBS (`network:chromium`) | a package outside the official repos, kept by a third party | Ungoogled Chromium (§3.5) |
| Flatpak `--user` | a graphical application absent from `zypper`, or a newer version | Anytype, KOReader, Bitwarden |
| Its own installer | no package anywhere; updates itself | Zed, Tela icons |

Every row below the first is a deliberate exception: the further down the table, the more
`zypper dup` and snapper stop seeing what you installed.

**Tela icons** — no package; the script installs into `~/.local/share/icons`, without `sudo`:

```bash
git clone --depth 1 https://github.com/vinceliuice/Tela-icon-theme.git ~/HD/Downloads/Tela-icon-theme
~/HD/Downloads/Tela-icon-theme/install.sh green
kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-green-dark
```

One colour takes ~185 MB; `-a` (all of them) goes past 2 GB. Updating is `git pull` and running it
again; removing is `install.sh -r`.

The colour is a positional argument; `-c` is a different option.

### 3.5 Ungoogled Chromium

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/network:chromium/openSUSE_Tumbleweed/network:chromium.repo
sudo zypper modifyrepo -f network_chromium
sudo zypper refresh && sudo zypper install ungoogled-chromium
```

Without `modifyrepo -f` the browser gets no updates. Slowroll: `network:chromium` has no build;
use the `io.github.ungoogled_software.ungoogled_chromium` Flatpak and skip the rest of this
section.

The package reuses Chromium's generic `.desktop` file (wrong name and icon). The fix, with the
Tela theme installed:

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

Only the long-named icon is the Ungoogled one; `ungoogled-chromium.svg` and the
`com.github.Eloston.*` ones are links to the ordinary Chromium logo.

### 3.6 Video and DaVinci Resolve

→ **[video and DaVinci Resolve](video-davinci.md)** · `./scripts/install-davinci.sh`

### 3.7 CPU microcode

```bash
sudo zypper install ucode-intel
sudo sdbootutil mkinitrd && sudo reboot
```

AMD CPU: `ucode-amd`. To check afterwards:

```bash
grep -r . /sys/devices/system/cpu/vulnerabilities/ | grep -i "no microcode"
```

Without the package several mitigations stay off; the output above has to come back empty.

### 3.8 WiFi

*Only with WiFi.*

```bash
sudo zypper install wireless-regdb && sudo reboot
sudo journalctl -k -b | grep -i regulatory
```

Without the package WiFi sits in the "world" regulatory domain, with less range. The log must not
say `failed to load`.

### 3.9 Machine name

```bash
sudo hostnamectl hostname machine-name
grep -q " $(hostname)$" /etc/hosts || echo "127.0.0.1  $(hostname)" | sudo tee -a /etc/hosts
```

With no name set the system stays as `localhost.localdomain` — that is the default when the field
is left blank in the installer. Use lower-case letters, digits and hyphens. The `hostname` verb is
required: `hostnamectl <name>` answers *Unknown command verb*.

The line in `/etc/hosts` is not decoration: openSUSE's `nsswitch.conf` does not carry the
`myhostname` module, so the machine's own name does not resolve on its own and programs that
query local DNS complain. Check afterwards with `getent hosts $(hostname)`.

The name only appears in the prompt of terminals opened after the change. Programs that recorded
the old name (KDE Connect, Tailscale) have to be pointed at the new one in their own interface.

---

## 4. Data disk

*Only with a second disk for data.* It is not formatted; only what lives on the SSD is rebuilt.

```bash
lsblk -f
DISCO=/dev/sdXN
sudo mkdir -p ~/HD
udisksctl unmount -b $DISCO 2>/dev/null
echo "UUID=$(lsblk -no UUID $DISCO)  $HOME/HD  btrfs  defaults,noatime,compress=zstd:1,nofail  0  0" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
findmnt ~/HD && ls -ld ~/HD
```

`findmnt` has to answer and `~/HD` has to be owned by you. ext4 disk: swap
`btrfs defaults,noatime,compress=zstd:1,nofail` for `ext4 defaults,noatime,nofail` and skip the
scrub and the `chattr`.

`nofail` silences a UUID error, which is why the check is there. The `sudo mkdir` is deliberate: a
root-owned folder blocks writes if the disk does not mount.

```bash
sudo sed -i "s|^BTRFS_SCRUB_MOUNTPOINTS=.*|BTRFS_SCRUB_MOUNTPOINTS=\"/:$HOME/HD\"|" /etc/sysconfig/btrfsmaintenance
sudo systemctl restart btrfs-scrub.timer

mkdir -p ~/HD/{Desktop,Documents,Downloads,Music,Pictures,Projects,Public,Templates,Videos}
rmdir ~/Desktop ~/Documents ~/Downloads ~/Music ~/Pictures ~/Projects ~/Public ~/Templates ~/Videos 2>/dev/null
for d in Desktop Documents Downloads Music Pictures Projects Public Templates Videos; do ln -s "HD/$d" ~/"$d"; done
xdg-user-dirs-update
rm -f ~/.local/share/user-places.xbel

grep -q '^\[General\]' ~/.config/baloofilerc 2>/dev/null || echo '[General]' >> ~/.config/baloofilerc
printf 'exclude folders[$e]=%s\n' "$HOME/HD/Games/,$HOME/HD/.pnpm-store/,$HOME/HD/VMs/,$HOME/HD/old/,$HOME/HD/.Trash-$(id -u)/,$HOME/Windows/" >> ~/.config/baloofilerc
balooctl6 disable && balooctl6 enable

mkdir -p ~/HD/VMs && chattr +C ~/HD/VMs
```

The files stay on the disk and the home gets a link to each folder: the everyday path is
`~/Documents`, and `ls -l ~` shows where it points. The link is relative (`HD/Documents`), so it
survives the home being renamed, and `rmdir` comes before `ln -s`, or the link is never created.

The link name follows the locale; the name on the disk does not. The disk uses the names from
`/etc/xdg/user-dirs.defaults`, which is why they match one-to-one on an English install and
diverge on a Portuguese one, where only `Downloads` is spelled the same on both sides. The disk
outlives the installation and the language does not, so the names on it stay neutral and the
locale lives only in the link layer, which is disposable. That is also what spares you writing
`user-dirs.dirs`: with the links already named the way the locale expects,
`xdg-user-dirs-update` generates the file correctly on its own, and keeps generating it at every
login. Writing it by hand with other names is a fight with it.

A symlink, not a bind mount: the content exists in one place only, Baloo indexes it once (it does
not follow symlinks) and `du ~` does not count it twice. In exchange, `realpath` answers the real
path inside `~/HD`, and some programs display that one — Dolphin's breadcrumb, for instance. With
the disk unmounted the links dangle and writes fail, which beats writing to the SSD believing it
worked; `xdg-user-dirs-update` will not replace a dangling link with a real folder, but it does
create any of the nine that is missing, on the SSD.

Removing `user-places.xbel` regenerates Dolphin's places, which do not follow the change — run it
with Dolphin closed. `chattr +C` only applies to files created afterwards.

`Projects` is in the system template (`/etc/xdg/user-dirs.defaults`), but Dolphin does not create
it in places. Drag the folder onto the sidebar and give it the `folder-development` icon:

```bash
printf '[Desktop Entry]\nIcon=folder-development\nType=Directory\n' > ~/Projects/.directory
```

The sidebar shortcut gets a bare gear instead: `folder-development` would come out coloured there,
because Tela (§3.4) only has it at 16 px and in `scalable`, and `scalable` is a link to
`default-folder-system`. The artwork comes from [SVG Repo](https://www.svgrepo.com/svg/479390/gear),
recoloured to follow the colour scheme and shrunk to leave a margin; it goes into `hicolor`, which
Tela inherits and its `install.sh` does not overwrite:

```bash
mkdir -p ~/.local/share/icons/hicolor/scalable/places
curl -sS https://www.svgrepo.com/show/479390/gear.svg |
  sed -e 's|<style type="text/css">|<style id="current-color-scheme" type="text/css">|' \
      -e 's|\.st0{fill:#000000;}|.ColorScheme-Text { color:#aaaaaa; }|' \
      -e 's|class="st0"|class="ColorScheme-Text" style="fill:currentColor"|' \
      -e 's|<g>|<g transform="translate(71.7 71.7) scale(0.72)">|' \
  > ~/.local/share/icons/hicolor/scalable/places/gear-projects.svg
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor
```

Use `gear-projects` on the shortcut. SVG Repo's download URL lands on a Vercel challenge; the
display one (`/show/`) hands over the file. Without `gtk-update-icon-cache` the new icon does not
appear: the theme's prebuilt index stays newer than the folder and Qt does not re-read the
directory.

**Home already in use.** The steps above assume empty folders. With content in them, move it
before changing `user-dirs.dirs`: pointing first leaves the system looking at empty folders and
cuts off access to what is already there.

Start by checking where each folder points today, with the disk mounted:

```bash
findmnt ~/HD
for k in DESKTOP DOWNLOAD DOCUMENTS PICTURES VIDEOS MUSIC TEMPLATES PUBLICSHARE; do
  printf '%-12s %s\n' "$k" "$(xdg-user-dir $k)"
done
```

No line may answer exactly `$HOME`. When one does, the variable is empty — and the whole home
would become the source of the copy in the next step. Fix `user-dirs.dirs` before going on.

`--ignore-existing` preserves whatever is already at the destination and `--remove-source-files`
empties the source as it copies, so the command can be repeated without duplicating anything:

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
rsync -a --ignore-existing --remove-source-files ~/Projects/                    ~/HD/Projects/
```

`Projects` goes by name because, unlike the other eight, Dolphin does not create it — it may
simply not exist yet. If it does not, `rsync` complains and the rest carries on.

Whatever is left over shares a name with a file already at the destination — nothing was
overwritten, and those collisions stay in the home for you to settle by hand. Run this **before**
creating the links, because the current `user-dirs.dirs` is what still points at the old folders;
once the links exist the loop looks at the destination instead and counts everything just moved as
a collision:

```bash
for k in DESKTOP DOWNLOAD DOCUMENTS PICTURES VIDEOS MUSIC TEMPLATES PUBLICSHARE; do
  d=$(xdg-user-dir $k)
  n=$(find "$d" -type f 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && printf '%s: %s file(s) not moved\n' "$d" "$n"
done
find ~/Desktop ~/Documents ~/Downloads ~/Music ~/Pictures ~/Projects ~/Public ~/Templates ~/Videos -type d -empty -delete 2>/dev/null
```

With the collisions settled, keep a copy of the two files about to be rewritten, then follow the
block above from `rmdir` onwards, which now finds the source folders empty.

```bash
cp -a ~/.config/user-dirs.dirs ~/.config/user-dirs.dirs.bak
cp -a ~/.local/share/user-places.xbel ~/.local/share/user-places-pre-HD.xbel
```

Log out and back in. To check:

```bash
xdg-user-dir DOWNLOAD
grep -o 'file:///home/[^"]*' ~/.local/share/user-places.xbel
```

Afterwards, sweep for whatever recorded the disk's old path (`/run/media/...`): Steam, libvirt,
Zed, recent documents.

```bash
grep -rl "/run/media/$USER" ~/.config ~/.local/share 2>/dev/null
```

Through the interface: Spectacle's and Elisa's folders. Files deleted from inside the HD go to
`~/HD/.Trash-$(id -u)`, which KDE does not empty — check it with `du -sh`.

**Games.** A folder on the disk for them, with the usual link in the home:

```bash
mkdir -p ~/HD/Games
rmdir ~/Games 2>/dev/null
ln -s HD/Games ~/Games
```

The `rmdir` is the same care the folder block takes: with `~/Games` already there, `ln -s` would
create the link *inside* it and still exit successfully, leaving a dangling link and the library on
the SSD.

In Steam, **Settings → Downloads → Steam Library Folders**: add `~/Games` and right-click to make
it the default. It creates `SteamLibrary` in there — that name is Steam's own, leave it.

Do this **before installing any game**: then nothing lands on the SSD and there is nothing to move
later. A game already installed only changes place through **Properties → Installed Files → Move
install folder**, never by moving the folder by hand.

**Windows on the same machine** — mount its disk read-only and put the loader back from it:

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

The loader comes from the Windows partition itself, which keeps a copy of the ESP tree under
`EFI/Microsoft/Boot/` — `bootmgfw.efi` and the BCD together. That is why the mount comes first,
and why no backup taken before formatting is needed ⚠️ not tested here. If that folder is absent
on your install, the loader alone sits at `Windows/Boot/EFI/bootmgfw.efi`, but without the BCD it
is not enough: then the route is Windows' own recovery (`bcdboot C:\Windows /s S:`).

`WIN` is the large partition, not the "Microsoft reserved" one. If `lsblk -f` shows `BitLocker` in
place of `ntfs`, the disk is encrypted and will not mount: turn BitLocker off, or suspend it, from
Windows.

With dual boot, fix the clock as well — the two systems read the hardware clock differently and
the time ends up wrong in one of them on every switch:

```bash
timedatectl                      # "RTC in local TZ: yes" is the problem
sudo timedatectl set-local-rtc 0
```

Linux moves to UTC, which is the right one; on the Windows side, create the `RealTimeIsUniversal`
DWORD with value 1 under
`HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation`. The reverse recipe —
putting Linux on local time — works, but systemd advises against it: it breaks on daylight saving
and at boot, before the timezone database loads.

openSUSE ships `ntfs3` blacklisted (`/usr/lib/modprobe.d/60-blacklist_fs-ntfs3.conf`, "isn't
actively supported by SUSE"); the automatic unblock only works in an interactive terminal, so
without the `ln -s` above the mount fails with *unknown filesystem type*. The same effect,
interactively: `sudo modprobe ntfs3` and answer `y`. Alternative: use `ntfs-3g` in place of
`ntfs3` in `fstab` — it is FUSE, slower, and does not go through the blacklist.

`ro` stays: with Fast Startup on, Windows discards whatever Linux writes to the NTFS. Only move to
`rw` after turning Fast Startup off.

**Disk labels** — the name that shows up in Dolphin and in the partition manager. None of this is
required, and since `fstab` goes by `UUID=`, changing a label affects neither mounting nor boot.

```bash
sudo btrfs filesystem label / System
sudo btrfs filesystem label ~/HD Data
sudo umount ~/Windows
sudo sfdisk --part-label /dev/sdX N Windows
sudo udevadm trigger --settle --subsystem-match=block
```

Btrfs changes the label with the filesystem mounted, and the command **says nothing when it
works** — silence is success. But `lsblk` and KDE read from the udev cache, which does not
re-probe a device in use on its own: without the `udevadm trigger` above, or a reboot, the old
value stays on screen and it looks as though the command failed.

For Windows the change is to the **GPT partition name** (`/dev/sdX` and `N` are the disk and the
number of `WIN` above), not to the NTFS. That partition usually arrives with no filesystem label
and with the GPT name `Basic data partition`, which is exactly what the managers display. Touching
only the GPT writes no byte to the NTFS — which matters with Fast Startup on — and the partition
type does not change, so Windows' boot is unaffected. `ntfslabel` would do the same by writing
inside the NTFS, with the partition unmounted; avoid it for the same reason as the `ro`.

---

## 5. Verification

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

ESP below 50 %; initrd ~130-140 MB with NVIDIA, < 80 MB without; up to 3 kernels; Mesa
`openSUSE`; no "no microcode"; Downloads at `~/Downloads`, pointing to the disk;
`RTC in local TZ: no`.

`firewalld` comes active from the installation, with the network interface in the `public` zone:
everything incoming is blocked, everything outgoing is free. KDE Connect opens itself when
installed; the rest is manual.

```bash
firewall-cmd --list-all                                          # what is open today
sudo firewall-cmd --permanent --add-service=ssh                  # if you will use SSH
sudo firewall-cmd --permanent --add-port=53317/tcp --add-port=53317/udp   # LocalSend
sudo firewall-cmd --reload
```

LocalSend has no ready-made service in firewalld and receives no file with the port closed —
sending works, receiving does not, with no error to explain it. To reach this machine over the
VPN, `sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0` (§3.4).

---

## 6. Maintenance

```bash
sudo zypper dup
df -h /boot/efi
snapper list
```

Always `dup`, never `update` — on Tumbleweed and on Slowroll alike. Once or twice a week is
enough; months without updating call for a few `dup` cycles in a row.

The size `flatpak list` shows is each item's cost in isolation, not what you get back by removing
it: runtimes share objects through hardlinks, and deleting one whose sibling is still installed
frees a fraction of the advertised number.

| Action | Command |
|---|---|
| Update the system | `sudo zypper dup` |
| See what would change first | `zypper dup --dry-run` |
| Search for a package | `zypper se <name>` |
| List what is installed | `zypper se -i` |
| A package's origin and version | `rpm -q --qf '%{VENDOR} %{VERSION}\n' <name>` |
| Install a pattern | `sudo zypper in -t pattern <name>` · `zypper se -t pattern` lists them |
| Lock a package's version | `sudo zypper addlock <name>` · `removelock` undoes it |
| Free the download cache | `sudo zypper clean` |
| Update Flatpaks | `flatpak update --user` |
| Collect orphaned runtimes | `flatpak uninstall --unused` |
| See snapshots and what each one takes | `sudo snapper list` · `sudo btrfs qgroup show -p --sort=excl /` |

Snapshots limit themselves on three fronts: by **count** (`NUMBER_LIMIT="2-10"`, with
`NUMBER_MIN_AGE=3600` protecting the last hour), by **space** (`SPACE_LIMIT="0.5"` and
`FREE_LIMIT="0.2"` — at most half the filesystem, and at least 20 % of the disk free) and by
**time**, which comes disabled on root (`TIMELINE_CREATE="no"`: only `zypper`'s pre/post pairs
exist). What runs them is `snapper-cleanup.timer`, every hour. The `excl` column of `qgroup show`
is what each snapshot occupies on its own — what you actually get back by deleting it.

---

## 7. Recovery

→ **[troubleshooting](troubleshooting.md)**, by symptom.

---

## Sources

[Tumbleweed installation](https://en.opensuse.org/openSUSE:Tumbleweed_installation) · [SDB:NVIDIA drivers](https://en.opensuse.org/SDB:NVIDIA_drivers) · [SDB:Packman codecs](https://en.opensuse.org/SDB:Installing_codecs_from_Packman_repositories) · [doc.opensuse.org](https://doc.opensuse.org/documentation/tumbleweed/)
