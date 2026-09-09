-- Agentic.nvim: Space is the global leader; comma is the chat-local leader.
vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.mouse = "a"
vim.opt.updatetime = 250
vim.opt.cursorline = true
vim.opt.cursorlineopt = "line"

-- Search only the installer-managed native package root. This prevents stale
-- plugins in other package namespaces from shadowing the pinned revisions.
vim.opt.packpath = table.concat({
  vim.fn.stdpath("data") .. "/agentic-vim/nvim-site",
  vim.env.VIMRUNTIME,
}, ",")

-- Provider binaries are installed in Neovim's portable data directory.
local provider_bin = vim.fn.stdpath("data") .. "/nvim/agentic-vim/bin"

-- Show live ChatGPT Codex quota windows without reading or storing auth data.
require("codex_usage").setup({ command = provider_bin .. "/codex" })

-- Keep routine scheduling in systemd when the WSL-only LeeHaRin mirror is
-- installed. Other machines retain the pane and keymap with an empty job list.
local routine_jobs = require("routine_jobs")
local routine_job_list = {}
local mirror_service = vim.fn.expand("~/.config/systemd/user/leeharin-mirror.service")
local mirror_timer = vim.fn.expand("~/.config/systemd/user/leeharin-mirror.timer")
if vim.fn.executable("systemctl") == 1
    and vim.fn.filereadable(mirror_service) == 1
    and vim.fn.filereadable(mirror_timer) == 1 then
  routine_job_list = {
    {
      name = "LeeHaRin mirror",
      description = "Event-driven WSL-to-Windows mirror with hourly reconciliation",
      service = "leeharin-mirror.service",
      reconcile_service = "leeharin-mirror-reconcile.service",
      watcher = "leeharin-mirror-watch.service",
      timer = "leeharin-mirror.timer",
      timer_path = mirror_timer,
      service_path = mirror_service,
    },
  }
end
routine_jobs.setup({
  jobs = routine_job_list,
})
vim.keymap.set("n", "<leader>aj", routine_jobs.toggle,
  { desc = "Routine Jobs: toggle management pane" })

-- GUI clients honor these; terminal Neovim uses the terminal's font metrics.
vim.opt.guifont = "JetBrainsMono NFM:h14"
vim.opt.linespace = 2

vim.keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { desc = "Enter Terminal-Normal mode" })

-- Move between windows with one Ctrl chord. These Normal-mode mappings also
-- work after entering Terminal-Normal mode, without stealing shell shortcuts.
vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Focus window left" })
vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Focus window below" })
vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Focus window above" })
vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Focus window right" })

-- Soft, dark colors with intentionally broad syntax differentiation.
vim.cmd("packadd catppuccin")
require("catppuccin").setup({
  flavour = "macchiato",
  term_colors = true,
  auto_integrations = true,
  color_overrides = {
    macchiato = {
      text = "#bdc6e5",
      base = "#202334",
      mantle = "#1b1d2b",
      crust = "#151620",
    },
  },
  styles = {
    comments = { "italic" },
    conditionals = { "italic" },
    loops = { "italic" },
    functions = { "bold" },
    keywords = { "italic" },
    strings = {},
    variables = {},
    numbers = {},
    booleans = { "bold" },
    properties = {},
    types = { "bold" },
    operators = {},
  },
  custom_highlights = function(colors)
    return {
      CursorLine = { bg = "#272a3c" },
      ["@variable"] = { fg = colors.rosewater },
      ["@variable.parameter"] = { fg = colors.maroon, style = { "italic" } },
      ["@variable.member"] = { fg = colors.lavender },
      ["@module"] = { fg = colors.yellow, style = { "italic" } },
      ["@property"] = { fg = colors.lavender },
      ["@constructor"] = { fg = colors.sapphire },
      ["@type.builtin"] = { fg = colors.yellow, style = { "italic" } },
      ["@function.call"] = { fg = colors.blue },
      ["@function.method.call"] = { fg = colors.blue },
    }
  end,
})
vim.cmd("colorscheme catppuccin-macchiato")

-- Traditional project tree. Dependencies are installed alongside Neo-tree in
-- native package directories so startup does not depend on a plugin manager.
vim.cmd("packadd plenary.nvim")
vim.cmd("packadd nui.nvim")
vim.cmd("packadd nvim-web-devicons")
vim.cmd("packadd neo-tree.nvim")
require("nvim-web-devicons").setup({})
require("neo-tree").setup({
  close_if_last_window = true,
  popup_border_style = "rounded",
  source_selector = {
    winbar = true,
    statusline = false,
    sources = {
      { source = "filesystem", display_name = " Files" },
      { source = "buffers", display_name = " Buffers" },
      { source = "git_status", display_name = " Git" },
    },
  },
  window = {
    position = "left",
    width = 34,
    mappings = {
      ["h"] = "close_node",
      ["l"] = "open",
    },
  },
  filesystem = {
    filtered_items = {
      visible = true,
    },
    follow_current_file = {
      enabled = true,
      leave_dirs_open = false,
    },
    group_empty_dirs = true,
    use_libuv_file_watcher = true,
  },
})

vim.keymap.set("n", "<leader>e", "<Cmd>Neotree filesystem toggle reveal left<CR>",
  { desc = "Neo-tree: toggle project tree" })
vim.keymap.set("n", "<leader>E", "<Cmd>Neotree filesystem focus reveal left<CR>",
  { desc = "Neo-tree: focus current file" })

