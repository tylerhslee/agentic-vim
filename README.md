# Agentic Vim

An independent Neovim distribution evolving toward a provider-neutral,
Neovim-owned orchestration harness on top of
[Agentic.nvim](https://github.com/carlos-algms/agentic.nvim). This is not an
official Agentic.nvim or Neovim project and is not endorsed by either upstream
project.

The repository captures the editor configuration, exact plugin revisions, a
modified Agentic.nvim extension, and provider versions. Credentials, sessions,
caches, and machine-local data are never committed. Agentic.nvim was created by
Carlos Gomes and is used and modified under its MIT License; see
[Third-party notices](THIRD_PARTY_NOTICES.md).

Today, Agentic Vim provides isolated Neovim packaging and ordinary agent
sessions; it can also display provider-originated subagent telemetry when a
provider emits it. The planned harness will make Neovim own capability planning,
portable worker sessions, workspace isolation, single-writer integration,
adversarial review, and verification. Those planned features are not yet
implemented. See the
[orchestration architecture](docs/architecture/orchestration-harness.md) and
[upstream strategy](docs/architecture/upstream-strategy.md).

## Fresh machine setup

The installer supports macOS and Linux on Apple Silicon/ARM64 and x86-64. It
downloads verified, pinned builds of Neovim 0.12.5 and Node.js 22.22.2, installs
the exact plugin and provider versions, compiles Tree-sitter parsers locally,
and links this repository's `nvim/` directory as an isolated configuration.
It installs `~/.local/bin/nvim` as the launcher while leaving `~/.config/nvim`
and ordinary Neovim data untouched. It also installs JetBrainsMono Nerd Font
for the current user account.

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

The credential wizard follows the [official Codex authentication
flow](https://developers.openai.com/codex/auth/): either ChatGPT browser sign-in
or an OpenAI API key. The key is passed directly to
`codex login --with-api-key`; it is not saved in this repository or a `.env`
file. API-key usage is billed through the OpenAI Platform account, while
ChatGPT sign-in uses eligible subscription access.

Run `./scripts/install.sh --dry-run` to preview the installation. If
`~/.config/agentic-vim`, `~/.local/bin/nvim`, or the isolated data
directory already conflicts, the installer stops. Re-run with `--force` to move
conflicts into a timestamped directory under
`~/.local/state/agentic-vim/backups/` before replacing it.

The installer does not replace `~/.codex/config.toml`. Agentic.nvim and its
managed provider use the user's normal Codex authentication and settings, so
review those settings before granting an agent write or command-execution
access. To restore a replaced Agentic Vim file, move it out of the timestamped
backup directory and back to its original path.

The installer also adds `~/.local/bin` to `.zshrc` or `.bashrc` when necessary.
Run `nvim` in your operating system's terminal; file arguments work as usual:
`nvim README.md`. This launcher selects the isolated Agentic Vim configuration;
it does not read or replace `~/.config/nvim`. Select **JetBrainsMono Nerd Font
Mono** at **14pt** in the terminal's font settings, with two pixels of extra
line spacing if supported.
Installing a font does not select it in an existing terminal window; Neovim's
`guifont` only affects graphical clients.

Neovim detects terminal color support and uses the Macchiato theme, with a
matching 256-color fallback when RGB colors are unavailable. Color fidelity
depends on the terminal, so approximate colors are expected. For
matching space outside the Neovim editor, set your terminal profile's background
to `#202334` and foreground to `#bdc6e5`. Profile settings remain under your
control.

### What is pinned

- Neovim 0.12.5 and Node.js 22.22.2, downloaded from their official releases
  and SHA-256 verified.
- JetBrainsMono Nerd Font 3.5.1, matching the current host's four Mono faces.
- Codex CLI 0.153.4 and `@agentclientprotocol/codex-acp` 1.10.0 through
  `provider/package-lock.json`; Tree-sitter CLI 0.27.0 from its checksum-verified
  official release binary.
- Every native Neovim plugin at the commit in `nvim/plugins.lock`.
- Maintained patches for the Agent HUD and filesystem-tree churn fixes, each
  checksum-verified before and after application to its pinned plugin base.

To update an existing clone, pull changes and rerun the installer. Re-running
the same revision is idempotent.

### Coding-agent onboarding

Repository instructions live in `AGENTS.md`. Claude Code loads `CLAUDE.md`,
which imports that canonical guide so Claude and other coding agents receive the
same capability-oriented orchestration, specialist review, project boundaries,
patch workflow, and verification commands. Run
`bash tests/agent-onboarding.sh` to check the onboarding contract without
authentication or a billable agent request. After authenticating Claude Code,
run `bash tests/agent-onboarding.sh --live` for an opt-in, read-only agent check;
the live form makes a provider request and may count against account usage.

### Platform-specific behavior

The editor experience and keymaps are shared across macOS, Linux, and WSL. The
Routine Jobs pane only exposes the LeeHaRin mirror when its systemd units exist;
on a normal Linux or macOS laptop it opens with no configured jobs. The personal
vault and WSL mirror services are intentionally outside this repository.

For SSH or WSL, select the font on the host that actually displays Neovim. When
using Windows Terminal with WSL, install JetBrainsMono Nerd Font separately on
Windows and select its Mono family in the Windows Terminal profile. Installing
the font inside Linux does not install it on the Windows host. WSLg is not
required to run terminal Neovim.

## Cursor subscription integration

Cursor is available as an optional Agentic provider; Codex remains the default.
Install the official Cursor CLI on each machine, then sign in with the Cursor
account whose subscription you want to use:

```bash
curl -fsSL https://cursor.com/install -o /tmp/cursor-install.sh
bash /tmp/cursor-install.sh
~/.local/bin/cursor-agent login
~/.local/bin/cursor-agent status
```

Restart Neovim, open Agentic with `Space aa`, and use `,l` inside Agentic
(or `Space l` from the editor) to select **Cursor Agent ACP**. Use `,m` to
select an available model. Use the same provider picker to return to Codex.
Provider switching carries over the current conversation; start a new session
with `Space an` if you want a fresh conversation. The existing quota display
continues to show Codex usage, not Cursor usage.

The configuration launches `~/.local/bin/cursor-agent acp` directly, so it
also works when Neovim's inherited PATH does not include `~/.local/bin`.
The Cursor CLI is optional and maintained by Cursor's installer/updater, not
pinned by this repository's main installer. Update it with
`~/.local/bin/cursor-agent update`.

Browser sign-in uses your Cursor account; applicable plan allowances and
usage charges still apply. No Cursor credentials belong in this repository.
This integration provides agent chat and tool-based edits, not Cursor Tab
inline autocomplete. To disconnect the account, run
`~/.local/bin/cursor-agent logout`.

See [Cursor ACP](https://cursor.com/docs/cli/acp) and
[Cursor plans](https://cursor.com/help/account-and-billing/pricing).

## Neovim IDE quick reference

Press `F2` (or `Space F1` in Normal mode) to open the searchable [Agentic NVIM cheatsheet](nvim/doc/agentic-nvim.txt)
in a floating help window without resizing chat. `F2` toggles it from any pane;
`q` or `Esc` closes it from inside. `:AgenticCheatsheet` also opens
it, and `F1` keeps Neovim's built-in help. The session name appears in a slim,
muted header above the chat beside the chat icon (or “New session” before it has
a title); the status bar keeps settings and quota information.

The installer links `~/.config/agentic-vim` to this checkout's `nvim/`
directory. The installed `nvim` launcher sets `NVIM_APPNAME=agentic-vim`, keeping
its configuration, data, state, and cache separate from ordinary Neovim. Lua
configuration edits therefore take effect when Agentic Vim restarts. Changes to
`nvim/plugins.lock`, plugin patches, or `provider/package-lock.json` require
rerunning `bash scripts/install.sh` to update the installed dependencies.

Python uses the installer-managed Pyright 1.1.414 server, while Rust uses
rust-analyzer when it is installed and available on `PATH`. Agentic Vim chooses
between them by filetype and gives both the same completion and navigation
bindings. Python also triggers completion while typing identifiers: `Tab` /
`Shift-Tab` select suggestions, `Enter` accepts, and `Ctrl-Space` requests
completion. Use `gd` for definitions, `K` for documentation, `grr` for
references, `gri` for implementations, `grt` for type definitions, `gO` for
file symbols, and `gW` for workspace symbols.
`Space rn` renames a symbol and `Space ca` opens code actions, when supported
by the server. Files default to four-space indentation and word-boundary wrapping.

In an Agentic prompt, type `$` at the start of the line to open completion for
available Codex skills. Continue typing to filter the list and press `Tab` or
`Enter` to accept a skill.

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
| `Space s` / `,s` | Editor / Agentic | Toggle the session picker in the prompt area |
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
| `:term` / `:terminal` | Command line | Toggle one persistent 15-line terminal across the full bottom of the current tab |
| `:q` | Dedicated terminal, Terminal-Normal mode | Close the pane and terminate its shell |

Toggling the dedicated terminal off keeps its shell alive; toggling it from
another tab moves that same shell there. Terminal commands with arguments, such
as `:terminal git status`, retain Neovim's native behavior. Hiding or closing
the terminal restores the preceding editor and Agentic pane layout.

While editing, parentheses, brackets, braces, and quotes close automatically.
Typing an existing closing character moves over it instead of inserting a
duplicate, and Backspace removes an untouched empty pair together.

Inside Neo-tree, use `j`/`k` to move, `l` or `Enter` to open, `h` to collapse,
`Backspace` to move up, `/` to search the displayed tree, `H` to toggle hidden
and ignored items, and `q` to close. Those items are visible by default. Press
`?` there for the complete command list. The source tabs at the top switch
among files, open buffers, and Git status; `<` and `>` move between them.
The tree stays 34 columns wide and never wraps entries. When a long filename is
selected, it pauses briefly, scrolls horizontally, and loops so the whole name
remains readable. `!` means unstaged changes; `?` means an untracked file.

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

The session picker replaces the prompt area. Moving the highlight with `j`/`k`
immediately previews that session's actual chat in the chat pane, with its normal
colors and live updates, starting at the latest message. Selecting a session
also scrolls its chat to the latest message. If chat is hidden, opening the
picker restores it first.
Use `Enter` to open the highlighted session's prompt, `e` or
`R` to rename it, and `D` to destroy it after confirmation.
`Tab` switches between the list and transcript; `q`, `Esc`, or `Space s` closes
the picker and opens the highlighted session's prompt. Each session keeps its
own unsent draft. Subagent rows preview their parent session's chat; closing
while inspecting a subagent opens its parent session.

The normal chat buffer continues to follow incoming messages. The picker has no
prompt input. Nested subagents remain visible as a status tree, but browsing
them does not replace the chat buffer.

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
- The single global bottom statusline has colored editor and agent sections
  aligned with the chat column; Neo-tree shares the editor section. The focused
  editor section shows editor mode, filetype and cursor position. The agent
  section always shows model, effort, agent mode, and a shortened session title
  with its session number; quota appears when space allows. Panel header boxes
  are hidden. Icons mark files, unsaved changes and diagnostics. When
  chat is stacked above/below the editor, the bar divides evenly. Customize the
  layout and colors in `nvim/lua/statusbar.lua`.
- Check usage: the bottom statusline updates from
  Codex's live ChatGPT quota notifications; `Space au` requests an immediate
  refresh. Read the current chat's token/context figures in its Agentic header.
  Type `/status` in the prompt for the provider's full account and session
  report. No separate AgentTally or ccusage plugin is installed.
- Manage routines: `Space aj` opens the bottom pane. On the original WSL host,
  it detects the LeeHaRin mirror's systemd units. Other machines show no jobs.

Plugins are installed in the isolated native package root
`~/.local/share/agentic-vim/nvim-site/pack/agentic-vim/start/` by default.
Graphical Neovim clients use a 14-point JetBrainsMono Nerd Font with two pixels
of extra line spacing. Terminal Neovim cannot control font face, size, or line
spacing; those settings belong to the terminal application's profile.

## Licensing and attribution

The original code in this repository is available under the [MIT License](LICENSE).
The distribution downloads and configures third-party projects under their own
licenses. In particular, the customized chat interface is a patched derivative
of Carlos Gomes's MIT-licensed Agentic.nvim, not an original upstream release.
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance and license
information.
