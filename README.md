# openSUSE KDE Setup

**English** · [Português](README.pt-BR.md)

Documentation and scripts that take a machine from an empty disk to a working
**openSUSE Tumbleweed or Slowroll** desktop with **KDE Plasma**, systemd-boot and btrfs
snapshots.

Written for any machine rather than one specific build: steps that depend on hardware (NVIDIA,
WiFi, dual boot with Windows, a secondary data disk) are marked where they appear.

Every document exists in both languages, with a switch link at the top.

## Documentation

| Document | What it covers |
|---|---|
| [Installation guide](docs/installation-guide.md) | partitioning, kernel safety net, repositories, drivers, codecs, applications, data disk |
| [Troubleshooting](docs/troubleshooting.md) | by symptom, for when something breaks |
| [SSH and git](docs/ssh-and-git.md) | SSH keys kept in the Bitwarden vault, no private key on disk |
| [Video and DaVinci Resolve](docs/video-davinci.md) | installing Resolve, video conversion entries in Dolphin |

## Scripts

Run them from the repository root — that is what `./` means in the guides.

| Script | What it does |
|---|---|
| `scripts/install-dup-notifier.sh` | update notifications for `zypper` and Flatpak, without PackageKit |
| `scripts/install-davinci.sh` | downloads, installs and fixes up DaVinci Resolve |
| `scripts/convert-video` + `.desktop` | video conversion entries in the Dolphin context menu |

## Order

1. **Install** — guide §1. Expert partitioner, 2 GiB ESP, btrfs with snapshots, systemd-boot.
2. **Kernel safety net** — guide §2, before the first `zypper dup`. Keeps the previous kernel
   bootable (`latest-1`) and builds a lean initrd.
3. **System and software** — guide §3. `sudo zypper ref && sudo zypper dup && sudo reboot`, then
   the driver, codecs from Packman Essentials, applications, and
   `sudo ./scripts/install-dup-notifier.sh`.
4. **Data disk** — guide §4. Mount point, XDG folders, Baloo, the Windows partition.
5. **Extras** — SSH and git, video and DaVinci Resolve.
6. **Check** — guide §5.

Something broke → [troubleshooting](docs/troubleshooting.md).

## Scope

Rolling releases only. Tumbleweed and Slowroll are both covered, and the differences are noted
where they occur instead of in a section of their own. Always `zypper dup`, never
`zypper update`.

Codecs come from Packman **Essentials**, not a full vendor change. Out of scope: Android
tooling, emulator camera and virtual machines.

## Licence

[MIT](LICENSE).
