local M = {}

local frame = 0
local active_state
local active_node_id
local active_since = 0

local function characters(text)
  local result = {}
  for index = 0, vim.fn.strchars(text) - 1 do
    result[#result + 1] = vim.fn.strcharpart(text, index, 1)
  end
  return result
end

local function marquee_window(text, width, offset)
  local glyphs = characters(text .. "   ")
  local result = {}
  local used = 0
  local index = (offset % #glyphs) + 1

  while used < width do
    local glyph = glyphs[index]
    local glyph_width = vim.fn.strdisplaywidth(glyph)
    if used + glyph_width > width then
      break
    end
    result[#result + 1] = glyph
    used = used + glyph_width
    index = (index % #glyphs) + 1
  end

  return table.concat(result) .. string.rep(" ", width - used)
end

function M.name(config, node, state, remaining_width)
  local name_component = require("neo-tree.sources.common.components").name
  local rendered = name_component(config, node, state)
  local selected = state.tree and state.tree:get_node()
  local node_id = node:get_id()
  local is_selected = selected and selected:get_id() == node_id
  local width = math.max(8, (remaining_width or state.win_width or 40) - 4)

  if not is_selected or vim.fn.strdisplaywidth(rendered.text) <= width then
    if is_selected then
      active_state = nil
      active_node_id = nil
      frame = 0
    end
    return rendered
  end

  if active_node_id ~= node_id then
    active_node_id = node_id
    frame = 0
    active_since = vim.uv.now()
  end
  active_state = state

  local wanted_width = vim.fn.strdisplaywidth(rendered.text)
  rendered.text = marquee_window(rendered.text, width, frame)
  return rendered, wanted_width
end

function M.setup()
  local timer = assert(vim.uv.new_timer())
  timer:start(160, 160, vim.schedule_wrap(function()
    local state = active_state
    if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then
      return
    end
    if vim.api.nvim_get_current_win() ~= state.winid then
      return
    end
    if vim.uv.now() - active_since < 700 then
      return
    end

    frame = frame + 1
    require("neo-tree.ui.renderer").redraw(state)
  end))

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("NeoTreeFilenameMarquee", { clear = true }),
    once = true,
    callback = function()
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  })
end

M._window = marquee_window

return M
