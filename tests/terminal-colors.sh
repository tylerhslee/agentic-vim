#!/usr/bin/env bash
# Exercise the installed plugins with the repository's actual startup config.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agentic-colors-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
NVIM=${NVIM:-nvim}
export NVIM NVIM_APPNAME=agentic-vim
export XDG_CONFIG_HOME="$TEST_DIR/config"
export XDG_STATE_HOME="$TEST_DIR/state" XDG_CACHE_HOME="$TEST_DIR/cache"
export NVIM_LOG_FILE="$TEST_DIR/nvim.log" NVIM_CODEX_USAGE_DISABLED=1
export AGENTIC_COLOR_TEST="$TEST_DIR/check.lua"
cat > "$AGENTIC_COLOR_TEST" <<'LUA'
local ok, err = pcall(function()
  assert(vim.o.termguicolors == (vim.env.EXPECT_RGB == "1"), "Config overrode terminal color mode")
  assert(vim.fn.maparg("jj", "i") == "<Esc>", "Insert-mode jj mapping is missing")
  assert(vim.fn.maparg("<leader>aa", "n") ~= "", "Agentic chat mapping is missing")
  assert(type(require("agentic").toggle) == "function", "Agentic chat module is unavailable")
  local registry = require("agentic.session_registry")
  local header = require("agentic.config").headers.chat
  local state = {}
  local saved_sessions = registry.sessions
  local session = { session_state = state, chat_history = { title = "Fix 50%\nregression" } }
  registry.sessions = { [1] = session }
  local parts = { title = "󰻞 Agentic Chat" }
  assert(header(parts, state) == "󰻞 Fix 50%% regression", "Chat header lost session title or escaping")
  session.chat_history.title = "Renamed session"
  assert(header(parts, state) == "󰻞 Renamed session", "Chat header retained a stale title")
  assert(header(parts, {}) == "󰻞 New session", "Chat header used another session's title")
  session.chat_history.title = ""
  assert(header(parts, state) == "󰻞 New session", "Untitled chat fallback changed")
  registry.sessions = saved_sessions
  assert(vim.g.colors_name == "catppuccin-macchiato")
  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  assert(normal.bg == 0x202334 and normal.fg == 0xbdc6e5, "RGB palette changed")
  assert(normal.ctermbg == 235 and normal.ctermfg, "Missing indexed background/foreground")
  local string_hl = vim.api.nvim_get_hl(0, { name = "String", link = false })
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  assert(string_hl.ctermfg and comment.ctermfg and string_hl.ctermfg ~= comment.ctermfg,
    "Syntax colors lost differentiation")
  assert(comment.italic, "Highlight style lost")
  vim.api.nvim_set_hl(0, "AgenticColorTestLink", { link = "String" })
  require("terminal_colors").apply()
  assert(vim.api.nvim_get_hl(0, { name = "AgenticColorTestLink" }).link == "String")
  vim.cmd("colorscheme catppuccin-macchiato")
  assert(vim.o.termguicolors == (vim.env.EXPECT_RGB == "1"), "Theme reload changed terminal color mode")
  assert(vim.api.nvim_get_hl(0, { name = "Normal" }).ctermbg == 235, "Reload lost fallback")
  dofile(vim.env.AGENTIC_CHEATSHEET_TEST)
  dofile(vim.env.AGENTIC_SESSION_PREVIEW_TEST)
  dofile(vim.env.AGENTIC_MARQUEE_TEST)
end)
if vim.env.AGENTIC_COLOR_RESULT then
  vim.fn.writefile({ ok and "verified" or tostring(err) }, vim.env.AGENTIC_COLOR_RESULT)
end
if not ok then print(err); vim.cmd("cquit 1") end
LUA
export AGENTIC_CHEATSHEET_TEST="$ROOT/tests/cheatsheet.lua"
export AGENTIC_SESSION_PREVIEW_TEST="$ROOT/tests/session-preview.lua"
export AGENTIC_MARQUEE_TEST="$ROOT/tests/neotree-marquee.lua"
for mode in notermguicolors termguicolors; do
  rgb=0
  [[ "$mode" != termguicolors ]] || rgb=1
  EXPECT_RGB="$rgb" "$NVIM" --headless -i NONE -u "$ROOT/nvim/init.lua" \
    --cmd "set runtimepath^=$ROOT/nvim" \
    --cmd "set $mode" '+lua dofile(vim.env.AGENTIC_COLOR_TEST)' +qa
  printf 'PASS: %s palette, styles, links, and reload\n' "$mode"
done

# A headless process never negotiates TUI color support. Exercise an actual
# pseudo-terminal after startup, without requiring a particular terminal app.
python3 - "$ROOT" <<'PY'
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import termios
import time

root = sys.argv[1]
cases = [
    ("truecolor", None, True),
    ("truecolor", "notermguicolors", False),
    ("24bit", None, True),
    ("", None, False),
    ("", "termguicolors", True),
]
for color, override, expected in cases:
    label = f"PTY COLORTERM={color or '(empty)'} override={override or '(unset)'}"
    env = os.environ.copy()
    # Do not inherit emulator-specific hints from the terminal running tests.
    for key in ("TERM_PROGRAM", "TERM_PROGRAM_VERSION", "VTE_VERSION",
                "KONSOLE_VERSION", "KONSOLE_PROFILE_NAME", "TMUX", "STY"):
        env.pop(key, None)
    env.update(TERM="xterm-256color", COLORTERM=color, EXPECT_RGB=str(int(expected)))
    result = Path(env["AGENTIC_COLOR_TEST"]).with_name("pty-result")
    if result.exists():
        result.unlink()
    env["AGENTIC_COLOR_RESULT"] = str(result)
    command = [env["NVIM"], "-i", "NONE", "-u", f"{root}/nvim/init.lua",
               "--cmd", f"set runtimepath^={root}/nvim"]
    if override:
        command += ["--cmd", f"set {override}"]
    command += ["+lua vim.defer_fn(function() dofile(vim.env.AGENTIC_COLOR_TEST); vim.cmd('qa!') end, 300)"]
    master, slave = pty.openpty()
    process = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
        process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave,
                                   env=env, start_new_session=True)
        os.close(slave)
        slave = None
        deadline = time.monotonic() + 15
        while process.poll() is None:
            if time.monotonic() > deadline:
                raise RuntimeError(f"{label}: Neovim timed out")
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not chunk:
                    break
        status = process.wait(timeout=2)
        report = result.read_text().strip() if result.exists() else "Verification did not run"
        if status or report != "verified":
            raise RuntimeError(f"{label}: Neovim exited {status}: {report}")
        print(f"PASS: {label}, palette, and reload", flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        if slave is not None:
            os.close(slave)
PY
