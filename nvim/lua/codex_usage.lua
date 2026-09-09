local M = {}

local state = {
  process = nil,
  stdout = "",
  initialized = false,
  pending_read_id = nil,
  refresh_queued = false,
  stopping = false,
  next_request_id = 2,
  retry_timer = nil,
  watchdog = nil,
  generation = 0,
  windows = {},
}

local config = {
  command = "codex",
  retry_ms = 30000,
  timeout_ms = 10000,
}

local schedule_retry

local function redraw_statusline()
  vim.schedule(function()
    pcall(vim.cmd.redrawstatus)
  end)
end

local function reset_windows()
  state.windows = {}
  redraw_statusline()
end

local function normalized_window(value)
  if type(value) ~= "table" then
    return nil
  end

  local used = tonumber(value.usedPercent)
  local duration = tonumber(value.windowDurationMins)
  local resets_at = tonumber(value.resetsAt)
  if not used or not duration or not resets_at or duration <= 0 or resets_at <= 0 then
    return nil
  end

  return {
    percent_left = math.max(0, math.min(100, math.floor(100 - used + 0.5))),
    duration_mins = math.floor(duration + 0.5),
    resets_at = math.floor(resets_at),
  }
end

-- Retain only display-safe numerical quota fields after each transient JSON
-- message is decoded. Account IDs, plan details, and credit IDs are discarded.
local function apply_rate_limits(payload)
  local limits = type(payload) == "table" and payload.rateLimits or nil
  if type(limits) ~= "table" then
    return false
  end

  local windows = {}
  for _, key in ipairs({ "primary", "secondary" }) do
    local window = normalized_window(limits[key])
    if window then
      windows[#windows + 1] = window
    end
  end

  table.sort(windows, function(a, b)
    return a.duration_mins < b.duration_mins
  end)
  state.windows = windows
  redraw_statusline()
  return true
end

local function duration_label(minutes)
  if minutes % 10080 == 0 then
    return string.format("%dw", minutes / 10080)
  elseif minutes % 1440 == 0 then
    return string.format("%dd", minutes / 1440)
  elseif minutes % 60 == 0 then
    return string.format("%dh", minutes / 60)
  end
  return string.format("%dm", minutes)
end

local function reset_label(resets_at, now)
  local remaining = math.max(0, resets_at - now)
  if remaining < 60 then
    return "<1m"
  elseif remaining < 3600 then
    return string.format("%dm", math.ceil(remaining / 60))
  elseif remaining < 86400 then
    local hours = math.floor(remaining / 3600)
    local minutes = math.ceil((remaining % 3600) / 60)
    if minutes == 60 then
      hours = hours + 1
      minutes = 0
    end
    return minutes == 0 and string.format("%dh", hours)
      or string.format("%dh%dm", hours, minutes)
  end
  local days = math.floor(remaining / 86400)
  local hours = math.floor((remaining % 86400) / 3600)
  return hours == 0 and string.format("%dd", days)
    or string.format("%dd%dh", days, hours)
end

local function format_windows(windows, now)
  local parts = {}
  for _, window in ipairs(windows) do
    parts[#parts + 1] = string.format(
      "%s %d%% left (reset %s)",
      duration_label(window.duration_mins),
      window.percent_left,
      reset_label(window.resets_at, now)
    )
  end
  return table.concat(parts, " | ")
end

local function current_statusline_width()
  local winid = tonumber(vim.g.statusline_winid)
  if winid and vim.api.nvim_win_is_valid(winid) then
    return vim.api.nvim_win_get_width(winid)
  end
  return vim.o.columns
end

local function format_compact(windows, now, include_resets)
  local quotas = {}
  local resets = {}
  for _, window in ipairs(windows) do
    quotas[#quotas + 1] = string.format(
      "%s %d%%",
      duration_label(window.duration_mins),
      window.percent_left
    )
    resets[#resets + 1] = reset_label(window.resets_at, now)
  end
  local result = "Codex " .. table.concat(quotas, "/")
  if include_resets then
    result = result .. " left (reset " .. table.concat(resets, "/") .. ")"
  end
  return result
end

function M.statusline()
  if #state.windows == 0 then
    return ""
  end
  local width = current_statusline_width()
  if width < 55 then
    return format_compact(state.windows, os.time(), false)
  elseif width < 100 then
    return format_compact(state.windows, os.time(), true)
  end
  return "Codex " .. format_windows(state.windows, os.time())
end

local function cancel_watchdog()
  if not state.watchdog then
    return
  end
  pcall(state.watchdog.stop, state.watchdog)
  pcall(state.watchdog.close, state.watchdog)
  state.watchdog = nil
end

local function fail_process(process, generation)
  if state.process ~= process or state.generation ~= generation then
    return
  end
  cancel_watchdog()
  state.generation = state.generation + 1
  state.process = nil
  state.initialized = false
  state.pending_read_id = nil
  state.refresh_queued = false
  reset_windows()
  pcall(process.kill, process, 15)
  schedule_retry()
end

local function arm_watchdog(process, generation)
  cancel_watchdog()
  state.watchdog = vim.defer_fn(function()
    state.watchdog = nil
    fail_process(process, generation)
  end, config.timeout_ms)
end

local function send(message)
  if not state.process then
    return false
  end
  local ok = pcall(state.process.write, state.process, vim.json.encode(message) .. "\n")
  return ok
end

function M.refresh()
  if not state.process or not state.initialized then
    M.start()
    return
  end

  if state.pending_read_id then
    state.refresh_queued = true
    return
  end

  local id = state.next_request_id
  state.next_request_id = id + 1
  state.pending_read_id = id
  local process = state.process
  local generation = state.generation
  if send({ id = id, method = "account/rateLimits/read" }) then
    arm_watchdog(process, generation)
  else
    fail_process(process, generation)
  end
end

local function handle_message(message)
  if type(message) ~= "table" then
    return
  end

  if message.id == 1 then
    if message.error then
      fail_process(state.process, state.generation)
      return
    end
    cancel_watchdog()
    state.initialized = true
    if not send({ method = "initialized" }) then
      fail_process(state.process, state.generation)
      return
    end
    M.refresh()
    return
  end

  if message.method == "account/rateLimits/updated" then
    -- Notifications can be sparse. Re-read the complete snapshot instead of
    -- accidentally dropping an unchanged primary or secondary window.
    M.refresh()
    return
  end

  if message.id == state.pending_read_id then
    cancel_watchdog()
    state.pending_read_id = nil
    if message.result then
      apply_rate_limits(message.result)
    elseif message.error then
      reset_windows()
    end
    if state.refresh_queued then
      state.refresh_queued = false
      M.refresh()
    end
  end
end

local function consume_stdout(chunk)
  if not chunk then
    return
  end
  state.stdout = state.stdout .. chunk
  while true do
    local newline = state.stdout:find("\n", 1, true)
    if not newline then
      break
    end
    local line = state.stdout:sub(1, newline - 1)
    state.stdout = state.stdout:sub(newline + 1)
    if line ~= "" then
      local ok, message = pcall(vim.json.decode, line)
      if ok then
        handle_message(message)
      end
    end
  end
end

schedule_retry = function()
  if state.stopping or state.retry_timer then
    return
  end
  state.retry_timer = vim.defer_fn(function()
    state.retry_timer = nil
    if not state.stopping then
      M.start()
    end
  end, config.retry_ms)
end

function M.start()
  if vim.env.NVIM_CODEX_USAGE_DISABLED == "1" or state.stopping or state.process then
    return
  end

  local executable = vim.fn.exepath(config.command)
  if executable == "" then
    return
  end

  state.stdout = ""
  state.initialized = false
  state.pending_read_id = nil
  state.refresh_queued = false
  state.generation = state.generation + 1
  local generation = state.generation
  local process
  local ok, result = pcall(vim.system, { executable, "app-server", "--stdio" }, {
    stdin = true,
    text = true,
    stdout = function(_, data)
      if state.generation == generation then
        consume_stdout(data)
      end
    end,
    -- App Server diagnostics are intentionally quiet in the editor. The
    -- provider-backed chat remains usable if this optional display fails.
    stderr = function() end,
  }, function()
    vim.schedule(function()
      if state.process ~= process or state.generation ~= generation then
        return
      end
      cancel_watchdog()
      state.process = nil
      state.initialized = false
      state.pending_read_id = nil
      state.refresh_queued = false
      reset_windows()
      schedule_retry()
    end)
  end)
  if not ok then
    schedule_retry()
    return
  end
  process = result
  state.process = process

  if not send({
    id = 1,
    method = "initialize",
    params = {
      clientInfo = {
        name = "leeharin-neovim-usage",
        title = "LeeHaRin Neovim Usage",
        version = "1.0.0",
      },
      capabilities = { experimentalApi = true },
    },
  }) then
    fail_process(process, generation)
    return
  end
  arm_watchdog(process, generation)
end

function M.stop()
  state.stopping = true
  state.generation = state.generation + 1
  cancel_watchdog()
  if state.retry_timer then
    pcall(state.retry_timer.stop, state.retry_timer)
    pcall(state.retry_timer.close, state.retry_timer)
    state.retry_timer = nil
  end
  if state.process then
    pcall(state.process.kill, state.process, 15)
    state.process = nil
  end
  state.initialized = false
  state.pending_read_id = nil
  state.refresh_queued = false
  state.stdout = ""
end

function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  state.stopping = false

  local original = vim.o.statusline
  local usage = "%{v:lua.require('codex_usage').statusline()}"
  if original == "" then
    vim.o.statusline = "%<%f %h%m%r%=" .. usage .. "  %-14.(%l,%c%V%) %P"
  elseif not original:find("codex_usage", 1, true) then
    vim.o.statusline = original .. "%= " .. usage
  end

  vim.api.nvim_create_user_command("CodexUsageRefresh", M.refresh, {
    desc = "Refresh the live ChatGPT Codex quota display",
    force = true,
  })
  vim.keymap.set("n", "<leader>au", M.refresh, {
    desc = "Codex: refresh live quota",
  })

  local group = vim.api.nvim_create_augroup("LeeHaRinCodexUsage", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = M.stop,
  })

  if vim.env.NVIM_CODEX_USAGE_DISABLED ~= "1" then
    M.start()
  end
end

-- Narrow test seam: accepts the same already-decoded provider payload as the
-- live boundary and returns only the rendered, sanitized status text.
function M._test_apply(payload, now)
  state.windows = {}
  apply_rate_limits(payload)
  return format_windows(state.windows, now)
end

function M._test_consume(chunk)
  consume_stdout(chunk)
end

function M._test_expect_read(id)
  state.pending_read_id = id
end

return M
