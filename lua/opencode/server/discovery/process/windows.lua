local M = {}

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

---@return Promise<opencode.server.discovery.process.Process[]>
function M.get()
  local Promise = require("opencode.promise")

  return require("opencode.promise.system")
    .system({ "powershell", "-NoProfile", "-Command", ps_script })
    :next(function(ps_stdout)
      if ps_stdout == "" then
        return Promise.resolve({})
      end

      local ok, processes = pcall(vim.fn.json_decode, ps_stdout)
      if not ok then
        return Promise.reject("Failed to parse `powershell` output: " .. tostring(processes))
      end

      -- A single process was found
      if processes.pid then
        processes = { processes }
      end

      return Promise.resolve(processes)
    end)
end

return M
