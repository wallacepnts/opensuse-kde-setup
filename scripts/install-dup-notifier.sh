#!/bin/bash
# Update notifier for Tumbleweed, without PackageKit. A system timer refreshes
# the metadata and writes the count; the user side only reads the file.
set -euo pipefail

# sudo does not always keep the caller's locale, so fall back to the system one.
L="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
[ -n "$L" ] || L=$(sed -n 's/^LC_MESSAGES=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
[ -n "$L" ] || L=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
case "$L" in pt*) PT=1;; *) PT=0;; esac
say(){ if [ "$PT" = 1 ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; }

[ "$(id -u)" = 0 ] || { say "run this with sudo" "rode com sudo"; exit 1; }

# /var survives reboots; /run is tmpfs.
CONTA=/var/lib/dup-count

cat > /usr/local/bin/dup-check <<EOF
#!/bin/bash
# Writes to $CONTA how many packages a 'zypper dup' would change. On failure
# it keeps the previous value instead of writing 0, which would lie.
set -u
C=$CONTA
zypper -n ref >/dev/null 2>&1 || { echo "\$(date -Is) refresh failed" >> \${C}.log; exit 1; }
xml=\$(zypper -n --no-refresh --xmlout dup --dry-run 2>/dev/null) || {
  echo "\$(date -Is) dup --dry-run failed" >> \${C}.log; exit 1; }
n=\$(printf '%s' "\$xml" | sed -n 's/.*packages-to-change="\([0-9]*\)".*/\1/p' | head -1)
case "\$n" in ''|*[!0-9]*) echo "\$(date -Is) unexpected output" >> \${C}.log; exit 1;; esac
printf '%s\n' "\$n" > "\$C"
EOF
chmod +x /usr/local/bin/dup-check

cat > /etc/systemd/system/dup-check.service <<EOF
[Unit]
Description=Check for Tumbleweed updates
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
Environment=ZYPP_LOCK_TIMEOUT=300
ExecStart=/usr/local/bin/dup-check
EOF

cat > /etc/systemd/system/dup-check.timer <<'EOF'
[Unit]
Description=Check for Tumbleweed updates daily
[Timer]
OnCalendar=daily
RandomizedDelaySec=30min
Persistent=true
[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/dup-check.path <<'EOF'
[Unit]
Description=Recount pending updates after an rpm transaction
[Path]
PathChanged=/usr/lib/sysimage/rpm/Packages.db
Unit=dup-check.service
[Install]
WantedBy=paths.target
EOF

# The old Portuguese name would otherwise linger and print the notice twice.
rm -f /etc/profile.d/dup-aviso.sh
cat > /etc/profile.d/dup-notice.sh <<EOF
# Terminal only: 'bash -lc' also reads this file, and the colour would corrupt
# the output of whoever is capturing text.
if [ -t 1 ] && [ -s $CONTA ] && [ ! /usr/lib/sysimage/rpm/Packages.db -nt $CONTA ]; then
  n=\$(cat $CONTA 2>/dev/null)
  case "\$n" in ''|*[!0-9]*) ;; 0) ;;
    *) case "\${LC_ALL:-\${LC_MESSAGES:-\${LANG:-}}}" in
         pt*) m="pacotes aguardando atualizacao";;
         *)   m="packages pending update";;
       esac
       printf '\n  \033[1;33m%s %s\033[0m  ->  sudo zypper dup\n\n' "\$n" "\$m";;
  esac
fi
EOF

systemctl daemon-reload
systemctl enable --now dup-check.timer dup-check.path
/usr/local/bin/dup-check || say "warning: first check failed (see ${CONTA}.log)" \
                                "aviso: primeira verificacao falhou (ver ${CONTA}.log)"
PEND=$(cat "$CONTA" 2>/dev/null || echo '?')
say "system: installed. pending now: $PEND" "sistema: instalado. pendentes agora: $PEND"

# ── user side: the desktop notification ────────────────────────────────────
U=${SUDO_USER:-}
[ -z "$U" ] && { say "(no SUDO_USER — graphical part not installed)" \
                     "(sem SUDO_USER — parte gráfica não instalada)"; exit 0; }

