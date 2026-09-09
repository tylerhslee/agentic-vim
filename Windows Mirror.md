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
The mirror uses Watchexec, rsync, and systemd user services. Watchexec recursively
watches the native WSL vault and requests a mirror run after one second of quiet.
The guarded mirror copies changes and propagates deletions from WSL to Windows.
An hourly systemd timer performs a forced whole-tree reconciliation in case a
filesystem notification was missed or the Windows copy drifted.
The copies may differ while edits or synchronization are in progress. It is not
two-way synchronization and cannot update Windows while WSL is stopped.

The script lives outside the vault at
`~/.local/lib/leeharin-mirror/mirror.py`. Recovery copies of overwritten and
deleted destination files belong under
`~/.local/state/leeharin-mirror/backups`. These copies are a recovery aid, not
an independent backup of the authoritative WSL folder.

The event trigger is the first-party Watchexec 2.7.1 Linux x86-64 binary at
`~/.local/lib/watchexec/2.7.1/watchexec`. Its release archive was verified
against the publisher's per-asset SHA-256 value
`0b0946cdb8c9151d1db5a2c552b6229724960a58b0417fb2a20f810c2135abd2`
before installation. Watchexec
only decides when to start the existing guarded service; it does not own mirror
direction, validation, copying, deletion, or recovery policy.

Ordinary event runs fingerprint the source and skip Windows access when it is
unchanged. The hourly forced run also compares Windows, so Windows-only changes
are corrected within the next reconciliation window. A forced comparison that
finds no difference does not create an empty recovery directory. The Windows uploader's
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

Check automatic triggers, current work, and recent activity:

```bash
systemctl --user status leeharin-mirror-watch.service leeharin-mirror.timer \
  leeharin-mirror.service leeharin-mirror-reconcile.service
journalctl --user \
  -u leeharin-mirror-watch.service \
  -u leeharin-mirror.service \
  -u leeharin-mirror-reconcile.service -n 50 --no-pager
```

Pause both automatic triggers, then stop any current run:

```bash
systemctl --user disable --now leeharin-mirror-watch.service leeharin-mirror.timer
systemctl --user stop leeharin-mirror.service leeharin-mirror-reconcile.service
```

Resume automatic event watching and hourly reconciliation, or request one
immediate ordinary run:

```bash
systemctl --user enable --now leeharin-mirror-watch.service leeharin-mirror.timer
systemctl --user start leeharin-mirror.service
```

Disable automatic startup and stop current activity:

```bash
systemctl --user disable --now leeharin-mirror-watch.service leeharin-mirror.timer
systemctl --user stop leeharin-mirror.service leeharin-mirror-reconcile.service
```

Re-enable automatic operation:

```bash
systemctl --user enable --now leeharin-mirror-watch.service leeharin-mirror.timer
```

Force a Windows comparison even when the WSL files have not changed:

```bash
python3 ~/.local/lib/leeharin-mirror/mirror.py force
```

## Recovery

Pause both automatic triggers and active mirror services before investigating
an unwanted change. Inspect
`~/.local/state/leeharin-mirror/backups` and restore the wanted content into the
authoritative WSL vault. The pre-cutover copy of the former Windows layout is at
`~/.local/state/leeharin-mirror/migration-20260908/windows-before`. Review restored
content before resuming automatic operation; restoring only the Windows copy
would allow the next event or hourly reconciliation to replace it again.

To roll back the event-driven trigger, disable and stop
`leeharin-mirror-watch.service`, restore the timer's previous 15-second
`OnUnitInactiveSec` definition, reload the user manager, and re-enable the timer.
The guarded Python/rsync mirror is unchanged as the correctness boundary. After
rollback, the versioned Watchexec directory can be removed once no unit refers
to it.
