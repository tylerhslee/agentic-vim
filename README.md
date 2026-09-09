# Agentic Vim

A reproducible Neovim environment centered on Agentic.nvim and Codex. The
repository captures the live editor configuration, exact plugin revisions, the
custom Agent HUD overlay, provider versions, and the user's portable Codex
defaults. Credentials, sessions, caches, and the personal LeeHaRin vault are
never committed.

## Fresh laptop setup

The installer supports macOS and Linux on Apple Silicon/ARM64 and x86-64. It
downloads verified, pinned builds of Neovim 0.12.5 and Node.js 22.22.2, installs
the exact plugin and provider versions, compiles Tree-sitter parsers locally,
and links this repository's `nvim/` directory as your Neovim configuration.

Prerequisites are Git, curl, tar, and a C compiler. On a new Mac, install the
Command Line Tools first:

```bash
xcode-select --install
```

Then run:

```bash
git clone https://github.com/tylerhslee/agentic-vim.git ~/agentic-vim
cd ~/agentic-vim
./scripts/install.sh
./scripts/setup-credentials.sh
exec "$SHELL" -l
nvim
```

Because the repository is private, the initial clone requires GitHub
authentication (for example, a GitHub credential manager or an SSH key and the
equivalent SSH clone URL). No other project-specific secret is required.