-- Start an installed Tree-sitter parser whenever a matching filetype opens.
vim.cmd("packadd nvim-treesitter")
local treesitter_group = vim.api.nvim_create_augroup("LeeHaRinTreesitter", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = treesitter_group,
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})

-- Use a compact fuzzy picker for vim.ui.select calls, including Agentic's
-- Shift-Tab approval-mode selector. Keep the rest of snacks.nvim disabled.
vim.cmd("packadd snacks.nvim")
require("snacks").setup({
  picker = {
    enabled = true,
    ui_select = true,
  },
})

-- The installer applies the repository's Agent HUD patch to this pinned plugin.
vim.cmd("packadd agentic.nvim")
vim.cmd("packadd render-markdown.nvim")
require("render-markdown").setup({
  file_types = { "markdown", "md", "AgenticChat" },
  pipe_table = {
    enabled = true,
  },
})

require("agentic").setup({
  provider = "codex-acp",
  keymaps = {
    widget = {
      switch_provider = "<localleader>l",
      select_session = "<localleader>s",
    },
  },
  acp_providers = {
    ["codex-acp"] = {
      command = provider_bin .. "/codex-acp",
    },
  },
})

local agentic = require("agentic")

-- Make Agentic's widget controls available from normal editor buffers under
-- the global Space leader. Comma remains local to Agentic buffers. The bridge
-- discovers configured mappings instead of duplicating their actions here and
-- resolves the active session each time a key is used.
local function has_normal_mode(modes)
  if type(modes) == "string" then
    return modes == "n"
  end

  for _, mode in ipairs(modes) do
    if mode == "n" then
      return true
    end
  end

  return false
end

local function each_normal_keymap(keymaps, callback)
  if type(keymaps) == "string" then
    callback(keymaps)
    return
  end

  for _, keymap in ipairs(keymaps) do
    if type(keymap) == "string" then
      callback(keymap)
    elseif has_normal_mode(keymap.mode) then
      callback(keymap[1])
    end
  end
end

local function expand_keycodes(lhs)
  return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

local function run_agentic_widget_keymap(lhs)
  local session = require("agentic.session_registry").current()
  local input_bufnr = session and session.widget.buf_nrs.input
  if not input_bufnr or not vim.api.nvim_buf_is_valid(input_bufnr) then
    return
  end

  local expanded_lhs = expand_keycodes(lhs)
  for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(input_bufnr, "n")) do
    if keymap.lhsraw == expanded_lhs and type(keymap.callback) == "function" then
      keymap.callback()
      return
    end
  end
end

local expanded_localleader = expand_keycodes("<localleader>")
local expanded_leader = expand_keycodes("<leader>")
for _, keymaps in pairs(require("agentic.config").keymaps.widget) do
  each_normal_keymap(keymaps, function(lhs)
    local expanded_lhs = expand_keycodes(lhs)
    if expanded_lhs:sub(1, #expanded_localleader) == expanded_localleader then
      local global_lhs = expanded_leader .. expanded_lhs:sub(#expanded_localleader + 1)
      vim.keymap.set("n", global_lhs, function()
        run_agentic_widget_keymap(lhs)
      end, { desc = "Agentic: widget command from editor" })
    end
  end)
end

local function close_agentic_and_resize()
  agentic.close()
  vim.cmd("vertical resize 120")
end

vim.keymap.set("n", "<leader>aa", agentic.toggle, { desc = "Agentic: toggle chat" })
vim.keymap.set("n", "<leader>aq", close_agentic_and_resize,
  { desc = "Agentic: close chat and resize editor to 120 columns" })
vim.keymap.set("n", "<leader>q", close_agentic_and_resize,
  { desc = "Agentic: close chat and resize editor to 120 columns" })
vim.keymap.set({ "n", "v" }, "<leader>ac", agentic.add_selection_or_file_to_context,
  { desc = "Agentic: add file or selection" })
vim.keymap.set("n", "<leader>an", agentic.new_session, { desc = "Agentic: new session" })
vim.keymap.set("n", "<leader>ar", agentic.restore_session, { desc = "Agentic: restore session" })
vim.keymap.set("n", "<leader>al", agentic.rotate_layout, { desc = "Agentic: rotate layout" })
vim.keymap.set("n", "<leader>ax", agentic.stop_generation, { desc = "Agentic: stop generation" })

-- Turn the habitual :wq into an intentional save-everything-and-exit action.
-- Cancel is selected by default, and a failed write prevents Neovim from exiting.
local function confirm_write_all_and_quit(force)
  vim.ui.select({ "Cancel", "Save all and quit" }, {
    prompt = "Save every modified file and close all Neovim windows?",
  }, function(choice)
    if choice ~= "Save all and quit" then
      return
    end

    local command = force and "wqall!" or "wqall"
    local ok, err = pcall(vim.cmd, command)
    if not ok then
      vim.notify("Could not save all files and quit: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

vim.api.nvim_create_user_command("ConfirmWqAll", function(args)
  confirm_write_all_and_quit(args.bang)
end, {
  bang = true,
  desc = "Confirm, save every modified buffer, and quit Neovim",
})

vim.keymap.set("c", "<CR>", function()
  local command = vim.trim(vim.fn.getcmdline())
  if vim.fn.getcmdtype() == ":" and (command == "wq" or command == "wq!") then
    local bang = command == "wq!" and "!" or ""
    return "<C-u>ConfirmWqAll" .. bang .. "<CR>"
  end

  return "<CR>"
end, {
  expr = true,
  replace_keycodes = true,
  desc = "Confirm before :wq saves all files and quits Neovim",
})
