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

local namespace = vim.api.nvim_create_namespace("AgenticVimRoutineJobs")
local augroup = vim.api.nvim_create_augroup("AgenticVimRoutineJobs", { clear = true })

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
  local statuses = { job.service_status or {} }
  if job.reconcile_service then
    statuses[#statuses + 1] = job.reconcile_service_status or {}
  end

  for _, service in ipairs(statuses) do
    if service.error or not service.LoadState or service.LoadState == "not-found" then
      return "UNKNOWN", "RoutineJobsFailed"
    end
  end
  for _, service in ipairs(statuses) do
    if service.ActiveState == "failed" or service.SubState == "failed" then
      return "FAILED", "RoutineJobsFailed"
    end
  end
  for _, service in ipairs(statuses) do
    if service.ActiveState == "activating" then
      return "STARTING", "RoutineJobsRunning"
    end
  end
  for _, service in ipairs(statuses) do
    if service.ActiveState == "deactivating" then
      return "STOPPING", "RoutineJobsPaused"
    end
  end
  for _, service in ipairs(statuses) do
    if service.ActiveState == "active" then
      return "RUNNING", "RoutineJobsRunning"
    end
  end
  return "IDLE", "RoutineJobsManual"
end

local function unit_file_enabled(status)
  return status.UnitFileState == "enabled"
    or status.UnitFileState == "enabled-runtime"
end

local function automatic_units(job)
  local units = {}
  if job.timer then
    units[#units + 1] = job.timer_status or {}
  end
  if job.watcher then
    units[#units + 1] = job.watcher_status or {}
  end
  return units
end

local function schedule_status(job)
  local units = automatic_units(job)
  if #units == 0 then
    return "MANUAL", "RoutineJobsManual"
  end

  local all_active = true
  local all_enabled = true
  local all_inactive = true
  local all_disabled = true
  for _, unit in ipairs(units) do
    if unit.error or not unit.LoadState or unit.LoadState == "not-found" then
      return "UNKNOWN", "RoutineJobsFailed"
    end
    if unit.ActiveState == "failed" or unit.SubState == "failed" then
      return "FAILED", "RoutineJobsFailed"
    end
    local enabled = unit_file_enabled(unit)
    all_active = all_active and unit.ActiveState == "active"
    all_enabled = all_enabled and enabled
    all_inactive = all_inactive and unit.ActiveState == "inactive"
    all_disabled = all_disabled and not enabled
  end

  if all_active and all_enabled then
    return job.watcher and "AUTOMATIC" or "SCHEDULED", "RoutineJobsScheduled"
  end
  if all_inactive and all_disabled then
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

local function schedule_can_toggle(job)
  local status = schedule_status(job)
  return status ~= "UNKNOWN"
end

local function schedule_has_enabled_or_active_unit(job)
  for _, unit in ipairs(automatic_units(job)) do
    if unit_file_enabled(unit) or unit.ActiveState == "active"
      or unit.ActiveState == "activating" or unit.ActiveState == "failed"
    then
      return true
    end
  end
  return false
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

local function unit_details(label, name, status)
  status = status or {}
  return string.format(
    "   %-9s %-38s load=%s active=%s sub=%s file=%s",
    label,
    name,
    status.LoadState or "?",
    status.ActiveState or "?",
    status.SubState or "?",
    status.UnitFileState or "n/a"
  )
end

local function render()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local lines = {
    " Routine Jobs",
    " r run now   x stop runs   s enable/pause automatic   l logs   e edit   R refresh   q close",
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

    lines[#lines + 1] = unit_details("service", job.service, job.service_status)
    state.line_jobs[#lines] = job
    highlights[#highlights + 1] = {
      line = #lines,
      group = "Comment",
      start_col = 0,
      end_col = -1,
    }
    if job.reconcile_service then
      lines[#lines + 1] = unit_details(
        "reconcile",
        job.reconcile_service,
        job.reconcile_service_status
      )
      state.line_jobs[#lines] = job
      highlights[#highlights + 1] = {
        line = #lines,
        group = "Comment",
        start_col = 0,
        end_col = -1,
      }
    end
    if job.timer then
      lines[#lines + 1] = unit_details("timer", job.timer, job.timer_status)
      state.line_jobs[#lines] = job
      highlights[#highlights + 1] = {
        line = #lines,
        group = "Comment",
        start_col = 0,
        end_col = -1,
      }
    end
    if job.watcher then
      lines[#lines + 1] = unit_details("watcher", job.watcher, job.watcher_status)
      state.line_jobs[#lines] = job
      highlights[#highlights + 1] = {
        line = #lines,
        group = "Comment",
        start_col = 0,
        end_col = -1,
      }
    end
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
  local remaining = 1
    + (job.reconcile_service and 1 or 0)
    + (job.timer and 1 or 0)
    + (job.watcher and 1 or 0)

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

  if job.reconcile_service then
    run({
      "systemctl", "--user", "show", job.reconcile_service, "--no-pager",
      "--property=LoadState", "--property=ActiveState", "--property=SubState",
    }, function(result)
      if generation ~= state.generation then
        return
      end
      job.reconcile_service_status = parse_properties(result.stdout)
      job.reconcile_service_status.error = result.code ~= 0 and result.stderr or nil
      completed()
    end)
  end

  if job.watcher then
    run({
      "systemctl", "--user", "show", job.watcher, "--no-pager",
      "--property=LoadState", "--property=ActiveState", "--property=SubState",
      "--property=UnitFileState", "--property=Result",
    }, function(result)
      if generation ~= state.generation then
        return
      end
      job.watcher_status = parse_properties(result.stdout)
      job.watcher_status.error = result.code ~= 0 and result.stderr or nil
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

  local units = {}
  local service = job.service_status or {}
  if service.ActiveState == "active" or service.ActiveState == "activating" then
    units[#units + 1] = job.service
  end
  local reconcile = job.reconcile_service_status or {}
  if job.reconcile_service
    and (reconcile.ActiveState == "active" or reconcile.ActiveState == "activating")
  then
    units[#units + 1] = job.reconcile_service
  end
  if #units == 0 then
    notify(job.name .. " is not running")
    return
  end

  confirm("Stop active " .. job.name .. " runs?", "Stop runs", function()
    local command = { "systemctl", "--user", "stop" }
    vim.list_extend(command, units)
    run(command, function(result)
      if result.code == 0 then
        notify(job.name .. " stop accepted; refreshing status")
      else
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
      M.refresh()
    end)
  end)
end

local function automatic_unit_names(job, enabling)
  local units = {}
  if enabling then
    if job.watcher then
      units[#units + 1] = job.watcher
    end
    if job.timer then
      units[#units + 1] = job.timer
    end
  else
    if job.timer then
      units[#units + 1] = job.timer
    end
    if job.watcher then
      units[#units + 1] = job.watcher
    end
  end
  return units
end

local function change_automatic_units(job, enabling, callback)
  local units = automatic_unit_names(job, enabling)
  local changed = {}
  local errors = {}

  local function rollback(index)
    if index == 0 then
      callback(errors)
      return
    end
    run({ "systemctl", "--user", "disable", "--now", changed[index] }, function(result)
      if result.code ~= 0 then
        errors[#errors + 1] = "rollback " .. changed[index] .. ": " .. vim.trim(result.stderr)
      end
      rollback(index - 1)
    end)
  end

  local function step(index)
    if index > #units then
      callback(errors)
      return
    end
    local verb = enabling and "enable" or "disable"
    run({ "systemctl", "--user", verb, "--now", units[index] }, function(result)
      if result.code == 0 then
        changed[#changed + 1] = units[index]
        step(index + 1)
        return
      end

      errors[#errors + 1] = units[index] .. ": " .. vim.trim(result.stderr)
      if enabling then
        rollback(#changed)
      else
        -- Continue pausing after an error so the other automatic trigger is
        -- still stopped whenever possible.
        step(index + 1)
      end
    end)
  end

  step(1)
end

local function toggle_schedule()
  local job = selected_job()
  if not job then
    return
  end
  if not job.timer and not job.watcher then
    notify(job.name .. " is a manual-only job")
    return
  end

  if not schedule_can_toggle(job) then
    notify("Automatic state is unavailable", vim.log.levels.ERROR)
    return
  end
  local scheduled = schedule_has_enabled_or_active_unit(job)
  local action = scheduled and "Pause automatic" or "Enable automatic"
  confirm(action .. " for " .. job.name .. "?", action, function()
    change_automatic_units(job, not scheduled, function(errors)
      if #errors == 0 then
        notify(job.name .. (scheduled
          and " pause accepted; refreshing status"
          or " enable accepted; refreshing status"))
      else
        notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
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
  local command = { "journalctl" }
  command[#command + 1] = "--user-unit=" .. job.service
  if job.reconcile_service then
    command[#command + 1] = "--user-unit=" .. job.reconcile_service
  end
  if job.watcher then
    command[#command + 1] = "--user-unit=" .. job.watcher
  end
  vim.list_extend(command, { "-n", "100", "--no-pager", "--output=short-iso" })
  run(command, function(result)
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
    { "x", stop_job, "Stop active routine job runs" },
    { "s", toggle_schedule, "Enable or pause automatic routine job triggers" },
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
  local function validate_service(unit, label, job_name)
    if type(unit) ~= "string"
      or not unit:match("^[%w@_.%-]+%.service$")
      or unit:sub(1, 1) == "-"
    then
      error("invalid routine job " .. label .. " for " .. job_name)
    end
    if seen[unit] then
      error("duplicate routine job unit: " .. unit)
    end
    seen[unit] = true
  end

  for _, job in ipairs(next_config.jobs) do
    if type(job.name) ~= "string" or job.name == "" then
      error("routine job name must be a non-empty string")
    end
    validate_service(job.service, "service", job.name)
    if job.reconcile_service then
      validate_service(job.reconcile_service, "reconcile service", job.name)
    end
    if job.watcher then
      validate_service(job.watcher, "watcher", job.name)
    end
    if job.timer and (
      type(job.timer) ~= "string"
      or not job.timer:match("^[%w@_.%-]+%.timer$")
      or job.timer:sub(1, 1) == "-"
    ) then
      error("invalid routine job timer for " .. job.name)
    end
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
