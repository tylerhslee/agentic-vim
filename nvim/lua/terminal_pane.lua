local M = {}

local config = { height = 15 }
local state = {
  bufnr = nil,
  winid = nil,
  job_id = nil,
  origin_winid = nil,
  layout_tabpage = nil,
  layout_restore = nil,
  layout_window_options = nil,
  normalize_pending = false,
  normalizing = false,
}

local group = vim.api.nvim_create_augroup("AgenticTerminalPane", { clear = true })

local function valid_window(winid)
  return winid and vim.api.nvim_win_is_valid(winid)
end

local function valid_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function capture_layout()
  -- Agentic uses fixed-height child panes, so Neovim cannot reliably
  -- redistribute the terminal's rows when it closes. Remember the exact
  -- pre-terminal geometry and each pane's fixed-size policy.
  state.layout_tabpage = vim.api.nvim_get_current_tabpage()
  state.layout_restore = vim.fn.winrestcmd()
  state.layout_window_options = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(state.layout_tabpage)) do
    if vim.api.nvim_win_get_config(winid).relative == "" then
      state.layout_window_options[winid] = {
        winfixheight = vim.wo[winid].winfixheight,
        winfixwidth = vim.wo[winid].winfixwidth,
        height = vim.api.nvim_win_get_height(winid),
        width = vim.api.nvim_win_get_width(winid),
      }
    end
  end
end

local function preserve_fixed_layout()
  local tabpage = state.layout_tabpage
  for winid, options in pairs(state.layout_window_options or {}) do
    if vim.api.nvim_win_is_valid(winid)
        and vim.api.nvim_win_get_tabpage(winid) == tabpage then
      if options.winfixheight then
        pcall(vim.api.nvim_win_set_height, winid, options.height)
      end
      if options.winfixwidth then
        pcall(vim.api.nvim_win_set_width, winid, options.width)
      end
    end
  end
end

local function restore_layout()
  local tabpage, command = state.layout_tabpage, state.layout_restore
  local window_options = state.layout_window_options or {}
  state.layout_tabpage = nil
  state.layout_restore = nil
  state.layout_window_options = nil
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage)
      or not command or command == "" then
    return
  end
  vim.schedule(function()
    if not vim.api.nvim_tabpage_is_valid(tabpage) then
      return
    end
    local context_window
    for winid in pairs(window_options) do
      if vim.api.nvim_win_is_valid(winid)
          and vim.api.nvim_win_get_tabpage(winid) == tabpage then
        context_window = winid
        break
      end
    end
    if not context_window then
      return
    end
    pcall(vim.api.nvim_win_call, context_window, function()
      for winid in pairs(window_options) do
        if vim.api.nvim_win_is_valid(winid) then
          -- winrestcmd() cannot restore panes whose current fixed-size flags
          -- forbid its resize commands. Reinstate those flags immediately.
          vim.wo[winid].winfixheight = false
          vim.wo[winid].winfixwidth = false
        end
      end
      pcall(vim.cmd, command)
      for winid, options in pairs(window_options) do
        if vim.api.nvim_win_is_valid(winid) then
          if options.winfixheight then
            pcall(vim.api.nvim_win_set_height, winid, options.height)
          end
          if options.winfixwidth then
            pcall(vim.api.nvim_win_set_width, winid, options.width)
          end
          vim.wo[winid].winfixheight = options.winfixheight
          vim.wo[winid].winfixwidth = options.winfixwidth
        end
      end
    end)
  end)
end

local function job_alive(job_id)
  return job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1
end

local function snapshot(open)
  return {
    open = open,
    bufnr = state.bufnr,
    winid = state.winid,
    job_id = state.job_id,
  }
end

local function reset_buffer_state()
  state.bufnr = nil
  state.job_id = nil
end

