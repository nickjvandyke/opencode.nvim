local M = {}

---An `opencode` server process and some details about it.
---@class opencode.cli.server.Server
---@field port number
---@field cwd string
---@field title string

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

---@param port number
---@return Promise<opencode.cli.server.Server>
local function get_server(port)
  local Promise = require("opencode.promise")
  return Promise
    .new(function(resolve, reject)
      require("opencode.cli.client").get_path(port, function(path)
        local cwd = path.directory or path.worktree
        if cwd then
          resolve(cwd)
        else
          reject("No `opencode` responding on port: " .. port)
        end
      end, function()
        reject("No `opencode` responding on port: " .. port)
      end)
    end)
    -- Serial instead of parallel so that `get_path` has verified it's a server
    :next(
      function(cwd) ---@param cwd string
        return Promise.new(function(resolve)
          require("opencode.cli.client").get_sessions(port, function(session)
            -- This will be the most recently interacted session.
            -- Unfortunately `opencode` doesn't provide a way to get the currently selected TUI session.
            -- But they will probably have interacted with the session they want to connect to most recently.
            local title = session[1] and session[1].title or "<No sessions>"
            resolve({ cwd, title })
          end)
        end)
      end
    )
    :next(function(results) ---@param results { [1]: string, [2]: string }
      local cwd = results[1]
      local title = results[2]
      return {
        port = port,
        cwd = cwd,
        title = title,
      }
    end)
end

---@return Promise<opencode.cli.server.Server[]>
local function get_all_servers()
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    local processes
    if is_windows() then
      processes = get_processes_windows()
    else
      processes = get_processes_unix()
    end
    if #processes == 0 then
      reject("No `opencode` processes found")
    else
      resolve(processes)
    end
  end):next(function(processes) ---@param processes opencode.cli.server.Process[]
    local get_servers = vim.tbl_map(function(process) ---@param process opencode.cli.server.Process
      return get_server(process.port)
    end, processes)
    return Promise.all_settled(get_servers):next(function(results)
      local servers = {}
      for _, result in ipairs(results) do
        -- We expect non-servers to reject
        if result.status == "fulfilled" then
          table.insert(servers, result.value)
        end
      end
      if #servers == 0 then
        error("No `opencode` servers found", 0)
      end
      return servers
    end)
  end)
end

---@return Promise<opencode.cli.server.Server[]>
function M.get_all_servers_in_nvim_cwd()
  return get_all_servers():next(function(servers) ---@param servers opencode.cli.server.Server[]
    local cwd_matching_servers = {}
    local nvim_cwd = vim.fn.getcwd()
    for _, server in ipairs(servers) do
      -- Filter for servers in the same CWD as Neovim
      local normalized_server_cwd = server.cwd
      local normalized_nvim_cwd = nvim_cwd
      if is_windows() then
        -- On Windows, normalize to backslashes for consistent comparison
        normalized_server_cwd = server.cwd:gsub("/", "\\")
        normalized_nvim_cwd = nvim_cwd:gsub("/", "\\")
      end
      if normalized_nvim_cwd == normalized_server_cwd then
        table.insert(cwd_matching_servers, server)
      end
    end
    if #cwd_matching_servers == 0 then
      error("No `opencode` servers found in Neovim's CWD: " .. nvim_cwd, 0)
    end
    return cwd_matching_servers
  end)
end

---Attempt to get the `opencode` server's port. Tries, in order:
---
---1. The currently subscribed server in `opencode.events`.
---2. The configured port in `require("opencode.config").opts.port`.
---3. Any server in Neovim's CWD, prompting the user to select if multiple are found.
---4. Calling `require("opencode.provider").start()` to launch a new server, then retrying the above.
---
---Upon success, subscribes to the server's events.
---
---@param launch boolean? Whether to launch a new server if none found. Defaults to true.
---@return Promise<opencode.cli.server.Server>
function M.get(launch)
  launch = launch ~= false

  local Promise = require("opencode.promise")
  return Promise.resolve(
    require("opencode.events").connected_server and require("opencode.events").connected_server.port
      or require("opencode.config").opts.port
  )
    :next(function(priority_port) ---@param priority_port number
      if priority_port then
        return Promise.resolve(priority_port)
      else
        return M.get_all_servers_in_nvim_cwd():next(function(servers) ---@param servers opencode.cli.server.Server[]
          if #servers == 1 then
            return servers[1].port
          else
            return require("opencode.ui.select_server")
              .select_server(servers)
              :next(function(selected_server) ---@param selected_server opencode.cli.server.Server
                return selected_server.port
              end)
          end
        end)
      end
    end)
    :next(function(port) ---@param port number
      return get_server(port)
    end)
    :next(function(server) ---@param server opencode.cli.server.Server
      require("opencode.events").connect(server)
      return server
    end)
    :catch(function(err)
      if not err then
        -- Do nothing when select is cancelled
        return Promise.reject()
      end

      return Promise.new(function(resolve, reject)
        if launch then
          local start_ok, start_result = pcall(require("opencode.provider").start)
          if not start_ok then
            return reject("Error starting `opencode`: " .. start_result)
          end

          -- Wait for the provider to start
          vim.defer_fn(function()
            resolve(true)
          end, 2000)
        else
          -- Don't attempt to recover, just propagate the original error
          reject(err)
        end
      end):next(function()
        -- Retry
        return M.get(false)
      end)
    end)
end

return M
