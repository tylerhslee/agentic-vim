-- Exercise native session previews with real widgets, without provider requests.
local ChatWidget = require("agentic.ui.chat_widget")
local SessionHud = require("agentic.ui.session_hud")
local registry = require("agentic.session_registry")
local original_list = registry.list
local widgets = {}
local hud
local ok, err = pcall(function()
  local sessions = {}
  for key = 1, 2 do
    local widget = ChatWidget:new(function() return false end)
    widgets[key] = widget
    sessions[key] = {
      session_key = key,
      session_id = "preview-test-" .. key,
      widget = widget,
      chat_history = { title = "Preview " .. key, messages = {} },
      get_navigation_status = function() return "idle" end,
    }
    vim.bo[widget.buf_nrs.chat].modifiable = true
    vim.api.nvim_buf_set_lines(widget.buf_nrs.chat, 0, -1, false, { "Chat " .. key })
    vim.bo[widget.buf_nrs.chat].modifiable = false
    vim.api.nvim_buf_set_lines(widget.buf_nrs.input, 0, -1, false, { "Draft " .. key })
  end
  registry.list = function() return sessions end
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
  vim.cmd("normal k")
  assert(vim.api.nvim_win_get_buf(chat) == source.buf_nrs.chat, "k did not restore the source preview")
  vim.cmd("normal j")
  hud:close()
  assert(vim.api.nvim_win_get_buf(chat) == source.buf_nrs.chat, "Teardown lost the source chat")
  assert(vim.api.nvim_win_get_buf(input) == source.buf_nrs.input, "Teardown lost the source prompt")
  for key, widget in ipairs(widgets) do
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(widget.buf_nrs.input, 0, -1, false),
      { "Draft " .. key }), "Preview changed an unsent draft")
  end
end)
if hud then hud:close() end
registry.list = original_list
for _, widget in ipairs(widgets) do widget:destroy() end
assert(ok, err)
