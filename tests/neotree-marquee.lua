local marquee = require("neotree_marquee")

assert(marquee._window("abcdefgh", 5, 0) == "abcde")
assert(marquee._window("abcdefgh", 5, 2) == "cdefg")
assert(marquee._window("abcdefgh", 5, 8) == "   ab")
assert(vim.fn.strdisplaywidth(marquee._window("abcdefghi", 6, 7)) == 6)
assert(vim.fn.strdisplaywidth(marquee._window("한글파일이름", 6, 1)) == 6)

-- Exercise cursor-driven activation against the real renderer and timer.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
local filename = "abcdefghijklmnopqrstuvwxyz-0123456789-long-filename.txt"
vim.fn.writefile({}, directory .. "/" .. filename)
vim.fn.writefile({}, directory .. "/short.txt")
local command = require("neo-tree.command")
local renderer = require("neo-tree.ui.renderer")
local ok, err = pcall(function()
  command.execute({ action = "focus", source = "filesystem", dir = directory })
  local state = require("neo-tree.sources.manager").get_state("filesystem")
  assert(vim.wait(2000, function()
    return state.tree and state.tree:get_node(directory .. "/" .. filename) ~= nil
  end), "Fixture tree did not load")
  assert(not vim.wo[state.winid].wrap, "Neo-tree enabled line wrapping")
  assert(not vim.wo[state.winid].linebreak, "Neo-tree enabled line-boundary wrapping")
  assert(not vim.wo[state.winid].breakindent, "Neo-tree enabled wrapped-line indentation")
  local function select(name)
    renderer.focus_node(state, directory .. "/" .. name)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.bufnr })
  end
  local function line()
    local row = vim.api.nvim_win_get_cursor(state.winid)[1]
    return vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1]
  end
  select("short.txt")
  renderer.redraw(state)
  select(filename)
  local initial = line()
  assert(vim.wait(2200, function() return line() ~= initial end, 40),
    "Selecting a long filename did not start the marquee")
  select("short.txt")
  vim.wait(250, function() return false end)
  assert(table.concat(vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false), "\n"):find(filename, 1, true),
    "Deselected filename did not return to its full text")
  select(filename)
  initial = line()
  assert(vim.wait(2200, function() return line() ~= initial end, 40),
    "Marquee did not restart after selecting a short filename")
end)
command.execute({ action = "close", source = "filesystem" })
vim.fn.delete(directory, "rf")
assert(ok, err)
