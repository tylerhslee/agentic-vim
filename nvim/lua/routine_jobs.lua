local M = {}

local config = {
  height = 15,
  refresh_ms = 5000,
  jobs = {},
}

local state = {
  bufnr = nil,
  winid = nil,
  generation = 0,
  jobs = {},
  line_jobs = {},
  refresh_timer = nil,
}

local namespace = vim.api.nvim_create_namespace("LeeHaRinRoutineJobs")
local augroup = vim.api.nvim_create_augroup("LeeHaRinRoutineJobs", { clear = true })

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Routine Jobs" })
end

local function run(command, callback)
  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      callback(result)
    end)
  end)
end

local function parse_properties(output)
  local properties = {}
  for line in (output or ""):gmatch("[^\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then
      properties[key] = value
    end
  end
  return properties
end

local function is_open()
  return state.winid and vim.api.nvim_win_is_valid(state.winid)
end

local function selected_job()
  if not is_open() then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(state.winid)[1]
  while line > 0 do
    if state.line_jobs[line] then
      return state.line_jobs[line]
    end
    line = line - 1
  end
  return nil
end

local function run_status(job)
  local service = job.service_status or {}
  if service.error or not service.LoadState or service.LoadState == "not-found" then
    return "UNKNOWN", "RoutineJobsFailed"
  end
  if service.ActiveState == "activating" then
    return "STARTING", "RoutineJobsRunning"
  end
  if service.ActiveState == "deactivating" then
    return "STOPPING", "RoutineJobsPaused"
  end
  if service.ActiveState == "active" then
    return "RUNNING", "RoutineJobsRunning"
  end
  if service.ActiveState == "failed" then
    return "FAILED", "RoutineJobsFailed"
  end
  return "IDLE", "RoutineJobsManual"
end

local function schedule_status(job)
  if not job.timer then
    return "MANUAL", "RoutineJobsManual"
  end
  local timer = job.timer_status or {}
  if timer.error or not timer.LoadState or timer.LoadState == "not-found" then
    return "UNKNOWN", "RoutineJobsFailed"
  end
  local enabled = timer.UnitFileState == "enabled"
    or timer.UnitFileState == "enabled-runtime"
  if timer.ActiveState == "active" and enabled then
    return "SCHEDULED", "RoutineJobsScheduled"
  end
  if timer.ActiveState ~= "active" and not enabled then
    return "PAUSED", "RoutineJobsPaused"
  end
  return "ATTENTION", "RoutineJobsFailed"
end

local function job_status(job)
  local schedule, schedule_group = schedule_status(job)
  local execution, execution_group = run_status(job)
  if execution ~= "IDLE" then
    return schedule .. " · " .. execution, execution_group
  end
  if schedule == "UNKNOWN" or schedule == "ATTENTION" then
    return schedule .. " · " .. execution, schedule_group
  end
  return schedule .. " · " .. execution, schedule_group
end

local function parse_systemd_timespan(value)
  local units = {
    d = 86400,
    h = 3600,
    min = 60,
    s = 1,
    ms = 0.001,
    us = 0.000001,
  }
  local seconds = 0
  local found = false
  for amount, unit in (value or ""):gmatch("([%d.]+)%s*(%a+)") do
    if units[unit] then
      seconds = seconds + tonumber(amount) * units[unit]
      found = true
    end
  end
  return found and seconds or nil
end

local function monotonic_next_run(value)
  local target = parse_systemd_timespan(value)
  local uptime_file = io.open("/proc/uptime", "r")
  if not target or not uptime_file then
    return nil
  end
  local uptime = tonumber((uptime_file:read("*l") or ""):match("^[%d.]+"))
  uptime_file:close()
  if not uptime then
    return nil
  end
  local remaining = math.max(0, math.ceil(target - uptime))
  if remaining < 60 then
    return string.format("in %ds", remaining)
  end
  if remaining < 3600 then
    return string.format("in %dm", math.ceil(remaining / 60))
  end
  return string.format("in %dh", math.ceil(remaining / 3600))
end

local function schedule_is_active(job)
  local timer = job.timer_status or {}
  return timer.ActiveState == "active"
    and (timer.UnitFileState == "enabled" or timer.UnitFileState == "enabled-runtime")
end

local function schedule_can_toggle(job)
  local status = schedule_status(job)
  if status == "UNKNOWN" or status == "ATTENTION" then
    return false
  end
  return true
end

local function next_run(job)
  if not job.timer then
    return "No schedule"
  end
  local timer = job.timer_status or {}
  if timer.error or not timer.LoadState or timer.LoadState == "not-found" then
    return "Next run unavailable"
  end
  if timer.ActiveState ~= "active" then
    return "Schedule paused"
  end
  local value = timer.NextElapseUSecRealtime
  if value and value ~= "" and value ~= "n/a" then
    return value
  end
  return monotonic_next_run(timer.NextElapseUSecMonotonic) or "Next run pending"
end

local function set_modifiable(bufnr, value)
  vim.bo[bufnr].modifiable = value
end

local function render()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local lines = {
    " Routine Jobs",
    " r run now   x stop   s enable/pause schedule   l logs   e edit   R refresh   q close",
    "",
  }
  local highlights = {
    { line = 1, group = "Title", start_col = 1, end_col = -1 },
    { line = 2, group = "Comment", start_col = 1, end_col = -1 },
  }
  state.line_jobs = {}

  if #state.jobs == 0 then
    lines[#lines + 1] = " No predefined jobs. Add jobs in the routine_jobs setup in init.lua."
    highlights[#highlights + 1] = {
      line = #lines,
      group = "Comment",
      start_col = 1,
      end_col = -1,
    }
  end

  for _, job in ipairs(state.jobs) do
    local status, status_group = job_status(job)
    local marker = job.loading and "…" or "●"
    local row = string.format(" %s %-22s %-22s %s", marker, job.name, status, next_run(job))
    lines[#lines + 1] = row
    state.line_jobs[#lines] = job
    highlights[#highlights + 1] = {
      line = #lines,
      group = status_group,
      start_col = 1,
      end_col = -1,
    }

    lines[#lines + 1] = "   " .. (job.description or job.service)
    state.line_jobs[#lines] = job
    highlights[#highlights + 1] = {
      line = #lines,
      group = "Comment",
      start_col = 0,
      end_col = -1,
    }
  end

  set_modifiable(state.bufnr, true)
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.bufnr, namespace, 0, -1)
  for _, item in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      state.bufnr,
      namespace,
      item.group,
      item.line - 1,
      item.start_col,
      item.end_col
    )
  end
  set_modifiable(state.bufnr, false)
end

local function refresh_job(job, generation)
  local remaining = job.timer and 2 or 1

  local function completed()
    remaining = remaining - 1
    if remaining == 0 and generation == state.generation then
      job.loading = false
      render()
    end
  end

  job.loading = true
  run({
    "systemctl", "--user", "show", job.service, "--no-pager",
    "--property=LoadState", "--property=ActiveState", "--property=SubState",
  }, function(result)
    if generation ~= state.generation then
      return
    end
    job.service_status = parse_properties(result.stdout)
    job.service_status.error = result.code ~= 0 and result.stderr or nil
    completed()
  end)

  if job.timer then
    run({
      "systemctl", "--user", "show", job.timer, "--no-pager",
      "--property=LoadState", "--property=ActiveState", "--property=SubState",
      "--property=UnitFileState", "--property=NextElapseUSecRealtime",
      "--property=NextElapseUSecMonotonic",
      "--property=LastTriggerUSec",
    }, function(result)
      if generation ~= state.generation then
        return
      end
      job.timer_status = parse_properties(result.stdout)
      job.timer_status.error = result.code ~= 0 and result.stderr or nil
      completed()
    end)
  end
end

function M.refresh()
  state.generation = state.generation + 1
  local generation = state.generation
  for _, job in ipairs(state.jobs) do
    refresh_job(job, generation)
  end
  render()
end

local function confirm(prompt, action, callback)
  vim.ui.select({ "Cancel", action }, { prompt = prompt }, function(choice)
    if choice == action then
      callback()
    end
  end)
end

local function run_now()
  local job = selected_job()
  if not job then
    return
  end
  confirm("Run " .. job.name .. " now?", "Run now", function()
    run({ "systemctl", "--user", "start", "--no-block", job.service }, function(result)
      if result.code == 0 then
        notify(job.name .. " start requested; refreshing status")
      else
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
      M.refresh()
    end)
  end)
end

local function stop_job()
  local job = selected_job()
  if not job then
    return
  end
  local execution = run_status(job)
  if execution ~= "RUNNING" and execution ~= "STARTING" then
    notify(job.name .. " is not running")
    return
  end
  confirm("Stop the current " .. job.name .. " run?", "Stop run", function()
    run({ "systemctl", "--user", "stop", job.service }, function(result)
      if result.code == 0 then
        notify(job.name .. " stop requested; refreshing status")
      else
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
      M.refresh()
    end)
  end)
end

local function toggle_schedule()
  local job = selected_job()
  if not job then
    return
  end
  if not job.timer then
    notify(job.name .. " is a manual-only job")
    return
  end

  if not schedule_can_toggle(job) then
    notify("Schedule state is unavailable or needs attention", vim.log.levels.ERROR)
    return
  end
  local scheduled = schedule_is_active(job)
  local action = scheduled and "Pause schedule" or "Enable schedule"
  confirm(action .. " for " .. job.name .. "?", action, function()
    local verb = scheduled and "disable" or "enable"
    run({ "systemctl", "--user", verb, "--now", job.timer }, function(result)
      if result.code == 0 then
        notify(job.name .. (scheduled
          and " pause accepted; refreshing status"
          or " enable accepted; refreshing status"))
      else
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
      M.refresh()
    end)
  end)
end

local function show_logs()
  local job = selected_job()
  if not job then
    return
  end
  run({ "journalctl", "--user-unit=" .. job.service, "-n", "100", "--no-pager", "--output=short-iso" }, function(result)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      return
    end
    vim.cmd("botright vsplit")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_name(bufnr, "Routine Job Logs: " .. job.name)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "log"
    local log_lines = vim.split(result.stdout or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, log_lines)
    vim.bo[bufnr].modifiable = false
    vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = bufnr, silent = true })
  end)
end

local function edit_job()
  local job = selected_job()
  if not job then
    return
  end
  local path = job.edit_path or job.timer_path or job.service_path
  if not path then
    notify("No editable definition is configured for " .. job.name)
    return
  end
  M.close()
  vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.expand(path)))