local function discard_dead_terminal()
  if job_alive(state.job_id) then
    return
  end
  if valid_window(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  state.winid = nil
  if valid_buffer(state.bufnr) then
    pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
  end
  reset_buffer_state()
end

local function terminal_is_bottom(winid)
  local tab = vim.api.nvim_win_get_tabpage(winid)
  local terminal_position = vim.api.nvim_win_get_position(winid)
  if terminal_position[2] ~= 0 or vim.api.nvim_win_get_width(winid) ~= vim.o.columns then
    return false
  end
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if other ~= winid and vim.api.nvim_win_get_config(other).relative == "" then
      local position = vim.api.nvim_win_get_position(other)
      if position[1] + vim.api.nvim_win_get_height(other) > terminal_position[1] then
        return false
      end
    end
  end
  return true
end

local function normalize()
  local winid = state.winid
  if state.normalizing or not valid_window(winid)
      or vim.api.nvim_win_get_tabpage(winid) ~= vim.api.nvim_get_current_tabpage()
      or vim.api.nvim_win_get_config(winid).relative ~= "" then
    return
  end
  if terminal_is_bottom(winid) and vim.api.nvim_win_get_height(winid) == config.height then
    vim.wo[winid].winfixheight = true
    return
  end

  state.normalizing = true
  pcall(vim.api.nvim_win_call, winid, function()
    vim.wo.winfixheight = false
    vim.cmd("wincmd J")
    vim.cmd("resize " .. config.height)
    vim.wo.winfixheight = true
  end)
  state.normalizing = false
end

local function schedule_normalize()
  if state.normalize_pending then
    return
  end
  state.normalize_pending = true
  vim.schedule(function()
    state.normalize_pending = false
    normalize()
  end)
end

function M.is_open()
  return valid_window(state.winid)
end

function M.open()
  discard_dead_terminal()

  local current_tab = vim.api.nvim_get_current_tabpage()
  if valid_window(state.winid) then
    if vim.api.nvim_win_get_tabpage(state.winid) == current_tab then
      vim.api.nvim_set_current_win(state.winid)
      normalize()
      vim.cmd("startinsert")
      return snapshot(true)
    end
    pcall(vim.api.nvim_win_close, state.winid, false)
    state.winid = nil
    restore_layout()
  end

  state.origin_winid = vim.api.nvim_get_current_win()
  capture_layout()
  vim.cmd("botright " .. config.height .. "split")
  state.winid = vim.api.nvim_get_current_win()

  if valid_buffer(state.bufnr) and job_alive(state.job_id) then
    vim.api.nvim_win_set_buf(state.winid, state.bufnr)
  else
    vim.cmd("terminal")
    state.bufnr = vim.api.nvim_get_current_buf()
    state.job_id = vim.b[state.bufnr].terminal_job_id
    vim.bo[state.bufnr].bufhidden = "hide"
    vim.bo[state.bufnr].buflisted = false
    vim.bo[state.bufnr].swapfile = false
    vim.b[state.bufnr].agentic_terminal_pane = true
  end

  vim.wo[state.winid].winfixheight = true
  normalize()
  preserve_fixed_layout()
  vim.cmd("startinsert")
  return snapshot(true)
end

function M.hide()
  local winid = state.winid
  if not valid_window(winid) then
    state.winid = nil
    return snapshot(false)
  end

  local origin = state.origin_winid
  local windows = vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(winid))
  local normal_window_count = 0
  for _, window in ipairs(windows) do
    if vim.api.nvim_win_get_config(window).relative == "" then
      normal_window_count = normal_window_count + 1
    end
  end
  if normal_window_count == 1 then
    state.winid = nil
    state.origin_winid = nil
    vim.wo[winid].winfixheight = false
    local replacement = vim.api.nvim_create_buf(false, true)
    vim.bo[replacement].bufhidden = "wipe"
    vim.api.nvim_win_set_buf(winid, replacement)
    restore_layout()
    return snapshot(false)
  end
  vim.api.nvim_win_close(winid, false)
  state.winid = nil
  state.origin_winid = nil
  if valid_window(origin) and vim.api.nvim_win_get_tabpage(origin) == vim.api.nvim_get_current_tabpage() then
    vim.api.nvim_set_current_win(origin)
  end
  restore_layout()
  return snapshot(false)
end

function M.close()
  local bufnr, job_id = state.bufnr, state.job_id
  if valid_buffer(bufnr) then
    vim.bo[bufnr].bufhidden = "wipe"
  end
  if job_alive(job_id) then
    pcall(vim.fn.jobstop, job_id)
  end
  if valid_window(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  elseif valid_buffer(bufnr) then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  state.winid = nil
  state.origin_winid = nil
  restore_layout()
  reset_buffer_state()
  return snapshot(false)
end

function M.toggle()
  if valid_window(state.winid)
      and vim.api.nvim_win_get_tabpage(state.winid) == vim.api.nvim_get_current_tabpage() then
    return M.hide()
  end
  return M.open()
end

function M.command_line(line, command_type)
  if command_type == ":" then
    local command = vim.trim(line)
    if command == "term" or command == "terminal" then
      return "<C-u>TerminalPaneToggle<CR>"
    end
  end
end

function M.setup(opts)
  local next_config = vim.tbl_deep_extend("force", {}, config, opts or {})
  if type(next_config.height) ~= "number" or next_config.height < 1
      or next_config.height % 1 ~= 0 then
    error("terminal pane height must be a positive integer")
  end
  config = next_config

  vim.api.nvim_create_user_command("TerminalPaneToggle", M.toggle, {
    force = true,
    desc = "Toggle the persistent full-width terminal pane",
  })
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinResized", "VimResized", "BufWinEnter", "TabEnter" }, {
    group = group,
    callback = schedule_normalize,
  })
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    callback = function(args)
      if args.buf ~= state.bufnr then
        return
      end
      if valid_buffer(state.bufnr) then
        vim.bo[state.bufnr].bufhidden = "wipe"
      end
      if job_alive(state.job_id) then
        pcall(vim.fn.jobstop, state.job_id)
      end
      local quitting_buffer = state.bufnr
      vim.schedule(function()
        if valid_buffer(quitting_buffer) then
          pcall(vim.api.nvim_buf_delete, quitting_buffer, { force = true })
        end
        restore_layout()
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      if state.winid and tonumber(args.match) == state.winid then
        state.winid = nil
        state.origin_winid = nil
        restore_layout()
      end
    end,
  })
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function(args)
      if args.buf == state.bufnr then
        state.job_id = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if args.buf == state.bufnr then
        state.winid = nil
        state.origin_winid = nil
        reset_buffer_state()
      end
    end,
  })
end

return M
