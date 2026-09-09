# LeeHaRin Project

This is the shared project workspace for the LeeHaRin personal-agent system.

- `LeeHaRin/` is the canonical Obsidian vault and the only subtree mirrored to
  the Windows/Google Drive view.
- Capability source, agent configuration, and repository metadata stay outside
  `LeeHaRin/`.
- Read `AGENTS.md` before working here. The mirror's controls and recovery path
  are documented in `Windows Mirror.md`.

The authoritative working copy is `/home/tylerhyun/leeharin`; do not edit the
Windows mirror directly.

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
`x` to stop its current run, `s` to enable or pause its schedule, `l` or
`Enter` to inspect logs, `e` to edit its definition, `R` to refresh, and `q` to
close the pane. Run and schedule changes require confirmation. The pane reports
schedule and execution separately, such as `SCHEDULED · IDLE` or
`PAUSED · RUNNING`.

### Common routines

- Find the feedback note: `Space e`, `/`, type `agentic_nvim_feedback`, then
  `Enter`.
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
- Manage routines: `Space aj` opens the bottom pane. The first predefined job
  is the existing LeeHaRin Windows mirror; future agent jobs can use the same
  systemd-backed interface without requiring Neovim to remain open.

Neo-tree, its icon support, and its two required libraries are installed as
native packages under `~/.local/share/nvim/site/pack/neo-tree/start/`.
Graphical Neovim clients use a 14-point JetBrainsMono Nerd Font with two pixels
of extra line spacing. Terminal Neovim cannot control font face, size, or line
spacing; those settings belong to the terminal application's profile.
