---Shared process management utilities for opencode providers.
---
---WORKAROUND: This module exists to work around an upstream bug where the opencode process
---does not terminate cleanly when it receives SIGHUP (it daemonizes/respawns instead).
---See: https://github.com/anomalyco/opencode/issues/13001
---Once that issue is fixed, this module can be removed and providers can use their
---native stop mechanisms (jobstop, tmux kill-pane, etc.) directly.
local M = {}

---Capture the PID associated with a Neovim terminal job.
---@param job_id number The terminal job ID (from `vim.b[buf].terminal_job_id`)
---@return number|nil pid The process ID, or nil if it could not be resolved
function M.capture_pid(job_id)
  local ok, pid = pcall(vim.fn.jobpid, job_id)
  if ok then
    return pid
  end
  return nil
end

---Capture the PID of the process running in a tmux pane.
---@param pane_id string The tmux pane ID (e.g., "%42")
---@return number|nil pid The process ID, or nil if it could not be resolved
function M.capture_tmux_pid(pane_id)
  local pid_str = vim.trim(vim.fn.system("tmux display-message -p -t " .. pane_id .. " '#{pane_pid}'"))
  return tonumber(pid_str)
end

---Terminate the process and its children reliably.
---
---Uses the cached PID to kill the entire process group, which is more reliable
---than jobstop during VimLeavePre because:
--- 1. os.execute is synchronous (vim.fn.system spawns a job that Neovim kills during shutdown)
--- 2. Negative PID sends SIGTERM to the entire process group (children included)
--- 3. jobstop sends SIGHUP which can cause the process to daemonize/respawn
---@param pid number|nil The cached process ID
---@return boolean killed Whether the process was successfully terminated
function M.kill(pid)
  if not pid then
    return false
  end

  if vim.fn.has("unix") == 1 then
    return os.execute("kill -TERM -" .. pid .. " 2>/dev/null") ~= nil
  else
    return pcall(vim.uv.kill, pid, "sigterm")
  end
end

return M
