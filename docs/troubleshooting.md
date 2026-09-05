# Troubleshooting

**English** · [Português](troubleshooting.pt-BR.md)

By symptom. Installation and configuration live in
[the installation guide](installation-guide.md).

| Symptom | Section |
|---|---|
| Will not boot, or boots into emergency mode | [Recovering from a snapshot](#recovering-from-a-snapshot) |
| `initrd` of a few KB, ESP full | [Kernel truncated](#kernel-truncated-for-lack-of-space) |
| Black background, no icons and no "Start" | [Desktop with no panel](#desktop-with-no-panel) |
| Windows does not appear in the boot menu | [Windows gone from the menu](#windows-gone-from-the-menu) |
| `mkdir ~/HD` says "permission denied" | [Data disk did not mount](#data-disk-did-not-mount) |
| Dolphin sidebar shortcuts do not open | [Dolphin places](#dolphin-places) |
| `ls ~/Windows` says "No such device" | [Windows disk will not mount](#windows-disk-will-not-mount) |
| "No space left" with the disk apparently free | [Btrfs full of snapshots](#btrfs-full-of-snapshots) |
| `zypper dup` stops and asks you to pick a solution | [Conflict during dup](#conflict-during-dup) |
| Asks for the KDE wallet password when the session starts | [KDE wallet locked](#kde-wallet-locked) |
| `zypper dup` aborts with "Empty destination in URI" | [Installation media repository](#installation-media-repository) |
| No GPU after a `dup` with a new kernel | [Kernel without the NVIDIA driver](#kernel-without-the-nvidia-driver) |
| Session opens at 640x480 and offers nothing else | [Monitor with no EDID](#monitor-with-no-edid) |
| Update notice insists after the `dup` | [Notifier on an old number](#notifier-on-an-old-number) |

---

## Recovering from a snapshot

`snapper rollback` does not work with systemd-boot: it points the default at a read-only snapshot
and the boot drops into emergency mode.

1. In the systemd-boot menu, pick a recent `Snapper:` entry.
   Never the "after installation" one: it contains `/etc/selinux/.autorelabel` and will not boot.
2. The system comes up read-only. Network and SSH work.
3. Make it writable and permanent:

```bash
findmnt -no SOURCE /
sudo btrfs property set -f /.snapshots/<N>/snapshot ro false
sudo mount -o remount,rw /
sudo btrfs subvolume list / | grep "snapshots/<N>/snapshot"
sudo btrfs subvolume set-default <ID> /
sudo reboot
```

Picking a snapshot in the menu does not change the default: without `set-default`, the next boot
goes back to the previous subvolume. Check that the two agree:

```bash
findmnt -no SOURCE /
sudo btrfs subvolume get-default /
```

`@/.snapshots/1/snapshot` is openSUSE's normal root, not a rollback. Finding snapshots that will
not boot, from a healthy system:

```bash
for n in $(ls /.snapshots | sort -n); do [ -e "/.snapshots/$n/snapshot/etc/selinux/.autorelabel" ] && echo "snapshot $n WILL NOT BOOT"; done
```

---

## Kernel truncated for lack of space

```bash
df -h /boot/efi
find /boot/efi -name 'initrd*' -printf '%s\t%p\n' | sort -n
sudo sdbootutil mkinitrd
```

Files from an already uninstalled kernel are held in place by snapshots:

```bash
sudo snapper delete <N> <N>
sudo sdbootutil cleanup
```

`snapper-cleanup.timer` does this every hour.

---

## Desktop with no panel

The session logs in and windows work, but the background stays black, with no icons and no bar.
It is not the video driver: it is the Breeze theme without the wallpaper package.

```bash
cat ~/.config/kdedefaults/package
ls -d /usr/share/wallpapers/Next
sudo zypper install breeze6-wallpapers
```

Then log out and back in. With no panel: Ctrl+Alt+Del, or
`qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout`.

The breakage only shows up at the login after the theme change — it looks like another change is
to blame.

Do not restart `plasmashell` through systemd in this state: it takes down the portal, `kded6` and
`kioworker` in a cascade until the screen goes black for real.

`Atomic modeset commit failed!` in the `kwin_wayland` log is noise with NVIDIA. Confirm with
`qdbus6 org.kde.KWin /KWin supportInformation | grep "Compositing is"`.

---

## Windows gone from the menu

If `EFI/Microsoft` has disappeared from the ESP, restore it from the Windows partition itself,
which keeps a copy of the tree under `EFI/Microsoft/Boot/` — `bootmgfw.efi` and the BCD together.
It needs `~/Windows` mounted (guide §4) ⚠️ not tested here:

```bash
sudo ls /boot/efi/EFI/Microsoft/Boot/bootmgfw.efi
ls ~/Windows/EFI/Microsoft/Boot/bootmgfw.efi
sudo cp -a ~/Windows/EFI/Microsoft /boot/efi/EFI/Microsoft
sudo bootctl update
```

Without that folder on the partition, the loader alone is at
`~/Windows/Windows/Boot/EFI/bootmgfw.efi`, but without the BCD it is not enough — then the route is
Windows' own recovery.

`bootctl list` does not show Windows even when everything is right: it only lists BLS entries. The
real check is to reboot and look at the menu. In the meantime, the BIOS boot menu will do.

---

## Data disk did not mount

`~/HD` is still the empty `root:root` folder on the SSD; `nofail` hid the error. Almost certain
cause: the wrong UUID in `fstab`. Since the links in the home point inside it, the symptom usually
shows up first as a broken `~/Documents`, or as a program that cannot save.

```bash
findmnt ~/HD
grep HD /etc/fstab
lsblk -f
```

Close Dolphin and your editor first (otherwise "target is busy"):

```bash
DISCO=/dev/sdXN
sudo sed -i "s|^UUID=.*$HOME/HD|UUID=$(lsblk -no UUID $DISCO)  $HOME/HD|" /etc/fstab
udisksctl unmount -b $DISCO
sudo systemctl daemon-reload && sudo mount ~/HD
findmnt ~/HD && ls -ld ~/HD
```

With the mount up, redo the `user-dirs.dirs` step from guide §4: `xdg-user-dirs-update` has
already put everything back under `$HOME`.

---

## Dolphin places

After guide §4, the sidebar shortcuts (Documents, Downloads, Pictures…) do not open. They keep
absolute paths in `~/.local/share/user-places.xbel` and do not follow `user-dirs.dirs`; they are
system items, and editing them one by one does not help.

Close every Dolphin window first — while open, it writes the old paths back.

```bash
cp -a ~/.local/share/user-places.xbel ~/.local/share/user-places-pre-HD.xbel
rm ~/.local/share/user-places.xbel
```

Open Dolphin. To check:

```bash
grep -o 'file:///home/[^"]*' ~/.local/share/user-places.xbel
```

Shortcuts you created yourself are lost; make them again by dragging the folder onto the sidebar.

The `user-places.xbel.bak` sitting next to it is rewritten by KDE on every save — it is not a
backup.

---

## Installation media repository

The installer registers itself as a repository pointing at the DVD or USB stick. Without the
media connected, `ref` fails on it and `dup` aborts without changing anything.

```bash
zypper lr -u
sudo zypper rr <alias with a hd:/ or cd:/ URI>
```

---

## Kernel without the NVIDIA driver

After a `dup` that brought in a new kernel, `nvidia-smi` fails and the session opens without
acceleration. NVIDIA's KMP runs a few days behind the Tumbleweed kernel.

In the systemd-boot menu pick the previous kernel entry (`latest-1`, from guide §2) and repeat the
`dup` a few days later. The KMP name carries the kernel version it was built for:

```bash
rpm -qa kernel-default 'nvidia*kmp*'
```

---

## Windows disk will not mount

`ls ~/Windows` answers "No such device" and the journal shows the real reason:

```bash
sudo journalctl -b -u "$(systemd-escape -p --suffix=mount ~/Windows)" -n 20 --no-pager
```

`unknown filesystem type "ntfs3"` means the module did not load: openSUSE keeps it blacklisted and
the automatic unblock only works in an interactive terminal — the `mount` fired by systemd never
meets that condition.

```bash
sudo ln -s /dev/null /etc/modprobe.d/60-blacklist_fs-ntfs3.conf
sudo systemctl reset-failed "$(systemd-escape -p --suffix=mount ~/Windows)"
ls ~/Windows
```

The disk itself is not at fault: `lsblk -f` shows the partition as `ntfs`, with the UUID from
`fstab`.

---

## Btrfs full of snapshots

Symptom: "no space left on device" while `df` shows free space. Btrfs counts the snapshots, `df`
does not.

```bash
sudo btrfs filesystem usage /
snapper list
sudo snapper delete 100-140          # a range of old snapshots
```

If deleting snapshots does not do it either, the space is stuck in half-used blocks:

```bash
sudo btrfs balance start -dusage=5 /
```

`snapper-cleanup.timer` cleans up every hour by `NUMBER_LIMIT` (default `2-10`) — filling up means
something created snapshots faster than that, generally a run of large `zypper dup`s. For a full
ESP, which is a different problem, see [Kernel truncated](#kernel-truncated-for-lack-of-space).

---

## Conflict during dup

`zypper dup` stops and offers numbered solutions. Read before choosing: the "easy" option is
usually to change the package's vendor to a third-party repository, which drags the whole stack
along afterwards.

```bash
zypper dup --dry-run            # see the damage first
zypper lr -u                    # a repository that is down or obsolete causes conflicts
```

Order of preference: keep the `openSUSE` vendor; if the conflict is over a codec, resolve just the
package involved with `--from packman-essentials`; uninstall the troublesome package; and only
then accept a vendor change. Never answer "yes" to a `dup` that wants to move dozens of packages
to another vendor — that is the scenario in guide §3.3.

---

## KDE wallet locked

When the session starts, *"The application `xdg-desktop-portal` has requested to open the wallet
`kdewallet`"* appears. The portal is not the one asking: it is some Flatpak that came up on
autostart and needs to store a secret — with no direct access to the keyring, it goes through the
portal, which on KDE is served by `kwalletd6`.

Automatic unlocking is already configured (`pam_kwallet5` in `common-auth-pc` and
`common-session-pc`) and only works when **the wallet password matches the login password**. The
dialog appearing means they differ.

```bash
kwalletmanager5 &
```

Select `kdewallet` → **Open...** (current password) → the **Change password...** button becomes
available → use the login password in both fields. It applies from the next boot. Check what PAM
attempted:

```bash
journalctl --user -b | grep -i pam_kwallet
```

An empty password also removes the prompt, but leaves the wallet unencrypted on disk — it holds
secrets for several applications. Taking the application out of autostart only postpones the
prompt to whenever you open it.

---

## Monitor with no EDID

Only with an NVIDIA card and the monitor on DisplayPort.

The session opens at 640x480 and that is the only resolution on offer. When the PC boots with the
monitor switched off or in deep sleep, reading the EDID over the DisplayPort AUX channel fails and
the driver fabricates a synthetic EDID with a single mode.

```bash
kscreen-doctor -o | grep Modes
grep -o '"edidIdentifier": "[^"]*"' ~/.config/kwinoutputconfig.json
```

`NVD 0 0 0 0 0` is the invented EDID; the monitor's own carries a manufacturer and a year. Note
that `/sys/class/drm/card*-DP-1/edid` stays at 0 bytes even with everything working — the
proprietary driver does not publish the EDID there, so the mode list is what counts.

Switch the monitor on, then unplug and replug the DP cable: the hotplug re-probes the link and KDE
returns to the saved profile on its own. There is no fix in software — with a single mode on the
list, `kscreen-doctor` has nowhere to move to.

To stop it happening again, switch the monitor on before the PC, or move to DVI-D or HDMI, where
the EDID travels over DDC/I²C powered by the card's own +5 V and is read with the monitor asleep
⚠️ not tested here. Forcing it through `drm.edid_firmware` does not help: the proprietary driver
does not fetch the EDID through the DRM helper path.

Each occurrence leaves one more profile in `~/.config/kwinoutputconfig.json`, harmlessly. Deleting
it prevents nothing: the 640x480 comes from the driver, not from the profile.

`Atomic modeset commit failed!` in the log shows up in both cases and does not tell them apart,
see [Desktop with no panel](#desktop-with-no-panel).

---

## Notifier on an old number

The notice keeps reporting pending packages after a `sudo zypper dup` run by hand. The number is
not measured on the spot: `dup-notify` and the terminal notice only read `/var/lib/dup-count`,
written by `dup-check.timer`, which runs once a day.

```bash
cat /var/lib/dup-count
stat -c '%y' /var/lib/dup-count
systemctl list-timers dup-check.timer
```

A counter dated before the last `dup` is the case. Confirm there is genuinely nothing pending:

```bash
zypper --no-refresh lu
flatpak remote-ls --updates
zypper --no-refresh se -s openSUSE-release
```

`i+` on the `openSUSE-release` line means the repository is at the same snapshot already
installed. To correct the number now:

```bash
sudo /usr/local/bin/dup-check
```

The notification already on screen does not expire by itself, by the script's own choice: close it
in the Plasma notification centre.

`install-dup-notifier.sh` in this repository already carries the permanent fix — `dup-check.path`
recalculates after every rpm transaction, and both readers stay quiet when the rpmdb is newer than
the counter. Reinstall with `sudo ./scripts/install-dup-notifier.sh`.

