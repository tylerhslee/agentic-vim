# Windows Mirror

## Folder ownership

Use `/home/tylerhyun/leeharin` for project and agent work. The canonical vault
is `/home/tylerhyun/leeharin/LeeHaRin`; only that subtree is mirrored. Keeping
the authoritative files in WSL gives Linux tools local filesystem access.

`C:\Users\tyler hyun\Documents\leeharin` is the Windows viewing copy, accessible
from WSL at `/mnt/c/users/tyler hyun/documents/leeharin`. Treat it as read-only:
this is a user convention, not a filesystem permission. Do not edit it in
Windows or point a writable Obsidian vault or another automation at it. Changes
there can be overwritten or removed on the next mirror run.

To edit from a Windows application, open the authoritative vault through
`\\wsl.localhost\Ubuntu-24.04\home\tylerhyun\leeharin\LeeHaRin`. Windows access
crosses the filesystem boundary; Linux tools still use the local WSL path.

## Setup

WSL was seeded from Windows and verified by checksum before enabling the mirror.
The mirror uses rsync and a systemd user timer, checking about every 15 seconds
while the WSL user service manager is running. It copies changes and propagates deletions from WSL to Windows.
The copies may differ while edits or synchronization are in progress. It is not
two-way synchronization and cannot update Windows while WSL is stopped.

The script lives outside the vault at
`~/.local/lib/leeharin-mirror/mirror.py`. Recovery copies of overwritten and
deleted destination files belong under
`~/.local/state/leeharin-mirror/backups`. These copies are a recovery aid, not
an independent backup of the authoritative WSL folder.

An unchanged vault skips Windows access. Windows-only changes are corrected on
the next vault change or a forced run, not by idle checks. The Windows uploader's
root `.tmp.driveupload` temporary folder is excluded and protected; all regular
files and directories inside the vault are mirrored, including `.obsidian`.
Project-level source, agent configuration, and repository metadata never enter
the mirror source. Linux permissions and ownership are not mirrored.

The job refuses missing or replaced roots, unreadable source trees, symlinks,
Windows-incompatible names, and missing or empty `README.md`, `Profile.md`, or
`Architecture.md`. Failures are logged and retried on later checks. Root or mount
identity changes require investigation and reinitialization against matching
copies. Backups accumulate without automatic deletion; inspect disk usage
occasionally. The timer starts with the WSL user service manager and does not
start WSL from Windows by itself.

## Controls

Check status and recent activity:

```bash
systemctl --user status leeharin-mirror.timer leeharin-mirror.service
journalctl --user -u leeharin-mirror.service -n 30 --no-pager
```

Pause scheduled copying and stop any current run:

```bash
systemctl --user stop leeharin-mirror.timer leeharin-mirror.service
```

Resume scheduling, or request one immediate run:

```bash
systemctl --user start leeharin-mirror.timer
systemctl --user start leeharin-mirror.service
```

Disable automatic startup and stop current activity:

```bash
systemctl --user disable --now leeharin-mirror.timer
systemctl --user stop leeharin-mirror.service
```

Re-enable automatic scheduling:

```bash
systemctl --user enable --now leeharin-mirror.timer
```

Force a Windows comparison even when the WSL files have not changed:

```bash
python3 ~/.local/lib/leeharin-mirror/mirror.py force
```

## Recovery

Pause the timer and service before investigating an unwanted change. Inspect
`~/.local/state/leeharin-mirror/backups` and restore the wanted content into the
authoritative WSL vault. The pre-cutover copy of the former Windows layout is at
`~/.local/state/leeharin-mirror/migration-20260908/windows-before`. Review restored
content before resuming the timer; restoring only the Windows copy would allow
the next run to replace it again.
