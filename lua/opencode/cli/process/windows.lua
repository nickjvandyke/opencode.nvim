local M = {}

---@return opencode.cli.process.Process[]
function M.get()
  assert(vim.fn.has("win32") == 1, "`opencode.cli.process.windows.get` should only be called on Windows")

  local ps_script = [[
Get-Process -Name '*opencode*' -ErrorAction SilentlyContinue |
ForEach-Object {
  $ports = Get-NetTCPConnection -State Listen -OwningProcess $_.Id -ErrorAction SilentlyContinue
  if ($ports) {
    foreach ($port in $ports) {
      [PSCustomObject]@{pid=$_.Id; port=$port.LocalPort}
    }
  }
} | ConvertTo-Json -Compress
]]
  local ps = vim.system({ "powershell", "-NoProfile", "-Command", ps_script }):wait()
  require("opencode.util").check_system_call(ps, "PowerShell")
  if ps.stdout == "" then
    return {}
  end
  -- The Powershell script should return the response as JSON to ease parsing.
  local ok, processes = pcall(vim.fn.json_decode, ps.stdout)
  if not ok then
    error("Failed to parse PowerShell output: " .. tostring(processes), 0)
  end
  if processes.pid then
    -- A single process was found, so wrap it in a table.
    processes = { processes }
  end
  return processes
end

return M
