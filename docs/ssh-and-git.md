# Bitwarden SSH agent and git

**English** · [Português](ssh-and-git.pt-BR.md)

SSH keys kept in the vault, with no private key file on disk. Works for the terminal and for
graphical applications.

## 1. Bitwarden desktop

The agent only exists in the desktop application — a browser extension will not do. Three
sources, in order of preference:

```bash
zypper info bitwarden          # repo-oss, but usually behind the Flathub version
flatpak install --user flathub com.bitwarden.desktop
```

The Flatpak works: since 2025 the application detects `FLATPAK_ID` and creates the socket inside
its own data folder, which is visible to the system. No `flatpak override` needed.

| Source | Socket path |
|---|---|
| Flatpak | `~/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock` |
| `.rpm` or repository package | `~/.bitwarden-ssh-agent.sock` |

Older guides state that the Flatpak will not do. That was true before the application started
handling the case; check the path above before changing packages over it.

## 2. Key in the vault

In Bitwarden, a new item of type **SSH key**. It generates the pair, or accepts an existing key
pasted in. The private one never leaves the vault.

## 3. Turn the agent on

**Settings → SSH agent → enable the SSH agent.** Next to it sits the confirmation policy:

| Option | Effect |
|---|---|
| Always | confirms every signature — one `git push` asks two or three times |
| Never | any process of yours signs silently while the vault is unlocked |
| Remember until the vault is locked | approves once per key; renews when the vault locks |

The third is the middle ground, and what then decides things is the **vault lock timeout**
(Settings → Security): set to "Never", the memory is permanent and the effect becomes that of the
second row.

The socket is created when the option is ticked. Without it, nothing below works:

```bash
ls -l ~/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock   # type 's' at the start
```

## 4. Point `SSH_AUTH_SOCK` at it

One setting covers both worlds — the terminal, and applications launched from the KDE menu, which
do not read `~/.bashrc`:

```bash
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/10-bitwarden-ssh-agent.conf <<'EOT'
SSH_AUTH_SOCK=${HOME}/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock
EOT
```

Use `${HOME}`, not `%h`: `%h` is a systemd unit specifier and is not expanded in
`environment.d`. It applies from the next login; check with:

```bash
systemctl --user show-environment | grep SSH_AUTH_SOCK
```

To use it before logging out, `export SSH_AUTH_SOCK=<path>` in the terminal.

## 5. Check

```bash
ssh-add -l          # fingerprints of the keys in the vault
ssh-add -L          # the public ones, in authorized_keys format
```

| Message | Cause |
|---|---|
| `Error connecting to agent: No such file or directory` | socket does not exist: agent off, or application closed |
| `Could not open a connection to your authentication agent` | `SSH_AUTH_SOCK` not set in the session |
| `The agent has no identities` | vault locked, or the item is not of type SSH key |

`ssh-add -L` saves copying the public key through the interface — the output is already the line
that GitHub and `authorized_keys` expect.

## 6. GitHub and servers

On GitHub: **Settings → SSH and GPG keys → New SSH key**, pasting the output of `ssh-add -L`.
Name it after the machine, so you can revoke a single one later.

```bash
ssh -T git@github.com          # Bitwarden asks for approval
```

On your own server, `ssh-copy-id user@server` reads from the agent and works the same.

## 7. git

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```

An existing HTTPS repository moves to SSH with `git remote set-url origin
git@github.com:user/repo.git`. To convert them all at once, without touching each one:

```bash
git config --global url."git@github.com:".insteadOf https://github.com/
```

Signing commits with the same key from the vault, no GPG. Pick the key by the name it carries in
the vault — with more than one in the agent, taking the first on the list gets the wrong one:

```bash
ssh-add -L                                     # the names are at the end of each line
KEY=$(ssh-add -L | grep -w 'KeyName$')
git config --global gpg.format ssh
git config --global user.signingkey "$KEY"
git config --global commit.gpgsign true
```

For `git log --show-signature` to verify locally, declare the key as trusted:

```bash
mkdir -p ~/.config/git
printf '%s %s\n' "$(git config --global user.email)" "$(echo "$KEY" | cut -d' ' -f1,2)" \
  > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

On GitHub the same key has to be registered **again**, with the type switched to *Signing Key* —
the *Authentication Key* registration does not sign. Without it the commit goes out signed and
still shows as *Unverified* there. Both registrations are public and can be checked without
opening the site:

```bash
curl -s https://github.com/<user>.keys                            # authentication
curl -s https://api.github.com/users/<user>/ssh_signing_keys      # signing
```

Compare with `ssh-add -L | cut -d' ' -f1,2` — the text has to match exactly.

End-to-end check, in a throwaway repository:

```bash
cd $(mktemp -d) && git init -q && echo x > a && git add a && git commit -qm test
git log --show-signature -1        # "Good git signature for <your e-mail>"
```

## When it fails

**Works in the terminal but not in the editor** — the `environment.d` file from step 4 is
missing, or the session was not restarted after it was created.

**Stopped out of nowhere** — the vault locked on inactivity, or the application was closed. The
socket goes with it. With `commit.gpgsign=true`, `git commit` fails too, not just `push`: unlock
the vault, or pass `--no-gpg-sign` on that commit.

**The approval window does not appear** — Bitwarden is in the tray; open the window.

**Asks for the KDE wallet password when the session starts** — Bitwarden comes up on autostart
and fetches a secret through the portal, which needs `kdewallet` open. Fix in
[troubleshooting](troubleshooting.md), "KDE wallet locked".

**`No handler registered for 'sshagent.clearkeys'` in the log** — the agent never came up in that
session. The log lives at `~/.var/app/com.bitwarden.desktop/config/Bitwarden/app.log`.

**The application logs itself out**, with `File backend error Incorrect secret` and `Access token
key not found` in the same log: the sandbox's file keyring is corrupt. Deleting it fixes it, at
the cost of logging in again — the data is on the server:

```bash
rm -rf ~/.var/app/com.bitwarden.desktop/data/keyrings
```

**Swapped the Flatpak for the native package, or the other way round** — the socket path changes;
redo step 4.
