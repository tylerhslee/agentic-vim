-- Supply indexed colors alongside RGB highlights. Preserve explicit color-mode
-- choices and recognize advertised RGB support before theme loading.
local M = {}
local cache = {}
local levels = { 0, 95, 135, 175, 215, 255 }

local function nearest(rgb)
  if cache[rgb] then return cache[rgb] end
  local r = math.floor(rgb / 65536)
  local g = math.floor(rgb / 256) % 256
  local b = rgb % 256
  local best, distance = 16, math.huge
  local function consider(index, red, green, blue)
    local d = (r - red)^2 + (g - green)^2 + (b - blue)^2
    if d < distance then best, distance = index, d end
  end
  -- Avoid indices 0-15: their colors are chosen by the terminal profile.
  for ri, red in ipairs(levels) do
    for gi, green in ipairs(levels) do
      for bi, blue in ipairs(levels) do
        consider(16 + (ri - 1) * 36 + (gi - 1) * 6 + bi - 1, red, green, blue)
      end
    end
  end
  for i = 0, 23 do
    local grey = 8 + i * 10
    consider(232 + i, grey, grey, grey)
  end
  cache[rgb] = best
  return best
end

function M.apply()
  for name, highlight in pairs(vim.api.nvim_get_hl(0, {})) do
    if not highlight.link and (highlight.fg or highlight.bg) then
      if highlight.fg then highlight.ctermfg = nearest(highlight.fg) end
      if highlight.bg then highlight.ctermbg = nearest(highlight.bg) end
      vim.api.nvim_set_hl(0, name, highlight)
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("AgenticTerminalColors", { clear = true })
  local rgb
  vim.api.nvim_create_autocmd("ColorSchemePre", {
    group = group,
    callback = function()
      rgb = vim.o.termguicolors
      local info = vim.api.nvim_get_option_info2("termguicolors", {})
      -- The TUI may detect RGB only after init.lua. Restoring the startup false
      -- below marks the option explicitly set and prevents that later detection.
      -- Honor advertised true color now, unless the user already chose a mode.
      if not info.was_set
          and (vim.env.COLORTERM == "truecolor" or vim.env.COLORTERM == "24bit") then
        rgb = true
      end
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      -- Catppuccin's compiled theme enables RGB unconditionally. Preserve the
      -- mode Neovim (or the user) selected before loading the theme.
      if rgb ~= nil and vim.o.termguicolors ~= rgb then
        vim.o.termguicolors = rgb
      end
      M.apply()
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = M.apply,
    desc = "Provide a matching 256-color palette for basic terminals",
  })
end

return M
