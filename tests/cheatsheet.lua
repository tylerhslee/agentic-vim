-- Runs with the installed Agentic UI, without starting a provider session.
local sheet = require("cheatsheet")
local widget = require("agentic.ui.chat_widget"):new(function() return false end)
local function settle()
  vim.wait(30, function() return false end)
end
local function press(key)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "xt", false)
  settle()
end
local function snapshot()
  local result = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      result[win] = {
        vim.api.nvim_win_get_position(win), vim.api.nvim_win_get_width(win),
        vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_buf(win),
        vim.api.nvim_win_call(win, vim.fn.winsaveview),
      }
    end
  end
  return result
end

-- Read-only help must open even when Neovim cannot create a swap file.
local old_directory = vim.o.directory
vim.o.directory = vim.fn.tempname() .. "/missing"
local opened, open_error = pcall(sheet.open)
vim.o.directory = old_directory
assert(opened, "Cheatsheet required a writable swap directory: " .. tostring(open_error))
assert(vim.api.nvim_buf_line_count(0) > 1, "Cheatsheet help buffer was empty")
assert(vim.bo.swapfile == false, "Cheatsheet help buffer enabled swap")
sheet.toggle()

widget:show({ focus_prompt = false })
settle()
vim.api.nvim_set_current_win(widget.win_nrs.input)
local before = snapshot()
for _ = 1, 12 do
  press("<F2>")
  local float = vim.api.nvim_get_current_win()
  assert(vim.api.nvim_win_get_config(float).relative == "editor", "F2 did not open a float")
  assert(vim.api.nvim_buf_line_count(0) > 1, "Normal-mode F2 opened an empty cheatsheet")
  assert(vim.deep_equal(before, snapshot()), "Opening F2 moved chat or input")
  sheet.open()
  assert(vim.api.nvim_get_current_win() == float, "Open duplicated the cheatsheet")
  press("<F2>")
  assert(not vim.api.nvim_win_is_valid(float), "F2 did not close the cheatsheet")
  assert(vim.api.nvim_get_current_win() == widget.win_nrs.input, "F2 lost input focus")
  assert(vim.deep_equal(before, snapshot()), "Repeated F2 changed the chat layout or view")
end

sheet.open()
local float = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(widget.win_nrs.chat)
press("<F2>")
assert(not vim.api.nvim_win_is_valid(float), "F2 from chat did not close the existing sheet")
assert(vim.api.nvim_get_current_win() == widget.win_nrs.chat, "Toggle stole chat focus")
for _, key in ipairs({ "q", "<Esc>", "<Space><F1>" }) do
  sheet.open()
  float = vim.api.nvim_get_current_win()
  press(key)
  assert(not vim.api.nvim_win_is_valid(float), key .. " did not close the cheatsheet")
end
assert(vim.deep_equal(before, snapshot()), "Closing shortcuts changed chat geometry")

vim.api.nvim_set_current_win(widget.win_nrs.input)
press("i<F2>")
float = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_config(float).relative == "editor", "Insert-mode F2 did not open help")
assert(vim.api.nvim_buf_line_count(0) > 1, "Insert-mode F2 opened an empty cheatsheet")
press("<F2>")
assert(vim.api.nvim_get_current_win() == widget.win_nrs.input, "Insert-mode F2 lost input focus")
assert(vim.deep_equal(before, snapshot()), "Insert-mode toggle changed chat geometry")

sheet.open()
float = vim.api.nvim_get_current_win()
vim.cmd("tabnew")
sheet.toggle()
local other_float = vim.api.nvim_get_current_win()
assert(other_float ~= float, "Another tab reused the original tab's sheet")
sheet.toggle()
assert(vim.api.nvim_win_is_valid(float), "Another tab closed the original tab's sheet")
vim.cmd("tabclose")
sheet.toggle()
assert(not vim.api.nvim_win_is_valid(float), "Original tab could not close its sheet")

-- Ordinary help must not be replaced or closed by the cheatsheet toggle.
vim.cmd("help help")
local help_win, help_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
sheet.toggle()
sheet.toggle()
assert(vim.api.nvim_win_is_valid(help_win) and vim.api.nvim_win_get_buf(help_win) == help_buf,
  "Cheatsheet replaced ordinary help")
vim.api.nvim_win_close(help_win, true)
widget:destroy()
settle()