end

function M.close()
  state.generation = state.generation + 1
  if state.refresh_timer then
    state.refresh_timer:stop()
    state.refresh_timer:close()
    state.refresh_timer = nil
  end
  if is_open() then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

local function configure_buffer(bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "RoutineJobs"
  vim.bo[bufnr].modifiable = false

  local keymaps = {
    { "r", run_now, "Run routine job now" },
    { "x", stop_job, "Stop the current routine job run" },
    { "s", toggle_schedule, "Enable or pause routine schedule" },
    { "l", show_logs, "Show routine job logs" },
    { "<CR>", show_logs, "Show routine job logs" },
    { "e", edit_job, "Edit routine job definition" },
    { "R", M.refresh, "Refresh routine jobs" },
    { "q", M.close, "Close routine jobs" },
    { "<Esc>", M.close, "Close routine jobs" },
  }
  for _, mapping in ipairs(keymaps) do
    vim.keymap.set("n", mapping[1], mapping[2], {
      buffer = bufnr,
      silent = true,
      desc = mapping[3],
    })
  end
end

function M.open()
  if is_open() then
    vim.api.nvim_set_current_win(state.winid)
    M.refresh()
    return
  end

  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.bufnr, "Routine Jobs")
    configure_buffer(state.bufnr)
  end

  vim.cmd("botright " .. config.height .. "split")
  state.winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.winid, state.bufnr)
  local window_options = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    cursorline = true,
    winfixheight = true,
    wrap = false,
    winbar = "%#Title# Routine Jobs",
  }
  for name, value in pairs(window_options) do
    vim.api.nvim_set_option_value(name, value, { win = state.winid })
  end
  M.refresh()
  if #state.jobs > 0 then
    vim.api.nvim_win_set_cursor(state.winid, { 4, 0 })
  end
  state.refresh_timer = vim.uv.new_timer()
  state.refresh_timer:start(config.refresh_ms, config.refresh_ms, function()
    vim.schedule(function()
      if is_open() then
        M.refresh()
      end
    end)
  end)
