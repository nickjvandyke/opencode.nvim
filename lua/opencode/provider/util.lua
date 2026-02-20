local M = {}

---Terminate the process and its children reliably.
---HACK: for upstream issue described in https://github.com/anomalyco/opencode/issues/13001.
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