The credential wizard follows the [official Codex authentication
flow](https://developers.openai.com/codex/auth/): either ChatGPT browser sign-in
or an OpenAI API key. The key is passed directly to
`codex login --with-api-key`; it is not saved in this repository or a `.env`
file. API-key usage is billed through the OpenAI Platform account, while
ChatGPT sign-in uses eligible subscription access.

Run `./scripts/install.sh --dry-run` to preview the installation. If
`~/.config/nvim`, the managed links under `~/.local/bin`, or the isolated plugin
directory already conflicts, the installer stops. Re-run with `--force` to move
each conflict into a timestamped directory under
`~/.local/state/agentic-vim/backups/` before replacing it.

The captured Codex defaults intentionally match this machine: approval policy
`never` with `danger-full-access`. That gives Codex unrestricted local access,
so use this setup only on a machine and in repositories you trust. To restore a
replaced configuration, move the desired item out of the timestamped backup
directory and back to its original path.

The installer also adds `~/.local/bin` to `.zshrc` or `.bashrc` when necessary
and installs the same JetBrainsMono Nerd Font for your user account. Select that
font in your terminal profile to reproduce the icons and typography; terminal
font selection cannot be controlled by Neovim.

### What is pinned

- Neovim 0.12.5 and Node.js 22.22.2, downloaded from their official releases
  and SHA-256 verified.
- JetBrainsMono Nerd Font 3.5.1, matching the current host's four Mono faces.
- Codex CLI 0.153.4 and `@agentclientprotocol/codex-acp` 1.10.0 through
  `provider/package-lock.json`; Tree-sitter CLI 0.27.0 from its checksum-verified
  official release binary.
- Every native Neovim plugin at the commit in `nvim/plugins.lock`.
- The custom Agent HUD as `patches/agentic-hud.patch`, verified before and
  after it is applied to the pinned Agentic.nvim base.

To update an existing clone, pull changes and rerun the installer. Re-running
the same revision is idempotent.

### Platform-specific behavior

The editor experience and keymaps are shared across macOS, Linux, and WSL. The
Routine Jobs pane only exposes the LeeHaRin mirror when its systemd units exist;
on a normal Linux or macOS laptop it opens with no configured jobs. The personal
vault and WSL mirror services are intentionally outside this repository.

## Neovim IDE quick reference

`Space` is the global leader and comma is Agentic's local leader. For example,
`Space e` means press Space, release it, then press `e`. From an ordinary editor
buffer, Agentic commands use `Space`; their comma versions work only while focus
is inside Agentic.

### Everyday commands

| Keys | Where | Action |
|---|---|---|
| `Space e` | Editor | Toggle Neo-tree and reveal the current file |
| `Space E` | Editor | Open/focus Neo-tree at the current file |
| `Space aa` | Editor | Toggle the Agentic chat |
| `Space ac` | Editor or visual selection | Add the current file or selection to Agentic context |
| `Space an` | Editor | Start a new Agentic session |
| `Space ar` | Editor | Restore a provider session |
| `Space al` | Editor | Rotate the Agentic layout |
| `Space ax` | Editor | Stop the active generation |
| `Space au` | Editor | Refresh the live ChatGPT Codex quota display |
| `Space aj` | Editor | Toggle the Routine Jobs management pane |
| `Space aq` | Editor | Close Agentic and restore a wide editor |
| `Space s` / `,s` | Editor / Agentic | Open the session HUD/picker |
| `Space ]` / `Space [` | Editor | Move to the next / previous session |
| `,]` / `,[` | Agentic | Move to the next / previous session |
| `Space D` / `,D` | Editor / Agentic | Destroy the current session |
| `Space m` / `Space l` | Editor | Select model / provider |
| `,m` / `,l` | Agentic | Select model / provider |
| `Space t` / `Space o` | Editor | Select thought level / open Agentic options |
| `,t` / `,o` | Agentic | Select thought level / open Agentic options |
| `Shift-Tab` | Agentic | Change approval mode |
| `Enter` or `Ctrl-s` | Agentic prompt | Submit the prompt |
| `jj` | Insert mode | Return to Normal mode |
| `Esc` | Terminal mode | Enter Terminal-Normal mode to navigate terminal output like text |

Inside Neo-tree, use `j`/`k` to move, `l` or `Enter` to open, `h` to collapse,
`Backspace` to move up, `/` to search the displayed tree, `H` to toggle hidden
and ignored items, and `q` to close. Those items are visible by default. Press
`?` there for the complete command list. The source tabs at the top switch
among files, open buffers, and Git status; `<` and `>` move between them.

In Neo-tree's **Buffers** source, the entries are files currently loaded in
Neovim, grouped by directory. `#7` is buffer number 7, `[+]` means the buffer
has unsaved changes, `[No Name]` is a buffer without a filename, and symbols
on the right show diagnostics or Git status.

| Keys | Action in the Buffers source |
|---|---|
| `Enter` or `l` | Open the buffer in the editor window |
| `S` / `s` | Open in a horizontal / vertical split |
| `t` | Open in a new Neovim tab |
| `d` or `bd` | Close the buffer without deleting its file; refuses unsaved changes |
| `P` | Toggle a floating preview |
| `i` | Show file details |
| `o` | Open the sorting menu |
| `Tab` | Mark or unmark an entry for multi-item file operations |

Inside the Agent HUD, use `j`/`k` to select a session, `Enter` to open it,
`e` or `R` to rename it, and `D` to destroy it after confirmation. `Tab` or
`l` enters the output preview; `Tab` or `h` returns to the session list.

Inside Routine Jobs, use `j`/`k` to select a predefined job, `r` to run it now,
`x` to stop its current run, `s` to enable or pause its automatic triggers, `l` or
`Enter` to inspect logs, `e` to edit its definition, `R` to refresh, and `q` to
close the pane. Run and schedule changes require confirmation. The pane reports
watcher, reconciliation schedule, and execution separately.

### Common routines

- Ask about a whole file: open it from Neo-tree, press `Space ac`, then
  `Space aa` and type the question.
- Ask about a fragment: visually select it, press `Space ac`, then focus the
  Agentic prompt and submit with `Enter`.
- Keep two chats working: `Space an` starts another session; `Space s` shows the
  HUD from the editor, and `Space ]` / `Space [` switches without stopping
  background work. Inside Agentic, use the comma versions.
- Recover an older chat: `Space ar`, type to filter the picker, select the
  session, and press `Enter`.
- Check usage: the bottom statusline updates from Codex's live ChatGPT quota
  notifications; `Space au` requests an immediate refresh. Read the current
  chat's token/context figures in its Agentic header. Type `/status` in the
  prompt for the provider's full account and session report. No separate
  AgentTally or ccusage plugin is installed.
- Manage routines: `Space aj` opens the bottom pane. On the original WSL host,
  it detects the LeeHaRin mirror's systemd units. Other machines show no jobs.

Plugins are installed in the isolated native package root
`~/.local/share/nvim/agentic-vim/nvim-site/pack/agentic-vim/start/` by default.
Graphical Neovim clients use a 14-point JetBrainsMono Nerd Font with two pixels
of extra line spacing. Terminal Neovim cannot control font face, size, or line
spacing; those settings belong to the terminal application's profile.
