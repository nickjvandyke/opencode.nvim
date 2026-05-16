local M = {}

---Try to start an `opencode` server via `opts.server.start`.
local function start()
  local server_opts = require("opencode.config").opts.server or {}

  if not server_opts.start then
    error("No `opts.server.start` function configured", 0)
  end

  local start_ok, start_result = pcall(server_opts.start)
  if not start_ok then
    return error("Failed to start `opencode`: " .. start_result, 0)
  end
end

---Find an `opencode` server. Tries, in order:
---
---1. The currently subscribed server in `opencode.events`.
---2. The configured port in `require("opencode.config").opts.port`.
---3. All local servers that overlap with Neovim's CWD. Automatically returns if just one, otherwise prompts to select from those.
---@return Promise<opencode.server.Server>
local function find()
  local Promise = require("opencode.promise")
  local port_opt = require("opencode.config").opts.server.port
  local connected_server = require("opencode.events").connected_server

  return connected_server and Promise.resolve(connected_server)
    or type(port_opt) == "number" and require("opencode.server").new(port_opt):catch(function(err)
      if err then
        error(err, 0)
      else
        error("No `opencode` responding on port " .. port_opt, 0)
      end
    end)
    or type(port_opt) == "function"
      and Promise.new(function(resolve, reject)
        port_opt(function(port) ---@param port number|nil
          if port then
            resolve(port)
          else
            reject("Configured port resolved to `nil`")
          end
        end)
      end):next(function(port)
        return require("opencode.server").new(port)
      end)
    or M.get_all():next(function(servers) ---@param servers opencode.server.Server[]
      local nvim_cwd = vim.fn.getcwd()
      local servers_sharing_cwd = vim.tbl_filter(function(server)
        -- Overlaps in either direction, with no non-empty mismatch
        return server.cwd:find(nvim_cwd, 0, true) == 1 or nvim_cwd:find(server.cwd, 0, true) == 1
      end, servers)

      if #servers_sharing_cwd == 0 then
        -- We prefer falling back to `opts.server.start` over selecting from servers that don't match the CWD.
        -- Manual selection is still available for that rare need.
        error("No `opencode` servers found with overlapping CWD", 0)
      elseif #servers_sharing_cwd == 1 then
        return servers_sharing_cwd[1]
      else
        return require("opencode.ui.select_server").select_server(servers_sharing_cwd)
      end
    end)
end

---Poll for an `opencode` server, rejecting if not found within five seconds.
---@return Promise<opencode.server.Server>
local function poll()
  local Promise = require("opencode.promise")
  local poll_timer, timer_err, timer_errname = vim.uv.new_timer()
  if not poll_timer then
    return Promise.reject("Failed to create timer to poll for `opencode`: " .. timer_errname .. ": " .. timer_err)
  end

  local retries = 0
  return Promise.new(function(resolve, reject)
    poll_timer:start(
      1000,
      1000,
      vim.schedule_wrap(function()
        find()
          :next(function(server)
            resolve(server)
          end)
          :catch(function(err)
            retries = retries + 1
            if retries >= 5 then
              reject(err)
            else
              -- Wait for next retry
            end
          end)
      end)
    )
  end):finally(function()
    poll_timer:stop()
    poll_timer:close()
  end)
end

---@return Promise<opencode.server.Server>
function M.get()
  local Promise = require("opencode.promise")
  local connected_server = require("opencode.events").connected_server

  return find()
    :catch(function(err)
      if not err then
        -- Do nothing when server selection was cancelled
        return Promise.reject()
      end

      local start_ok = pcall(start)
      if not start_ok then
        -- Propagate original error.
        -- Maybe concat start error?
        return Promise.reject(err)
      end

      return poll()
    end)
    :next(function(server) ---@param server opencode.server.Server
      if not connected_server or connected_server.port ~= server.port then
        require("opencode.events").connect(server)
      end
      return server
    end)
end

---@return Promise<opencode.server.Server[]>
function M.get_all()
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    local processes = require("opencode.server.discovery.process").get()
    if #processes == 0 then
      reject("No `opencode ... --port` processes found")
    else
      resolve(processes)
    end
  end):next(function(processes) ---@param processes opencode.server.discovery.process.Process[]
    return Promise.all_settled(vim.tbl_map(function(process) ---@param process opencode.server.discovery.process.Process
      return require("opencode.server").new(process.port)
    end, processes)):next(
      function(results) ---@param results { status: string, value?: opencode.server.Server, reason?: any }[]
        local servers = {}
        for _, result in ipairs(results) do
          -- We expect non-servers to reject
          if result.status == "fulfilled" then
            table.insert(servers, result.value)
          end
        end

        if #servers == 0 then
          -- Prefer to surface a rejection from a valid server (e.g. unauthenticated)
          for _, result in ipairs(results) do
            if result.status == "rejected" and result.reason then
              error(result.reason, 0)
            end
          end

          error("No `opencode` servers found", 0)
        end
        return servers
      end
    )
  end)
end

return M
