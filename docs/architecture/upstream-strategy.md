# Agentic.nvim upstream strategy

Agentic Vim currently installs Agentic.nvim from
`https://github.com/carlos-algms/agentic.nvim.git` at commit
`81628c1dc07edadd1c2c3c27d8dbcb424da1dea0` and applies the verified
`patches/agentic-hud.patch` overlay. `nvim/plugins.lock` is the authoritative
machine-readable record for that source, base revision, and patch hashes. The
same generic lock schema also records maintained compatibility patches for
other pinned plugins.

That overlay is transitional. The orchestration work needs stable, generic ACP
session hooks and an independently maintained release history. Once a public
fork repository exists, the project will pin an exact commit from that fork and
retire the patch as a competing source of truth. A fork URL must not be added to
the lockfile until the repository and pinned commit actually exist.

## Ownership boundary

The maintained Agentic.nvim derivative owns only generally useful session and
UI infrastructure. The `agentic_harness` extension owns orchestration policy
and remains separately testable. The boundary is defined in
`orchestration-harness.md`.

## Fork migration checklist

The migration is one coordinated change:

1. Create the maintained fork with Agentic.nvim's MIT license and Carlos Gomes's
   copyright notice intact.
2. Add `nvim/agentic-source.lock` as the authoritative machine-readable record
   of the fork URL and commit plus the upstream URL and base commit. Retain the
   same provenance in the fork history and release notes.
3. Run the upstream test suite plus Agentic Vim's installed-runtime checks.
4. Change the Agentic.nvim row in `nvim/plugins.lock` to the fork URL and an
   immutable commit.
5. Clear the Agentic.nvim row's patch path and hashes; the installer's generic
   verified-patch support remains available to other pinned plugins.
6. Update `THIRD_PARTY_NOTICES.md`, the README, and verification checks so
   `nvim/agentic-source.lock`, `nvim/plugins.lock`, the fork URL, upstream base,
   installed commit, and attribution agree.
7. Confirm a clean installation contains an unmodified checkout of the pinned
   fork commit and retain the previous pin as the rollback target.

Do not ship both a fork commit and an additional product patch unless a temporary
exception records why both are required and how each source is verified.

## Ongoing updates

Upstream updates are deliberate compatibility changes, not floating upgrades.
For each update, record the previous fork commit, new upstream base, resulting
fork commit, and user-visible changes. Review ACP types, session lifecycle,
prompt transport, permission handling, cancellation, and UI events before
running the full distribution verification ladder. Pins, notices, documentation,
and rollback instructions must land together.