H=$(getent passwd "$U" | cut -d: -f6) || H=""
[ -n "$H" ] && [ -d "$H" ] || { say "ERROR: home of '$U' not found" "ERRO: home de '$U' não encontrada"; exit 1; }

command -v notify-send >/dev/null || {
  say "installing libnotify-tools (provides notify-send)..." \
      "instalando libnotify-tools (fornece o notify-send)..."
  zypper -n install libnotify-tools >/dev/null 2>&1 || {
    say "failed; graphical part not installed" "falhou; parte gráfica não instalada"; exit 0; }
}

D="$H/.config/systemd/user"
# The primary group is not always named after the user.
G=$(id -gn "$U")
# -d applies ownership only to each component it is given, so name every level:
# a freshly created ~/.config would otherwise stay owned by root.
install -d -o "$U" -g "$G" "$H/.config" "$H/.config/systemd" "$D"

# Runs as the user: only they can see the --user Flatpaks.
cat > /usr/local/bin/dup-notify <<EOF
#!/bin/bash
set -u
# systemd --user may start this with no locale, so fall back to the system one.
L="\${LC_ALL:-\${LC_MESSAGES:-\${LANG:-}}}"
[ -n "\$L" ] || L=\$(sed -n 's/^LC_MESSAGES=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
[ -n "\$L" ] || L=\$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | tail -1 | tr -d '"')
case "\$L" in pt*) PT=1;; *) PT=0;; esac
pick(){ if [ "\$PT" = 1 ]; then printf '%s' "\$2"; else printf '%s' "\$1"; fi; }

n=\$(cat $CONTA 2>/dev/null)
case "\$n" in ''|*[!0-9]*) n=0;; esac
# The count only holds until the next rpm transaction: after a manual 'zypper
# dup' it would lie until the next dup-check. Newer rpmdb = stale number.
[ /usr/lib/sysimage/rpm/Packages.db -nt $CONTA ] && n=0
f=\$(flatpak remote-ls --updates --user --columns=application 2>/dev/null | grep -c . || true)

[ "\$n" = 0 ] && [ "\$f" = 0 ] && exit 0
[ "\$n" != 0 ] && [ "\$f" != 0 ] && t=\$(pick "\$n packages and \$f flatpaks pending" "\$n pacotes e \$f flatpaks aguardando")
[ "\$n" != 0 ] && [ "\$f" = 0 ] && t=\$(pick "\$n packages pending" "\$n pacotes aguardando")
[ "\$n" = 0 ] && [ "\$f" != 0 ] && t=\$(pick "\$f flatpaks pending" "\$f flatpaks aguardando")

c=""
[ "\$n" != 0 ] && c="sudo zypper dup"
[ "\$f" != 0 ] && c="\${c:+\$c   ·   }flatpak update --user"

# 'critical' does not expire on its own: it stays until closed.
exec notify-send -a "\$(pick Updates Atualizacoes)" -i system-software-update -u critical "\$t" "\$c"
EOF
chmod +x /usr/local/bin/dup-notify

cat > "$D/dup-notify.service" <<'EOF'
[Unit]
Description=Notify about pending system and Flatpak updates
[Service]
Type=oneshot
ExecStart=/usr/local/bin/dup-notify
EOF

cat > "$D/dup-notify.timer" <<'EOF'
[Unit]
Description=Check for pending updates at login and every 6h
[Timer]
OnStartupSec=3min
OnUnitActiveSec=6h
[Install]
WantedBy=timers.target
EOF

chown -R "$U:$G" "$H/.config/systemd"

UID_=$(id -u "$U")
if [ -d "/run/user/$UID_" ] && \
   runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$UID_" \
     systemctl --user enable --now dup-notify.timer 2>/dev/null; then
  say "user: desktop notification enabled for $U" "usuario: notificacao grafica ativada para $U"
else
  say "user: units written. Run WITHOUT sudo, in your terminal:" \
      "usuario: unidades gravadas. Rode SEM sudo, no seu terminal:"
  echo "         systemctl --user enable --now dup-notify.timer"
fi
