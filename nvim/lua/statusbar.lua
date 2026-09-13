local M = {}
local editors = {}
local timer

local function agent(win)
  local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
  return ft:match("^Agentic") ~= nil or ft:match("^agentic%-hud%-") ~= nil
end

local function escape(text)
  return (text:gsub("[\r\n\t]", " "):gsub("%%", "%%%%"))
end

local function fit(text, width)
  if width <= 0 then return "" end
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local out = ""
  for i = 0, vim.fn.strchars(text) - 1 do
    local char = vim.fn.strcharpart(text, i, 1)
    if vim.fn.strdisplaywidth(out .. char) > width - 1 then break end
    out = out .. char
  end
  return out .. "…"
end

local function section(left, right, width, group)
  right = fit(right, math.max(0, math.floor(width / 2)))
  local remaining = width - vim.fn.strdisplaywidth(right)
  left = fit(left, remaining)
  return "%#" .. group .. "#" .. escape(left)
    .. string.rep(" ", math.max(0, remaining - vim.fn.strdisplaywidth(left)))
    .. escape(right)
end

local function mode_label()
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == "i" then return "INSERT" end
  if mode:sub(1, 1) == "t" then return "TERMINAL" end
  if mode:match("^[vV\22]") then return "VISUAL" end
  if mode:sub(1, 1) == "R" then return "REPLACE" end
  return "NORMAL"
end

local function editor_text(win, active)
  if not win then return " 󰈔 Editor", "" end
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
  if vim.bo[buf].buftype == "terminal" then name = "Terminal" end
  local icon = "󰈔"
  local ok, icons = pcall(require, "nvim-web-devicons")
  if ok then icon = icons.get_icon(name, vim.bo[buf].filetype, { default = true }) or icon end
  local left = " " .. (active and (mode_label() .. "  ") or "") .. icon .. " " .. name
    .. (vim.bo[buf].modified and " ●" or "") .. (vim.bo[buf].readonly and " " or "")
  local pos = vim.api.nvim_win_get_cursor(win)
  local errors = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  local warnings = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.WARN })
  local right = (errors > 0 and ("  " .. errors) or "")
    .. (warnings > 0 and ("  " .. warnings) or "")
    .. (active and string.format("  %s  %d:%d ", vim.bo[buf].filetype, pos[1], pos[2] + 1) or " ")
  return left, right
end

local function agent_text(width)
  local registry = package.loaded["agentic.session_registry"]
  local session = registry and registry.current()
  local details = {}
  local state = session and session.session_state
  if state then
    for _, field in ipairs({ "model", "thought_level", "mode" }) do
      local value = state["get_" .. field .. "_name"](state)
        or state["get_" .. field .. "_id"](state)
      if value and value ~= "" then details[#details + 1] = value end
    end
  end
  if #details == 0 then details[1] = session and session.provider_name or "Agent" end
  local left = " 󰚩 " .. table.concat(details, " · ")
  if session and session.is_generating then left = left .. " ⟳" end
  -- Quota is secondary to session settings when the chat column is narrow.
  local budget = math.min(math.floor(width / 2), width - vim.fn.strdisplaywidth(left) - 3)
  local usage = budget > 0 and require("codex_usage").statusline(budget) or ""
  if vim.fn.strdisplaywidth(usage) > budget then usage = "" end
  return left, usage ~= "" and (" " .. usage .. " ") or ""
end

function M.render()
  local current = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_get_current_tabpage()
  local editor, first, last
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      if agent(win) then
        local col = vim.api.nvim_win_get_position(win)[2]
        first = math.min(first or col, col)
        last = math.max(last or 0, col + vim.api.nvim_win_get_width(win))
      elseif vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
          or vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
        editor = editor or win
        if win == current then editors[tab] = win end
      end
    end
  end
  local remembered = editors[tab]
  if remembered and vim.api.nvim_win_is_valid(remembered)
      and vim.api.nvim_win_get_tabpage(remembered) == tab and not agent(remembered)
      and (vim.bo[vim.api.nvim_win_get_buf(remembered)].buftype == ""
        or vim.bo[vim.api.nvim_win_get_buf(remembered)].buftype == "terminal")
      and vim.bo[vim.api.nvim_win_get_buf(remembered)].filetype ~= "neo-tree" then
    editor = remembered
  end
  local focused = agent(current)
  local left, right = editor_text(editor, not focused)
  local eg = focused and "StatusbarEditorMuted" or "StatusbarEditor"
  local ag = focused and "StatusbarAgent" or "StatusbarAgentMuted"
  local columns = vim.o.columns
  -- Side-by-side layouts follow actual window columns, including resize changes.
  if first and first > 0 then
    local a, b = agent_text(columns - first, focused)
    return section(left, right, first, eg) .. section(a, b, columns - first, ag)
  elseif first and last < columns then
    local a, b = agent_text(last + 1, focused)
    return section(a, b, last + 1, ag) .. section(left, right, columns - last - 1, eg)
  elseif first then
    -- Stacked layouts share horizontal space equally in the single bottom row.
    local split = math.floor(columns / 2)
    local a, b = agent_text(columns - split, focused)
    return section(left, right, split, eg) .. section(a, b, columns - split, ag)
  end
  local usage = require("codex_usage").statusline(math.floor(columns / 2))
  return section(left, (usage ~= "" and (usage .. "  ") or "") .. right, columns, eg)
end

function M.setup()
  local function highlights()
    for name, colors in pairs({
      StatusbarEditor = { fg = "#cad3f5", bg = "#363a4f", bold = true },
      StatusbarEditorMuted = { fg = "#a5adcb", bg = "#24273a" },
      StatusbarAgent = { fg = "#181926", bg = "#c6a0f6", bold = true },
      StatusbarAgentMuted = { fg = "#c6a0f6", bg = "#302c45" },
    }) do vim.api.nvim_set_hl(0, name, colors) end
  end
  highlights()
  vim.o.laststatus = 3
  vim.o.statusline = "%!v:lua.require('statusbar').render()"
  local group = vim.api.nvim_create_augroup("AgenticStatusbar", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "ModeChanged", "DiagnosticChanged", "WinResized" }, {
    group = group,
    callback = function() vim.cmd.redrawstatus() end,
  })
  -- Agent activity can change while the user is idle.
  if timer then timer:stop(); timer:close() end
  timer = vim.uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(function() vim.cmd.redrawstatus() end))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if timer then timer:stop(); timer:close(); timer = nil end
    end,
  })
end

return M
