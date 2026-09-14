# OmaRemote

OmaRemote is an Omarchy 4 (Quattro) bar widget for remote filesystems and SSH hosts.

- **sshfs:** toggle on runs `sshfs` immediately (8s timeout). Shares are not mounted at login.
- **SMB:** `gio mount` (gvfs) with an 8s timeout. Not mounted at login.
- **SSH hosts:** append marked `Host` blocks to `~/.ssh/config` (default identity `~/.ssh/id_ed25519`). Connect still happens in a terminal.

Plugins execute **unsandboxed** inside `omarchy-shell`. Review this source before enabling it.

## Dependencies

Python 3 (stdlib only), `sshfs` / fuse3, `gio` (gvfs), `wl-copy`, `xdg-open`. Optional: `gvfs-smb` for SMB.

## Install

From git:

```bash
omarchy plugin add https://github.com/tonyrumans/omaremote.git --enable
```

Or copy this folder to `~/.config/omarchy/plugins/omaremote`, then:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/omaremote
omarchy plugin enable omaremote --section right
```

Left-click the bar icon to open Hosts, search focused. Type to filter, ↑↓ to move the highlight.

- **Enter** — terminal SSH (`omarchy-launch-terminal ssh -- <alias>`)
- **Ctrl+Enter** (or the folder icon) — file manager over sftp
- **Ctrl+K** (or the key icon) — copy the public key to the clipboard (does not run `ssh-copy-id`)
- **Shift+Enter** — edit an OmaRemote-managed alias (unmanaged Host blocks stay read-only)

Right-click the icon to refresh. The widget defaults to the right section.

## Configure

```bash
omarchy bar move omaremote --section right
```

## How to use

1. Left-click the bar icon (Hosts opens with search focused).
2. Type to filter, ↑↓ to move, **Enter** to SSH in a terminal.
3. **Ctrl+Enter** opens the host in your file manager over sftp; **Ctrl+K** copies the public key; **Shift+Enter** edits a managed alias.
4. Switch to **Shares** to add sshfs/SMB mounts under `~/mnt`, toggle them on/off, and open mounted folders.
5. Right-click the bar icon to refresh.


## Shares

Share definitions live in `~/.config/omaremote/config.json` (created on first use). Mount points default to `~/mnt/<name>` and must stay under `~/mnt`.

### sshfs

Toggle **on** mounts with `sshfs` right away (`timeout 8`, `ConnectTimeout=5`, `BatchMode=yes`). A dead host fails that toggle in about 8s instead of hanging forever. It does **not** auto-mount at login.

Toggle **off** lazy-unmounts with `fusermount3 -uz`. Older builds wrote systemd `--user` automount units; toggle still tears those leftovers down. `allow_other` is never used.

### SMB

cifs user mounts usually need root, so OmaRemote uses `gio mount smb://[domain;]user@host/share` with `timeout 8`. Passwords are stored in `~/.config/omaremote/credentials/<name>` (mode `0600`) and piped to gio on stdin. SMB is not mounted at login.

### Open a share

Click the share name (or run `omaremote shares open --name …`). The helper probes the mount with an 8s timeout, then launches the file manager without waiting on it. sshfs must already be mounted.

## SSH hosts

`omaremote hosts add` appends a marked block so later updates stay scoped to hosts this plugin created:

```
# BEGIN omaremote:<alias>
Host <alias>
    HostName <hostname>
    User <user>
    IdentityFile ~/.ssh/id_ed25519
# END omaremote:<alias>
```

Existing `Host` stanzas this plugin did not write are never modified. `--generate-key` creates `~/.ssh/omaremote_<alias>_ed25519` only if that file does not already exist. Private key material is never printed.

Connect is not done by the helper. The panel launches:

```bash
omarchy-launch-terminal ssh -- <alias>
```

## Helper

`bin/omaremote` is Python 3, standard library only. It always prints one JSON object on stdout. Exit `0` on success, `2` on user/config errors, `1` on unexpected failures. User values are passed as argument arrays, never interpolated into a shell string.

External tools (`sshfs`, `gio`, `systemctl`, `ssh-keygen`, `xdg-open`, etc.) are resolved only under `/usr/bin` and `/bin` (plus `/usr/sbin`/`/sbin` for fuse/systemd helpers), via a fixed `PATH=/usr/bin:/bin`. Subprocesses get a minimal trusted environment (`HOME`/`USER` from the passwd database, validated `XDG_CONFIG_HOME` / `XDG_RUNTIME_DIR`). Captured stdout/stderr and helper JSON output are capped at 64KiB. The panel launches the helper with `/usr/bin/python3`.

```
omaremote hosts list
omaremote hosts add --alias NAME --hostname HOST --user USER [--identity PATH] [--generate-key]
omaremote hosts update --alias NAME [--new-alias NAME] [--hostname HOST] [--user USER] [--identity PATH]
omaremote hosts remove --alias NAME
omaremote hosts files --alias NAME
omaremote hosts pubkey --alias NAME

omaremote shares list
omaremote shares status
omaremote shares add --name NAME --type sshfs --ssh-alias ALIAS [--remote-path PATH] [--mount-point PATH]
omaremote shares add --name NAME --type smb --host HOST --share SHARE [--username USER] [--domain DOM]
omaremote shares update --name NAME [--new-name NAME] …
omaremote shares password --name NAME --password PASS
omaremote shares toggle --name NAME on|off
omaremote shares open --name NAME
omaremote shares remove --name NAME
```

Prefer setting SMB passwords from the panel so they land in the credentials file. Passing `--password` on the CLI can show up in process lists.

## Remove

Toggle shares off in the panel first (unmounts sshfs / `gio mount -u`), then:

```bash
omarchy plugin disable omaremote
omarchy plugin remove omaremote
```

Removing the plugin leaves `~/.config/omaremote/` and any marked SSH blocks in place:

```bash
omaremote shares list   # then toggle off / remove each share
omaremote hosts remove --alias NAME
rm -rf ~/.config/omaremote
```

## License

MIT
