# AGENTS.md

This file defines how coding agents work in this repository. Optimize for a
small, reviewable diff that solves the user's actual problem and leaves the
repository in a verified state.

## Product constraints

- Agentic Vim is an isolated Neovim distribution for Linux, macOS, and WSL on
  x86-64 and ARM64. Preserve that portability unless the task explicitly
  changes it.
- Use the operating system's terminal. Do not install a terminal emulator,
  change a terminal profile, or make behavior depend on emulator-specific
  features.
- Terminal applications control their own fonts. The project may install the
  documented font, but must not attempt to select it in a terminal profile.
- Macchiato colors should be faithful where possible; approximate indexed
  colors are acceptable when true color is unavailable.
- Keep Agentic Vim isolated from the user's ordinary `nvim` configuration,
  data, state, and cache.
- This is an independent distribution built around the pinned
  `carlos-algms/agentic.nvim` upstream project. Preserve its attribution and
  MIT license notice; do not describe the derivative as an upstream release.
- Never commit credentials, session data, caches, machine-local paths, or other
  secrets. Authentication must continue to use the supported provider flows.
- Preserve pinned versions, hashes, lockfiles, and patch provenance. A version
  bump is incomplete until its matching checksums, lockfiles, documentation,
  and verification paths agree.

## Repository map

- `nvim/init.lua` is the configuration entry point.
- `nvim/lua/` contains the editor, UI, LSP, usage, and routine-job modules.
- `nvim/doc/agentic-nvim.txt` is the in-editor help and keymap reference.
- `nvim/plugins.lock` pins native Neovim plugins.
- `patches/` contains checksum-pinned customizations to pinned plugin bases.
- `provider/package.json` and `provider/package-lock.json` pin provider tools.
- `scripts/install.sh` owns installation, upgrades, isolation, and platform
  behavior; `scripts/setup-credentials.sh` owns the authentication wizard.
- `scripts/nvim-install-check.lua` is the installed-runtime health check.
- `tests/` contains repository-level shell test entry points.
- `docs/architecture/` contains the harness contract and upstream strategy.
- `README.md` is the user-facing installation and operation contract.

## Operating model

Use an orchestrator-worker model for non-trivial work. The primary agent is the
orchestrator and remains accountable for the whole result: understanding the
request, defining acceptance criteria, planning, assigning work, integrating
changes, resolving conflicts, commissioning independent review, running final
verification, and reporting one cohesive outcome. Delegation transfers
execution, not ownership of correctness or product decisions.

### Execution plan

Inspect the repository before planning. For substantial work, maintain a
capability map with these fields:

| ID | Capability | Includes | Excludes | Interfaces | Dependencies | Exclusive write ownership | Read dependencies | Specialty | Acceptance criteria | Verification | Integration seams | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

Optimize the map for mutually exclusive and collectively exhaustive (MECE)
capability ownership, not for a timeline. Dependencies only determine runnable
waves. Each row must describe an objectively testable deliverable with explicit
semantic and filesystem boundaries. Reject a plan before delegation when
capabilities are missing or duplicated, write paths overlap, shared ownership
is ambiguous, interfaces are incomplete, or a row cannot be verified
independently. Keep shared and cross-cutting files with the orchestrator or one
designated integration owner. Combine scopes that cannot be separated cleanly.

### When to delegate

Delegate when there are at least two independent, substantial workstreams and
parallel execution is likely to save more time than coordination costs. Good
worker tasks include:

- independent investigation of separate subsystems;
- implementation in disjoint file sets;
- focused test design or documentation review alongside implementation; and
- reproduction of a bug on a separate, read-only path.

Do not delegate a trivial task, a single tightly coupled edit, or work whose
result the orchestrator cannot independently validate. Use as much concurrency
as the available harness safely supports when assignments are truly
independent; otherwise use ordered waves. The orchestrator should continue
useful integration or analysis work while workers run. Workers must not create
further workers unless their assignment explicitly permits it.

### Worker assignment contract

Every assignment must state:

1. the objective and expected deliverable;
2. dependencies already satisfied, relevant context, and known constraints;
3. exact file or subsystem ownership and prohibited scope expansion;
4. acceptance criteria and commands to run;
5. whether edits are allowed or the task is read-only; and
6. the required return format: findings, files changed, verification, and any
   residual risks.

Workers inspect before editing, stay within their ownership boundary, preserve
unrelated user changes, and never revert another worker's work. A worker that
finds necessary out-of-scope work reports it instead of expanding scope. For
shared or cross-cutting files, assign a single owner or keep integration with
the orchestrator.

When the execution harness supports isolation, writing workers use isolated
workspaces created from one frozen baseline. Otherwise workers remain read-only
and return findings or patch proposals. Only the integration phase may modify
the canonical working tree. Detect canonical drift before applying results and
never automatically stash, reset, or discard user changes.

### Integration protocol

- Start with `git status --short` and relevant diffs. Treat all pre-existing
  modifications and untracked files as user-owned.
- Build a small task graph before delegation. Parallelize only nodes without
  write conflicts or unresolved dependencies.
- Give workers enough context to be autonomous, but make assignments narrow
  enough that completion is objectively testable.
- Review worker output and the actual diff; do not accept a completion claim
  without inspecting it.
