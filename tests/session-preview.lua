-- Exercise native session previews with real widgets, without provider requests.
local ChatWidget = require("agentic.ui.chat_widget")
local SessionHud = require("agentic.ui.session_hud")
local registry = require("agentic.session_registry")
local original_list = registry.list
local original_sessions = registry.sessions
local original_recent = registry._most_recent
local original_previous = registry._previous_most_recent
local widgets = {}
local hud
local editor = vim.api.nvim_get_current_win()
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
vim.fn.writefile({ "picker routing fixture" }, directory .. "/selected.txt")
local tree_command = require("neo-tree.command")
local ok, err = pcall(function()
  local sessions = {}
  for key = 1, 2 do
    local widget = ChatWidget:new(function() return false end)
    widget.session_key = key
    widgets[key] = widget
    sessions[key] = {
      session_key = key,
      session_id = "preview-test-" .. key,
      widget = widget,
      chat_history = { title = "Preview " .. key, messages = {} },
      get_navigation_status = function() return "idle" end,
    }
    vim.bo[widget.buf_nrs.chat].modifiable = true
    local history = {}
    for line = 1, 200 do history[line] = "Chat " .. key .. " message " .. line end
    vim.api.nvim_buf_set_lines(widget.buf_nrs.chat, 0, -1, false, history)
    vim.bo[widget.buf_nrs.chat].modifiable = false
    vim.api.nvim_buf_set_lines(widget.buf_nrs.input, 0, -1, false, { "Draft " .. key })
  end
  registry.list = function() return sessions end
  registry.sessions = sessions
  local source, other = widgets[1], widgets[2]
  source:show({ focus_prompt = false })
  vim.wait(30, function() return false end)
  local chat, input = source.win_nrs.chat, source.win_nrs.input
  hud = SessionHud:new(sessions[1])
  hud:open()
  vim.cmd("normal j")
  assert(vim.api.nvim_win_get_buf(chat) == other.buf_nrs.chat, "j did not preview the highlighted chat")
  assert(vim.api.nvim_get_current_win() == input, "Preview stole picker focus")
  -- Let BufferGuard, headers, and the picker's periodic refresh run.
  vim.wait(350, function() return false end)
  assert(hud:is_open(), "Preview caused the picker to close")
  assert(vim.api.nvim_win_get_buf(chat) == other.buf_nrs.chat, "Preview was replaced after refresh")
  assert(other:get_visible_tab_id() == nil, "Preview moved the other session's widget")

  -- Enter in Neo-tree must not replace the picker or its chat preview.
  local picker_buf = vim.api.nvim_win_get_buf(input)
  tree_command.execute({ action = "focus", source = "filesystem", dir = directory })
  local tree = require("neo-tree.sources.manager").get_state("filesystem")
  assert(vim.wait(2000, function()
    return tree.tree and tree.tree:get_node(directory .. "/selected.txt") ~= nil
  end), "Picker routing fixture tree did not load")
  vim.api.nvim_set_current_win(input)
  vim.api.nvim_set_current_win(tree.winid)
  require("neo-tree.ui.renderer").focus_node(tree, directory .. "/selected.txt")
  vim.cmd("normal \r")
  assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == directory .. "/selected.txt",
    "Neo-tree did not open the selected file in the code editor")
  assert(vim.api.nvim_win_get_buf(input) == picker_buf, "Neo-tree replaced the session picker")
  assert(vim.api.nvim_win_get_buf(chat) == other.buf_nrs.chat, "Neo-tree replaced the chat preview")
  assert(hud:is_open(), "Opening a file closed the session picker")
  tree_command.execute({ action = "close", source = "filesystem" })
  vim.api.nvim_set_current_win(input)
  vim.cmd("normal k")
  assert(vim.api.nvim_win_get_buf(chat) == source.buf_nrs.chat, "k did not restore the source preview")
  vim.cmd("normal j")
  hud:close()
  assert(vim.api.nvim_win_get_buf(chat) == source.buf_nrs.chat, "Teardown lost the source chat")
  assert(vim.api.nvim_win_get_buf(input) == source.buf_nrs.input, "Teardown lost the source prompt")

  -- Selecting either the current session or another session lands at the latest
  -- message, even when that session was previously scrolled into its history.
  for _, action in ipairs({ "enter", "finish" }) do
    for _, target_key in ipairs({ 1, 2 }) do
      registry.show_session(1, { focus_prompt = false })
      vim.wait(30, function() return false end)
      vim.api.nvim_win_set_cursor(source.win_nrs.chat, { 20, 0 })
      hud = SessionHud:new(sessions[1])
      hud:open()
      if target_key == 2 then vim.cmd("normal j") end
      if action == "enter" then
        vim.cmd("normal \r")
      else
        hud:finish()
      end
      vim.wait(350, function() return false end)
      local target = widgets[target_key]
      local label = action .. " session " .. target_key
      assert(not hud:is_open(), label .. " did not close the picker")
      assert(vim.api.nvim_get_current_win() == target.win_nrs.input,
        label .. " did not focus the selected prompt")
      assert(vim.api.nvim_win_get_cursor(target.win_nrs.chat)[1] == 200,
        label .. " did not move the chat cursor to the latest message")
      local bottom = vim.api.nvim_win_call(target.win_nrs.chat, function()
        return vim.fn.line("w$")
      end)
      assert(bottom == 200, label .. " did not show the latest message")
      vim.cmd("stopinsert")
    end
  end
  for key, widget in ipairs(widgets) do
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(widget.buf_nrs.input, 0, -1, false),
      { "Draft " .. key }), "Preview changed an unsent draft")
  end
end)
tree_command.execute({ action = "close", source = "filesystem" })
if hud then hud:close() end
registry.list = original_list
registry.sessions = original_sessions
registry._most_recent = original_recent
registry._previous_most_recent = original_previous
for _, widget in ipairs(widgets) do widget:destroy() end
vim.fn.delete(directory, "rf")
assert(ok, err)
