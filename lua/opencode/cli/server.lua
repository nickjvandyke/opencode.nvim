local M = {}

---An `opencode` server process.
---@class opencode.cli.server.Server : opencode.cli.server.Process
---
---Populated by calling the server's `/path` endpoint at `port`.
---@field cwd string

---An `opencode` process.
---Retrieval is platform-dependent.
---@class opencode.cli.server.Process
---@field pid number
---@field port number

---@return boolean
local function is_windows()
  return vim.fn.has("win32") == 1
end

---@return opencode.cli.server.Process[]
local function get_processes_unix()
  -- Find PIDs by command line pattern.
  -- We filter for `--port` to avoid matching other `opencode`-related processes (LSPs etc.)
  local pgrep = vim.system({ "pgrep", "-f", "opencode.*--port" }, { text = true }):wait()
  require("opencode.util").check_system_call(pgrep, "pgrep")

  local processes = {}
  for pgrep_line in pgrep.stdout:gmatch("[^\r\n]+") do
    local pid = tonumber(pgrep_line)
    if pid then
      -- Get the port for the PID
      local lsof = vim
        .system({ "lsof", "-w", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-a", "-p", tostring(pid) }, { text = true })
        :wait()
      require("opencode.util").check_system_call(lsof, "lsof")
      for line in lsof.stdout:gmatch("[^\r\n]+") do
        local parts = vim.split(line, "%s+")
        if parts[1] ~= "COMMAND" then -- Skip header
          local port_str = parts[9] and parts[9]:match(":(%d+)$") -- e.g. "127.0.0.1:12345" -> "12345"
          if port_str then
            local port = tonumber(port_str)
            if port then
              table.insert(processes, {
                pid = pid,
                port = port,
              })
            end
          end
        end
      end
    end
  end
  return processes
end

---@return opencode.cli.server.Process[]
local function get_processes_windows()
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

---@return opencode.cli.server.Server[]
local function find_servers()
  local processes
  if is_windows() then
    processes = get_processes_windows()
  else
    processes = get_processes_unix()
  end
  if #processes == 0 then
    error("No `opencode` processes found", 0)
  end
  -- Filter out processes that aren't valid opencode servers.
  -- pgrep -f 'opencode' may match other processes (e.g., language servers
  -- started by opencode) that have 'opencode' in their path or arguments.
  ---@type opencode.cli.server.Server[]
  local servers = {}
  for _, process in ipairs(processes) do
    local ok, path = pcall(require("opencode.cli.client").get_path, process.port)
    if ok then
      table.insert(servers, {
        pid = process.pid,
        port = process.port,
        cwd = path.directory or path.worktree,
      })
    end
  end
  if #servers == 0 then
    error("No valid `opencode` servers found", 0)
  end
  return servers
end

local function is_descendant_of_neovim(pid)
  local neovim_pid = vim.fn.getpid()
  local current_pid = pid
  -- Walk up because the way some shells launch processes,
  -- Neovim will not be the direct parent.
  for _ = 1, 10 do -- limit to 10 steps to avoid infinite loop
    local ps = vim.system({ "ps", "-o", "ppid=", "-p", tostring(current_pid) }, { text = true }):wait()
    require("opencode.util").check_system_call(ps, "ps")
    local parent_pid = tonumber(ps.stdout)
    if not parent_pid then
      return false
    end
    if parent_pid == 1 then
      return false
    elseif parent_pid == neovim_pid then
      return true
    end
    current_pid = parent_pid
  end
  return false
end

---@return opencode.cli.server.Server
local function find_server_inside_nvim_cwd()
  local found_server
  local nvim_cwd = vim.fn.getcwd()
  for _, server in ipairs(find_servers()) do
    local normalized_server_cwd = server.cwd
    local normalized_nvim_cwd = nvim_cwd
    if is_windows() then
      -- On Windows, normalize to backslashes for consistent comparison
      normalized_server_cwd = server.cwd:gsub("/", "\\")
      normalized_nvim_cwd = nvim_cwd:gsub("/", "\\")
    end
    -- CWDs match exactly, or `opencode`'s CWD is under neovim's CWD.
    if normalized_server_cwd:find(normalized_nvim_cwd, 1, true) == 1 then
      found_server = server
      -- On Unix, prioritize embedded
      if not is_windows() and is_descendant_of_neovim(server.pid) then
        break
      end
    end
  end
  if not found_server then
    error("No `opencode` servers inside Neovim's CWD", 0)
  end
  return found_server
end

---@param fn fun(): number Function that checks for the port.
---@param callback fun(ok: boolean, result: any) Called with eventually found port or error if not found after some time.
local function poll_for_port(fn, callback)
  local retries = 0
  local timer = vim.uv.new_timer()
  if not timer then
    callback(false, "Failed to create timer for polling `opencode` port")
    return
  end
  local timer_closed = false
  -- TODO: Suddenly with opentui release,
  -- on startup it seems the port can be available but too quickly calling it will no-op?
  -- Increasing delay for now to mitigate. But more reliable fix may be needed.
  timer:start(
    500,
    500,
    vim.schedule_wrap(function()
      if timer_closed then
        return
      end
      local ok, find_port_result = pcall(fn)
      if ok or retries >= 5 then
        timer_closed = true
        timer:stop()
        timer:close()
        callback(ok, find_port_result)
      else
        retries = retries + 1
      end
    end)
  )
end

---Attempt to get the `opencode` server's port. Tries, in order:
---1. A process responding on `opts.port`.
---2. Any `opencode` process running inside Neovim's CWD. Prioritizes embedded.
---3. Calling `opts.provider.start` and polling for the port.
---
---@param launch boolean? Whether to launch a new server if none found. Defaults to true.
function M.get_port(launch)
  launch = launch ~= false
  return require("opencode.promise").new(function(resolve, reject)
    local configured_port = require("opencode.config").opts.port
    local find_port_fn = function()
      if configured_port then
        -- Test the configured port
        local ok, path = pcall(require("opencode.cli.client").get_path, configured_port)
        if ok and path then
          return configured_port
        else
          error("No `opencode` responding on configured port: " .. configured_port, 0)
        end
      else
        return find_server_inside_nvim_cwd().port
      end
    end
    local initial_ok, initial_result = pcall(find_port_fn)
    if initial_ok then
      resolve(initial_result)
      return
    end
    if launch then
      vim.notify(initial_result .. " — starting `opencode`…", vim.log.levels.INFO, { title = "opencode" })
      local start_ok, start_result = pcall(require("opencode.provider").start)
      if not start_ok then
        reject("Error starting `opencode`: " .. start_result)
        return
      end
    end
    poll_for_port(find_port_fn, function(ok, result)
      if ok then
        resolve(result)
      else
        reject(result)
      end
    end)
  end)
end

return M
