# Terminal integration evaluation

## Tactical plan

Intended result: evaluate optional Ghostty and Alacritty support for this
repository's Agentic.nvim workflow, distinguishing terminal-host benefits from
features that require plugin integration. Preserve the current terminal-independent
installation policy unless the user decides otherwise.

1. Inspect the current configuration, pinned plugin, HUD, and terminal handling.
2. Research Ghostty and Alacritty independently against official documentation
   and source, including platform support and integration limitations.
3. Map verified capabilities to concrete user workflows and implementation cost;
   directly verify the claims that determine the recommendation.
4. Have a separate agent challenge the synthesis, resolve findings, and record
   a bounded experiment with acceptance checks and outstanding questions.

Acceptance: primary-source citations, explicit separation of existing behavior
and proposals, no assumed agent-session persistence or notification support,
and a recommendation conditional on relevant user needs. This is research;
no runtime or terminal configuration changes are planned. Recovery consists of
removing this new note; existing working-tree edits are preserved.

## Findings

Evaluated 2026-09-09 against the repository's current working tree and official
documentation. This is an assessment, not a measured terminal comparison.

The use case is credible for **optional host polish and agent attention alerts**.
There is not yet a demonstrated need for a terminal-specific workspace controller.
Keep Agentic sessions, context, permissions, and the HUD in Neovim.

The choice depends on the friction being solved:

| Need | Ghostty | Alacritty | Implication for this project |
|---|---|---|---|
| Appearance and input | Native macOS/Linux host; modern rendering and keyboard protocols | macOS/Linux/Windows/BSD host; configurable appearance and modern keyboard support | Trial the existing configuration first; neither needs an Agentic adapter |
| Notice completion or approval while elsewhere | Documented OSC desktop notifications | Configurable bell command; generic rather than structured agent events | A shared Neovim lifecycle notifier is useful; delivery is an optional backend |
| Shell/log pane beside the editor | Native tabs and splits | Native tabs on macOS; no built-in cross-platform split system | Useful for separate processes, not a replacement for the Agentic HUD |
| Launch and arrange projects | macOS AppleScript automation, currently preview | Unix IPC can create windows and manage configuration | Defer until repeated manual setup justifies platform-specific maintenance |
| Keep agents alive through closing windows/disconnecting | Window restoration is not process survival | IPC is not a detach/reattach service | Evaluate process persistence separately |

