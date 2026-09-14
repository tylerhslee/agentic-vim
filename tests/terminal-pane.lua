local pane = require("terminal_pane")

assert(pane.command_line("term", ":") == "<C-u>TerminalPaneToggle<CR>")
assert(pane.command_line("terminal", ":") == "<C-u>TerminalPaneToggle<CR>")
assert(pane.command_line("terminal printf test", ":") == nil)
assert(pane.command_line("term", "/") == nil)

local original_tab = vim.api.nvim_get_current_tabpage()
vim.cmd("tabnew")
local test_tab = vim.api.nvim_get_current_tabpage()
local ok, err = xpcall(function()
  vim.o.columns = 120
  vim.o.lines = 40
  vim.cmd("vsplit")
  vim.cmd("belowright 5split")
  vim.wo.winfixheight = true
  local fixed_input_win = vim.api.nvim_get_current_win()
  local fixed_input_height = vim.api.nvim_win_get_height(fixed_input_win)
  vim.cmd("wincmd k")
  local flexible_history_win = vim.api.nvim_get_current_win()
  local flexible_history_height = vim.api.nvim_win_get_height(flexible_history_win)
  local layout_heights = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(test_tab)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      layout_heights[win] = vim.api.nvim_win_get_height(win)
    end
  end

  local first = pane.open()
  assert(first and first.bufnr and first.winid and first.job_id, "Terminal did not expose its live state")
  assert(vim.bo[first.bufnr].buftype == "terminal", "Dedicated pane is not a terminal")
  assert(vim.b[first.bufnr].agentic_terminal_pane == true, "Dedicated terminal marker is missing")
  assert(vim.api.nvim_win_get_position(first.winid)[2] == 0, "Terminal is not left-aligned")
  assert(vim.api.nvim_win_get_width(first.winid) == vim.o.columns, "Terminal does not span the editor")
  assert(vim.api.nvim_win_get_height(first.winid) == 15, "Terminal height changed")
  assert(vim.api.nvim_win_get_height(fixed_input_win) == fixed_input_height,
    "Opening the terminal compressed a fixed-height input pane")
  assert(vim.api.nvim_win_get_height(flexible_history_win) < flexible_history_height,
    "Terminal height was not taken from the flexible history pane")
  vim.api.nvim_win_set_height(fixed_input_win, fixed_input_height + 3)
  assert(vim.api.nvim_win_get_height(fixed_input_win) > fixed_input_height,
    "Input-pane resize fixture did not expand")

  pane.toggle()
  assert(not pane.is_open(), "Toggle did not hide the terminal")
  assert(vim.api.nvim_buf_is_valid(first.bufnr), "Toggle destroyed the terminal buffer")
  assert(vim.fn.jobwait({ first.job_id }, 0)[1] == -1, "Toggle killed the shell")
  local layout_restored = vim.wait(1000, function()
    for win, height in pairs(layout_heights) do
      if vim.api.nvim_win_get_height(win) ~= height then return false end
    end
    return true
  end, 20)
  local actual_layout_heights = {}
  for win in pairs(layout_heights) do
    actual_layout_heights[win] = vim.api.nvim_win_get_height(win)
  end
  assert(layout_restored, "Toggle did not restore the pre-terminal window layout: "
    .. vim.inspect({ expected = layout_heights, actual = actual_layout_heights }))

  local reopened = pane.open()
  assert(reopened.bufnr == first.bufnr and reopened.job_id == first.job_id,
    "Reopening did not preserve the shell")

  -- Toggling must still work if another command made the terminal the tab's
  -- only window; Neovim refuses to close a tab's final window.
  vim.cmd("only")
  local float_buf = vim.api.nvim_create_buf(false, true)
  local float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 1,
    height = 1,
    style = "minimal",
  })
  pane.toggle()
  assert(not pane.is_open(), "Toggle did not hide an only-window terminal")
  assert(vim.api.nvim_buf_is_valid(first.bufnr), "Only-window toggle destroyed the terminal buffer")
  assert(vim.fn.jobwait({ first.job_id }, 0)[1] == -1, "Only-window toggle killed the shell")
  vim.api.nvim_win_close(float_win, true)
  reopened = pane.open()
  assert(reopened.bufnr == first.bufnr and reopened.job_id == first.job_id,
    "Only-window toggle did not preserve the shell")

  -- A later bottom pane must not displace the terminal from the outer bottom.
  vim.cmd("botright 5split")
  assert(vim.wait(1000, function()
    local terminal_row = vim.api.nvim_win_get_position(reopened.winid)[1]
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(test_tab)) do
      if win ~= reopened.winid and vim.api.nvim_win_get_config(win).relative == "" then
        local pos = vim.api.nvim_win_get_position(win)
        if pos[1] + vim.api.nvim_win_get_height(win) > terminal_row then return false end
      end
    end
    return vim.api.nvim_win_get_position(reopened.winid)[2] == 0
      and vim.api.nvim_win_get_width(reopened.winid) == vim.o.columns
      and vim.api.nvim_win_get_height(reopened.winid) == 15
  end, 20), "Terminal did not return to the full-width bottom row")

  -- Opening from another tab relocates the single persistent shell.
  vim.cmd("tabnew")
  vim.cmd("belowright 5split")
  vim.wo.winfixheight = true
  vim.cmd("wincmd k")
  local quit_layout_heights = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      quit_layout_heights[win] = vim.api.nvim_win_get_height(win)
    end
  end
  local relocated = pane.toggle()
  assert(relocated and relocated.open, "Terminal did not open in the current tab")
  assert(relocated.bufnr == first.bufnr and relocated.job_id == first.job_id,
    "Moving the terminal between tabs replaced its shell")
  assert(vim.api.nvim_win_get_tabpage(relocated.winid) == vim.api.nvim_get_current_tabpage(),
    "Terminal remained in the previous tab")

  -- Native :q is intentionally destructive, unlike the toggle path.
  vim.api.nvim_set_current_win(relocated.winid)
  vim.cmd("stopinsert")
  vim.cmd("quit")
  local quit_completed = vim.wait(1000, function()
    return not vim.api.nvim_buf_is_valid(first.bufnr)
      and vim.fn.jobwait({ first.job_id }, 0)[1] ~= -1
  end, 20)
  assert(quit_completed, (":q did not terminate and wipe the dedicated terminal (buffer_valid=%s, job_status=%s, pane_open=%s)")
    :format(vim.api.nvim_buf_is_valid(first.bufnr), vim.fn.jobwait({ first.job_id }, 0)[1], pane.is_open()))
  assert(vim.wait(1000, function()
    for win, height in pairs(quit_layout_heights) do
      if vim.api.nvim_win_get_height(win) ~= height then return false end
    end
    return true
  end, 20), ":q did not restore the pre-terminal window layout")

  local fresh = pane.open()
  assert(fresh.bufnr ~= first.bufnr and fresh.job_id ~= first.job_id,
    "Opening after :q did not create a fresh shell")
  vim.api.nvim_set_current_win(fresh.winid)
  vim.cmd("stopinsert")
  vim.cmd("quit")
  assert(vim.wait(1000, function() return not vim.api.nvim_buf_is_valid(fresh.bufnr) end, 20),
    "Fresh terminal did not close before the Agentic layout fixture")

  -- Exercise Agentic's actual input window, whose fixed sizing is what the
  -- dedicated terminal must preserve and later restore.
  local widget = require("agentic.ui.chat_widget"):new(function() return true end)
  widget:show({ focus_prompt = false })
  assert(vim.wait(1000, function()
    return widget.win_nrs.input and vim.api.nvim_win_is_valid(widget.win_nrs.input)
  end, 20), "Agentic input fixture did not open")
  local agentic_input = widget.win_nrs.input
  local agentic_input_height = vim.api.nvim_win_get_height(agentic_input)
  local agentic_terminal = pane.open()
  assert(vim.api.nvim_win_get_height(agentic_input) == agentic_input_height,
    "Opening the terminal changed the real Agentic input height")
  vim.api.nvim_win_set_height(agentic_input, agentic_input_height + 3)
  pane.toggle()
  assert(vim.wait(1000, function()
    return vim.api.nvim_win_get_height(agentic_input) == agentic_input_height
  end, 20), "Toggle did not reset the real Agentic input to its original height")
  pane.close()
  assert(vim.wait(1000, function()
    return not vim.api.nvim_buf_is_valid(agentic_terminal.bufnr)
  end, 20), "Agentic fixture terminal did not terminate")
  widget:destroy()
end, debug.traceback)

for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
  if tab ~= original_tab and vim.api.nvim_tabpage_is_valid(tab) then
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd("tabclose!")
  end
end
vim.api.nvim_set_current_tabpage(original_tab)
assert(ok, err)
