# Mirror Tool Research

## Purpose-built synchronizers

### Recommendation

Keep the existing guarded Python program and `rsync` as the mirror engine. If lower latency is worth adding a long-running process, use **Watchexec**—a maintained Rust file-watcher—to invoke that existing program after WSL-source events, and retain a slower periodic timer as reconciliation.

The important distinction is that Watchexec should be only a trigger. The existing program already owns the safety contract that none of the candidates reproduces by configuration alone: fixed source and destination identities, required-file checks, rejection of symlinks and Windows-incompatible names, source fingerprinting, a lock, pre-change destination backups, delayed placement/deletion, a whole-tree dry-run verification, and a retry when the source changes during a copy. `rsync` natively supports destination deletion, delayed updates, and separate backup directories, which are the transfer primitives the program already uses ([official rsync manpage](https://rsync.samba.org/ftp/rsync/rsync.1.html)).

A production design would use a user `systemd` service roughly equivalent to:

```text
watchexec
  --watch /home/tylerhyun/leeharin/LeeHaRin
  --project-origin /home/tylerhyun/leeharin/LeeHaRin
  --debounce 1s
  --on-busy-update queue
  --ignore-nothing
  --no-follow-symlinks
  --no-meta
  --shell none
  -- /usr/bin/systemctl --user start leeharin-mirror.service
```

These flags matter. Watchexec recursively watches directories using kernel mechanisms, runs the command once on startup, and debounces related events ([official manual](https://github.com/watchexec/watchexec/blob/main/doc/watchexec.1.md#description)). `queue` schedules one more run if a change arrives while the mirror is running; its default instead ignores such events ([official manual](https://github.com/watchexec/watchexec/blob/main/doc/watchexec.1.md#command)). `--ignore-nothing` prevents its built-in and discovered ignore rules from hiding a file that the mirror contract includes, while explicit watcher ignores could still be added for the four roots already excluded by the Python program ([official filtering documentation](https://github.com/watchexec/watchexec/blob/main/doc/watchexec.1.md#filtering)). `--shell none` preserves an explicit argument vector instead of introducing shell parsing.

Do **not** remove reconciliation entirely. Linux inotify watches are not intrinsically recursive, have per-user watch limits, have a finite event queue, and can lose events on overflow; robust consumers must be prepared to rescan ([Linux `inotify(7)`](https://man7.org/linux/man-pages/man7/inotify.7.html)). Watchexec handles recursive watch construction, but it does not turn kernel notifications into an authoritative change ledger. A periodic forced comparison (for example hourly and at watcher startup) is the recovery path for a missed notification, watcher restart, or implementation defect. The present Python fingerprint means ordinary duplicate triggers are harmless.

Watchexec fits the Rust preference without creating a new custom daemon. Its repository describes recursive monitoring and event coalescing and publishes first-party Linux binaries and Cargo installation. Release 2.7.1 was published on September 3, 2026, in a history spanning 98 releases back to 2016 ([official repository](https://github.com/watchexec/watchexec), [official downloads](https://watchexec.github.io/downloads/watchexec/), [official package list](https://github.com/watchexec/watchexec/blob/main/doc/packages.md)).

### Comparison

| Candidate | One-way authority and deletion | Recursive events and batching | Destination recovery | Fit with current safeguards | Maintenance and WSL fit | Verdict |
|---|---|---|---|---|---|---|
| Existing guarded Python + `rsync` timer | Exact WSL-to-Windows authority; `--delete-delay` propagates deletions | Full-tree fingerprint polling every ~15 seconds; no event dependency | Timestamped `--backup-dir` for overwritten/deleted destination content | Baseline: all current guards and read-back verification | `rsync` is mature and actively maintained; current service is already active under the WSL user manager | Keep as the engine and fallback |
| Watchexec invoking existing mirror | Authority and deletion remain entirely in the guarded program | Recursive native watching; configurable debounce; `queue` prevents ignoring changes during a run | Unchanged because the guarded program still performs backups | Preserves the existing contract instead of replacing it | Rust, current releases, easy to supervise with `systemd`; cannot operate after WSL shuts down | **Best event-driven option** |
| Lsyncd `default.rsync` | Explicitly one source to one target; by default removes target-only files at startup and during operation | Watches a recursive source tree through inotify, aggregates events for `delay` seconds or until 1,000 uncollapsible events, and runs filtered rsync transfers | Supports rsync `backup` and a configured `backup_dir`, but a static directory is not equivalent to the current timestamped per-run recovery sets | Replacing the engine drops root/mount identity pinning, required-file and filename checks, stable-source fingerprinting, whole-tree verification, and the current recovery layout | Works as a foreground daemon under `systemd`, but the project currently says it needs a new maintainer | Good generic live mirror; disqualified here as the engine |
| Lsyncd custom action invoking existing mirror | Authority remains in the Python program | Can aggregate events and spawn custom binaries; custom action behavior and exit-code policy must be authored in Lua | Preserved if it invokes the current program | Possible, but requires a custom Lua event layer to reduce per-path events to a safe whole-tree run | Additional Lua/C daemon and custom configuration; upstream maintainer warning remains | Viable, but no advantage over Watchexec for this use |
| Syncthing | Send-only and receive-only folder modes exist, but authority is cluster/device state rather than a simple local source-to-destination copy | Filesystem watcher, accumulated-event delay, maximum delay, and periodic rescans are built in | Receiver-side file versioning can archive replacements and deletions received from another device | Does not invoke or preserve the guarded Python contract; introduces its own index/database, marker and temporary files, device identity, and conflict semantics | Highly active and mature, with frequent releases and shipped systemd examples; however, official docs say it is not designed to sync two folders on the same system | **Disqualified for this local mirror** |

### Lsyncd details and disqualifiers

Lsyncd is the closest purpose-built one-way mirror. Its official description says it watches local directory trees with inotify or FSEvents, aggregates changes for a few seconds, and normally spawns rsync; it is explicitly designed for a slowly changing source mirrored into a less-secure destination ([official repository](https://github.com/lsyncd/lsyncd#description)). Its documented `default.rsync` mode performs an initial whole-tree rsync, then sends filtered batches. It deletes target-only content by default, offers `delete=false`, `startup`, and `running` alternatives, exposes checksum, backup, and backup-directory rsync options, and supports configurable delay and process limits ([official default configuration](https://lsyncd.github.io/lsyncd/manual/config/layer4/)).

That makes Lsyncd functionally suitable for an ordinary one-way mirror, but it is not a drop-in implementation of this mirror's guardrails. Direct `default.rsync` would perform consequential destination changes before the current identity, compatibility, and required-content validations. A static `backup_dir` also lacks the current per-attempt timestamped recovery grouping unless extra custom logic is added. Lsyncd can call custom programs and associate exit-code policies with events ([official custom-action documentation](https://lsyncd.github.io/lsyncd/manual/config/layer3/)), but doing so turns it into a more complex watcher for the existing Python program. Its repository currently carries the explicit notice “Needs new maintainer. Up for adoption,” which is a material maintenance disqualifier for a new personal-infrastructure dependency ([official repository](https://github.com/lsyncd/lsyncd#lsyncd----live-syncing-mirror-daemon)).

**Disqualifier:** do not replace the guarded engine with Lsyncd. Consider it only if Watchexec proves unreliable in a real WSL smoke test and the custom-action configuration is exercised against missed events, overlapping changes, nonzero child exits, restarts, and destination mount replacement.

### Syncthing details and disqualifiers

Syncthing has the richest long-running synchronization machinery. A send-only folder ignores incoming cluster changes and can explicitly override other devices, including overwriting changed files and deleting files absent from the reference host; receive-only mode applies cluster changes without redistributing local destination edits ([official folder-type documentation](https://docs.syncthing.net/users/foldertypes.html)). Its configuration includes a filesystem watcher, an accumulation delay, a maximum delay for continuously changing files, and a periodic rescan interval ([official configuration reference](https://docs.syncthing.net/users/config.html)). Receiver-side versioning can archive files replaced or deleted by a remote device, though it does not archive edits made locally on that receiver ([official versioning documentation](https://docs.syncthing.net/users/versioning.html)). The release history shows sustained, frequent maintenance through 2026 ([official releases documentation](https://docs.syncthing.net/users/releases.html)).

Those strengths target a different topology. Syncthing's own FAQ says it is **not designed to synchronize two folders on the same system**, calls that use wasteful, and recommends rsync or Unison instead ([official FAQ, section 3.7](https://docs.syncthing.net/pdf/FAQ.pdf#page=15)). Making WSL and Windows separate peers would mean running and securing two Syncthing instances, maintaining device/folder identity and indexes, and accepting marker files such as `.stfolder`; it still would not execute the existing validation and read-back protocol. Its documentation also warns that synchronization is not itself an ideal backup because modifications and deletions propagate, even when versioning is available ([official FAQ, section 3.10](https://docs.syncthing.net/pdf/FAQ.pdf#page=16)).

**Disqualifier:** do not use Syncthing for this same-machine WSL-ext4-to-mounted-NTFS mirror. Reconsider it only if the requirement becomes actual cross-device synchronization and its device model becomes useful rather than overhead.

### WSL and service behavior

All WSL-side candidates share the same lifecycle constraint. Microsoft documents that WSL supports `systemd`, but also states that systemd services do not keep a WSL instance alive ([Microsoft WSL systemd documentation](https://learn.microsoft.com/en-us/windows/wsl/systemd)). Thus neither Watchexec nor Lsyncd can provide a Windows-always-on watcher from inside a stopped WSL distribution. They resume only when the distribution and its user service manager run. Microsoft also recommends keeping Linux-tool working files in the Linux filesystem rather than `/mnt/c` for performance, which supports retaining the WSL vault as authoritative and touching NTFS only during mirror operations ([Microsoft filesystem guidance](https://learn.microsoft.com/en-us/windows/wsl/filesystems)).

The event-driven change should therefore be treated as a latency optimization,
not as a stronger source of truth. The guarded full-tree comparison remains the
reliability mechanism. The adopted design uses Watchexec 2.7.1 for source events
and a fixed hourly forced reconciliation for missed events and destination drift.
