local M = {}
local path = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))),
  "doc", "agentic-nvim.txt")

local function find_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == path then
      return win
    end
  end
end

local function geometry()
  local width = math.max(1, math.min(100, vim.o.columns - 4))
  local available = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
  local height = math.max(1, math.min(32, available - 2))
  return {
    relative = "editor", width = width, height = height,
    row = math.max(0, math.floor((available - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
  }
end

function M.open()
  local win = find_window()
  if win then
    vim.api.nvim_set_current_win(win)
    return
  end
  local buf = vim.fn.bufadd(path)
  -- This is a read-only help buffer; loading it must not depend on being able
  -- to create a swap file beside the isolated configuration or in state.
  vim.bo[buf].buftype = "help"
  vim.bo[buf].swapfile = false
  vim.fn.bufload(buf)
  -- A float leaves Agentic's split sizes and input position untouched.
  local config = geometry()
  config.style = "minimal"
  config.border = "rounded"
  vim.api.nvim_open_win(buf, true, config)
  vim.bo.bufhidden = "hide"
  vim.bo.buflisted = false
  vim.bo.modifiable = false
  vim.bo.filetype = "help"
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.wrap = true
  vim.wo.linebreak = true
  for _, key in ipairs({ "q", "<Esc>", "<F2>", "<leader><F1>" }) do
    vim.keymap.set("n", key, "<Cmd>close<CR>", { buffer = true, desc = "Close cheatsheet" })
  end
end

function M.toggle()
  local win = find_window()
  if win then
    vim.api.nvim_win_close(win, true)
  else
    M.open()
  end
end

function M.setup()
  vim.api.nvim_create_user_command("AgenticCheatsheet", M.open, { desc = "Agentic NVIM cheatsheet" })
  vim.keymap.set({ "n", "i", "v", "t" }, "<F2>", function()
    vim.cmd.stopinsert()
    M.toggle()
  end,
    { desc = "Agentic NVIM cheatsheet" })
  vim.keymap.set("n", "<leader><F1>", M.toggle, { desc = "Agentic NVIM cheatsheet" })
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("AgenticCheatsheet", { clear = true }),
    callback = function()
      local win = find_window()
      if win and vim.api.nvim_win_get_config(win).relative ~= "" then
        vim.api.nvim_win_set_config(win, geometry())
      end
    end,
  })
end

return M