Sources: [Ghostty features](https://ghostty.org/docs/features),
[Ghostty OSC 9](https://ghostty.org/docs/vt/osc/9),
[Alacritty project](https://github.com/alacritty/alacritty),
[Alacritty configuration](https://alacritty.org/config-alacritty.html),
[Alacritty IPC](https://alacritty.org/cmd-alacritty-msg.html),
[Ghostty 1.3 release notes](https://ghostty.org/docs/install/release-notes/1-3-0).
The implications column is our assessment.

## What the current setup already provides

Local evidence: `README.md`, `nvim/init.lua`, `nvim/lua/terminal_colors.lua`,
`nvim/plugins.lock`, and `patches/agentic-hud.patch`.

- The README records an OS-terminal preference and user-managed profiles.
  Evaluating alternatives does not establish that this preference has changed.
- Neovim owns the project tree, chat layout, context selection, session navigation,
  and HUD. Separate terminal processes would not automatically share that state.
- The working tree already handles RGB detection and a 256-color fallback.
  Better color fidelity may justify changing hosts, without new plugin code.
- Existing leader mappings do not require advanced keyboard protocols. Modified
  keys can be a later convenience with the current mappings retained.

The referenced LeeHaRin vault notes are absent from this checkout; no vault was
created or modified. Existing uncommitted implementation changes were preserved.

## Highest-value code experiment: attention notifications

Scenario: submit a long turn, switch to another app, and receive one notice when
the agent needs approval or the turn ends. Return to the existing HUD to inspect
the result. A terminal notification need not select the exact session on click;
that is a separate routing feature and is not promised here.

The installed Agentic plugin matches pinned commit
`81628c1dc07edadd1c2c3c27d8dbcb424da1dea0`. Direct inspection of
`lua/agentic/config_default.lua` and `lua/agentic/session_manager.lua` confirms
`hooks.on_prompt_submit`, `hooks.on_response_complete`, and
`hooks.on_request_permission`. Completion passes session identity and a success
flag; the permission hook runs before the approval UI handles the request.
These are real extension points, not hypothetical new upstream APIs.

One limitation was confirmed during independent review: completion sets
`success = err == nil` but omits `response.stopReason`. The message writer
separately recognizes `stopReason == "cancelled"`, so a cancelled turn can still
reach the hook with `success=true`. Start with neutral "turn ended" notices.
Success/cancellation-specific notices require exposing the stop reason or another
verified cancellation signal; the existing completion payload alone is insufficient.

Proposed flow:

```text
Agentic lifecycle hook
  -> attention policy (focus, session, deduplication)
  -> optional notification transport
  -> return to Neovim/HUD for details and any approval
```

Ghostty accepts OSC 9 notifications. Neovim 0.12 provides `nvim_ui_send()` to
write to the host terminal; a clean headless check on this machine confirmed
Neovim 0.12.5 and that the function exists. That checks API availability, not
delivery. [Ghostty protocol](https://ghostty.org/docs/vt/osc/9),
[Neovim API](https://neovim.io/doc/user/api/#nvim_ui_send()).

Alacritty's bell command can invoke a notifier, but any bell can trigger it and
it does not carry structured session data. A platform notification backend could
also serve the existing OS terminal; changing emulators is not a prerequisite.
[Alacritty bell configuration](https://alacritty.org/config-alacritty.html#bell).

Design requirements for a prototype: opt-in delivery; fixed or sanitized text;
no prompts/tool output in desktop notices by default; per-session/turn deduplication;
distinguish failure and cancellation from success; no effect on approval decisions;
no hook errors interrupting agent work. Preserve any existing hook callbacks.
Focus tracking, multiple attached UIs, background sessions, and remote delivery
need explicit tests. Start with app-unfocused delivery; hidden-session notices
while Neovim remains focused are a separate policy choice.

Ghostty shell integration tracks shell commands, so its command-finished feature
cannot infer ACP turn completion inside a still-running Neovim process. An agent
hook is necessary for those semantics. This is an architectural inference from
the plugin and [Ghostty shell integration](https://ghostty.org/docs/features/shell-integration).

## Other potential integrations

**Optional host guidance: low effort.** Record tested font, colors, input, and
clipboard behavior without managing terminal profiles. Check Enter/Ctrl-s,
Shift-Tab, Ctrl-h/j/k/l, multiline paste, Unicode, and resizing with tree/chat/HUD
open. Both terminals support modern keyboard mechanisms, while Neovim negotiates
extended keys; support is not proof every desired chord arrives correctly.
[Neovim TUI](https://neovim.io/doc/user/tui/#tui-input),
[Alacritty changelog](https://raw.githubusercontent.com/alacritty/alacritty/master/CHANGELOG.md),
[Ghostty features](https://ghostty.org/docs/features).

**Project launcher: conditional value, moderate maintenance.** A project window
and adjacent test shell could reduce repeated setup. Ghostty 1.3 AppleScript can
control windows, tabs, splits, and input, but is macOS-only and explicitly preview
with breaking changes expected. Alacritty's documented Unix IPC offers
`create-window`, `config`, and `get-config`, not an Agentic session API. Prefer
explicit process launch and working directories over injecting keystrokes into
whichever terminal happens to have focus.
[Ghostty release notes](https://ghostty.org/docs/install/release-notes/1-3-0),
[Alacritty IPC manual](https://alacritty.org/cmd-alacritty-msg.html).

**Image previews: possible Ghostty-specific benefit, unproven demand.** Kitty
graphics support could support a separate Neovim image-rendering integration.
It does not automatically add image display or model image attachments to
Agentic. No current workflow requirement justifies that scope.
[Ghostty features](https://ghostty.org/docs/features).

**Persistence and performance: separate questions.** Restoring window layout is
not keeping Neovim, buffers, and agent processes alive. Provider session restore
is also distinct. GPU rendering may improve local responsiveness; it does not
speed model generation. No throughput, input-latency, battery, or memory comparison
was measured. Do not select an emulator on an assumed performance win.
[Ghostty window restoration](https://ghostty.org/docs/config/reference#window-save-state),
[Alacritty project](https://github.com/alacritty/alacritty).

## Decision and bounded trial

Keep terminal-independent support as the baseline. If the desired improvement
is a richer macOS/Linux desktop workspace or direct terminal notifications,
Ghostty is a sensible experiment. If the goal is one optional host across Mac,
Linux, and Windows, Alacritty fits that platform requirement. If the only issue
is missed agent completion, prototype the shared notification feature before
requiring either host. These are conditional choices, not an overall ranking.

The open question that determines the next action is the main friction:
appearance/input, missed agent events, multi-project layout, or live-process
persistence. No answer should be inferred from this evaluation request alone.

Suggested acceptance checks for a later trial:

1. Run the same project and existing Neovim configuration in the current host and
   candidate, at comparable font size/window dimensions. Record actual terminal
   versions and whether SSH or a multiplexer is involved.
2. Verify the key/paste/rendering cases above, context selection, session switching,
   and live HUD output. Record concrete improvement or regression, not general
   claims about speed. Keep the terminal fallback working.
3. If testing notifications, cover successful and failed turns, cancellation,
   repeated approval requests, two concurrent sessions, focus changes, denied
   OS notification permission, and unavailable transports. The notice must not
   approve anything or block chat; no claim of completed work for cancellation.
4. Test SSH/multiplexer notification delivery separately if that is a required
   workflow. Do not extrapolate from local desktop results. Ghostty's newer
   `+ssh` wrapper is documented as tip/future 1.4, not part of 1.3.x.
   [Ghostty SSH version caveat](https://ghostty.org/docs/features/ssh).
5. Keep an adapter only if it resolves the stated friction. Roll back a trial by
   disabling its opt-in hook/backend and returning to the existing host.

Research checks completed: parallel primary-source investigations, direct
inspection of the pinned lifecycle call sites, clean Neovim API availability
check, direct verification of notification, macOS tab, and automation claims,
and independent adversarial review. The review's cancellation-payload finding
was checked directly against the message writer and incorporated above.
No terminal was installed, no profile or runtime configuration changed, and no
desktop notification or emulator UI behavior was tested.

## Local Ghostty trial

The user subsequently requested installation on this Mac. Ghostty 1.3.1 was
installed through Homebrew, with a validated user configuration at
`~/.config/ghostty/config`: JetBrainsMono Nerd Font Mono, 14pt, two extra pixels
of cell height, and matching Macchiato colors. The installed app resolves both
ordinary text and a sampled Nerd Font icon to that font family.

A live Neovim launch verified Agentic loading, RGB output, and no startup errors.
That check exposed a theme-startup bug: restoring the initial false RGB option
suppressed subsequent TUI detection. The fallback now recognizes explicit
`COLORTERM=truecolor`/`24bit` advertisements while retaining user overrides.
Regression coverage exercises real PTY startup and theme reloads. Terminals
identified as RGB solely through terminfo remain outside this narrow fix.

The pre-fix module and test script are backed up under
`~/.local/state/agentic-vim/backups/ghostty-20260909-105551/`.
macOS Terminal remains available; return to it to end the trial. No notification
integration or agent prompts were added. Visual preference, interactive key/paste
behavior, and performance still need hands-on comparison.