- Integrate incrementally. Reconcile behavior, naming, docs, tests, lockfiles,
  and generated artifacts before running the repository-wide checks.
- Review the combined result adversarially: try to disprove that it satisfies
  the request. Look for missed requirements, incompatible interfaces,
  duplicated behavior, inconsistent error handling, security or state bugs,
  portability regressions, stale artifacts, and accidental scope growth.
- If worker results disagree, reproduce the evidence and choose based on the
  repository contract and observed behavior, not consensus.
- The orchestrator alone presents the final answer and clearly distinguishes
  verified facts from assumptions or checks that could not be run.

### Specialist code review

After integrating material code changes, assign a fresh read-only reviewer for
each programming language or technical domain materially changed. The reviewer
must be fluent in that language and ecosystem and must inspect the original
request, acceptance criteria, integrated diff, applicable instructions, and
test output. Ask the reviewer to search for defects rather than confirm prior
claims.

Review findings must be ordered by severity and include a file and line,
concrete failure mode, supporting evidence, and the smallest reasonable fix.
Avoid style-only findings unless they affect correctness, clarity,
maintainability, or established conventions. The orchestrator adjudicates every
finding, applies or delegates corrections, and reruns affected checks. A
separate reviewer may be skipped for tiny or documentation-only changes, but
the orchestrator must still inspect the final diff.

## Implementation workflow

1. Read the nearest instructions and the relevant implementation, tests, and
   documentation before changing code.
2. Restate the behavioral goal and identify the smallest coherent change.
3. Search with `rg`/`rg --files`; follow existing naming and structure.
4. Add or update the narrowest useful regression check when behavior changes.
5. Implement without broad cleanup, unrelated refactors, or speculative
   abstractions.
6. Review the diff for accidental scope growth, portability regressions,
   secrets, stale docs, and inconsistent pins.
7. Run the strongest applicable verification from the ladder below.
8. Report the outcome, changed files, tests run, and any remaining limitation.

Ask the user only when a missing decision would materially change behavior or
scope. Otherwise, make the most conservative reversible assumption, state it
when relevant, and continue.

## Coding standards

### Shell

- Target Bash and keep scripts compatible with the supported Linux and macOS
  environments.
- Use `set -euo pipefail` in executable Bash scripts unless a documented reason
  requires different behavior.
- Quote expansions, use arrays where word splitting matters, and validate
  platform, architecture, paths, and downloaded checksums before mutation.
- Keep installation reruns idempotent. Inspect targets before replacement and
  preserve the existing backup behavior for user-owned paths.
- Use temporary directories with cleanup traps. Never log secret values.

### Lua and Neovim

- Keep modules focused and return a module table where the surrounding code
  follows that pattern.
- Prefer Neovim APIs over shelling out. When external processes are necessary,
  handle missing executables, non-zero exits, timeouts, and cleanup.
- Avoid global state unless it is an intentional Neovim integration point.
- Preserve headless startup and both true-color and 256-color behavior.
- Keymap changes must be reflected in both `README.md` and
  `nvim/doc/agentic-nvim.txt` when they affect users.

### Dependencies and patches

- Do not hand-edit `provider/package-lock.json` independently of
  `provider/package.json`; regenerate it with the project's package manager.
- Keep `nvim/plugins.lock` deterministic and review every changed revision.
- When changing a plugin derivative, keep its patch, pinned base, lockfile
  checksums, and third-party notices mutually consistent.
- Do not introduce an unpinned network download into installation paths.

## Verification ladder

Run checks in proportion to the change, starting with the fastest relevant
ones. A check that cannot run because a prerequisite is absent should be
reported, not silently treated as passing.

```bash
# Review scope and whitespace errors.
git diff --check
git status --short

# Shell syntax for project scripts and tests.
bash -n scripts/*.sh tests/*.sh

# Safe installer control-flow and platform preview.
bash scripts/install.sh --dry-run

# Cross-agent metadata, Claude import, attribution, and isolated install contract.
bash tests/agent-onboarding.sh

# Self-contained install-check scenarios; requires Neovim 0.12.5-compatible nvim.
bash tests/install-check.sh

# Installed plugin, palette, reload, and pseudo-terminal checks; requires the
# isolated Agentic Vim installation and its pinned plugins.
bash tests/terminal-colors.sh
```

For a Lua-only change, also start Agentic Vim headlessly with usage polling
disabled when the installed runtime is available:

```bash
NVIM_CODEX_USAGE_DISABLED=1 nvim --headless -i NONE '+qa'
```

The optional `bash tests/agent-onboarding.sh --live` check makes a real Claude
request. Run it only when a user explicitly requests the live check and Claude
Code authentication is available; never include it in unattended CI.

Installation changes deserve at least syntax validation, dry-run coverage, and
the install-check suite. UI, color, or startup changes deserve the installed
runtime checks. Documentation-only changes still require `git diff --check` and
verification that commands, paths, versions, and keymaps match the code.

## Definition of done

A task is done only when the requested behavior is implemented, the diff is
cohesive and preserves unrelated work, relevant documentation and pins agree,
applicable checks pass, and unverified risks are stated plainly. Do not claim
success based only on code inspection when an executable verification path was
available.
