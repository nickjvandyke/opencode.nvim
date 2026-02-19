---Shared process management utilities for providers that run opencode inside Neovim's job system.
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

---Terminate the process and its children reliably.
---
---Uses the cached PID to kill the entire process group, which is more reliable
---than jobstop during VimLeavePre because:
--- 1. os.execute is synchronous (vim.fn.system spawns a job that Neovim kills during shutdown)
--- 2. Negative PID sends SIGTERM to the entire process group (children included)
--- 3. jobstop sends SIGHUP which can cause the process to daemonize/respawn
---
---Falls back to jobstop only when no PID is available.
---@param pid number|nil The cached process ID
---@param job_id number|nil The Neovim job ID (for jobstop fallback)
---@return boolean killed Whether the process was successfully terminated
function M.kill(pid, job_id)
  if pid then
    if vim.fn.has("unix") == 1 then
      return os.execute("kill -TERM -" .. pid .. " 2>/dev/null") ~= nil
    else
      return pcall(vim.uv.kill, pid, "sigterm")
    end
  end

  -- Fall back to jobstop if we don't have a PID.
  -- Avoid combining both: jobstop sends SIGHUP which can cause the process to respawn.
  if job_id then
    pcall(vim.fn.jobstop, job_id)
    return true
  end

  return false
end

return M
