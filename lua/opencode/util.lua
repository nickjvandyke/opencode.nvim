local M = {}

---Errors if a system call returned a non-zero exit code or no output.
---
---Ignores exit code 1 if there is no stderr, as many commands
---use this code when there are no results (e.g., `pgrep`, `lsof`, `ps`).
---
---@param obj vim.SystemCompleted
---@param cmd string
function M.check_system_call(obj, cmd)
  cmd = "`" .. cmd .. "`"
  if obj.code ~= 0 and (obj.code ~= 1 or obj.stderr ~= "") then
    error(string.format("%s failed with code %d\n%s", cmd, obj.code, obj.stderr), 0)
  elseif not obj.stdout then
    error(string.format("%s did not return any output", cmd), 0)
  end
end

return M