end

function M.toggle()
  if is_open() then
    M.close()
  else
    M.open()
  end
end

function M.setup(opts)
  local next_config = vim.tbl_deep_extend("force", {}, config, opts or {})
  if type(next_config.refresh_ms) ~= "number" or next_config.refresh_ms < 1000 then
    error("routine jobs refresh_ms must be at least 1000")
  end
  local seen = {}
  for _, job in ipairs(next_config.jobs) do
    if type(job.name) ~= "string" or job.name == "" then
      error("routine job name must be a non-empty string")
    end
    if type(job.service) ~= "string"
      or not job.service:match("^[%w@_.%-]+%.service$")
      or job.service:sub(1, 1) == "-"
    then
      error("invalid routine job service for " .. job.name)
    end
    if job.timer and (
      type(job.timer) ~= "string"
      or not job.timer:match("^[%w@_.%-]+%.timer$")
      or job.timer:sub(1, 1) == "-"
    ) then
      error("invalid routine job timer for " .. job.name)
    end
    if seen[job.service] then
      error("duplicate routine job service: " .. job.service)
    end
    seen[job.service] = true
  end
  config = next_config
  state.jobs = vim.deepcopy(config.jobs)

  vim.api.nvim_set_hl(0, "RoutineJobsRunning", { link = "DiagnosticInfo" })
  vim.api.nvim_set_hl(0, "RoutineJobsScheduled", { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, "RoutineJobsPaused", { link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, "RoutineJobsManual", { link = "Comment" })
  vim.api.nvim_set_hl(0, "RoutineJobsFailed", { link = "DiagnosticError" })

  vim.api.nvim_clear_autocmds({ group = augroup })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      if state.winid and tonumber(args.match) == state.winid then
        state.winid = nil
        state.generation = state.generation + 1
        if state.refresh_timer then
          state.refresh_timer:stop()
          state.refresh_timer:close()
          state.refresh_timer = nil
        end
      end
    end,
  })
end

return M
