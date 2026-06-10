local M = {}

local function find()
  local Promise = require("opencode.promise")
  local connected_server = require("opencode.server").connected

  return connected_server and Promise.resolve(connected_server)
    or M.configured()
    or M.locally():next(function(servers) ---@param servers opencode.server.Server[]
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

---Find and connect to an `opencode` server. Tries, in order:
---
---1. The currently connected server.
---2. The configured URL in `require("opencode.config").opts.server.url`.
---3. All local servers that overlap with Neovim's CWD. Automatically returns if just one, otherwise prompts to select from those.
---4. Calling `vim.g.opencode_opts.server.start` and retrying the above for five seconds.
---
---@return Promise<opencode.server.Server>
function M.get()
  local Promise = require("opencode.promise")

  return find()
    :catch(function(err)
      if not err then
        -- Do nothing when server selection was cancelled
        return Promise.reject()
      end

      local start = require("opencode.config").opts.server.start

      if not start then
        -- Propagate original error
        return Promise.reject(err)
      end

      local start_ok, start_result = pcall(start)
      if not start_ok then
        return Promise.reject("Failed to start `opencode`: " .. start_result)
      end

      return poll()
    end)
    :next(function(server) ---@param server opencode.server.Server
      return server:connect()
    end)
end

---Search for `opencode` processes on this machine and resolve them to servers.
---
---@return Promise<opencode.server.Server[]>
function M.locally()
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
      return require("opencode.server").new("http://localhost:" .. process.port)
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

---@return Promise<opencode.server.Server>?
function M.configured()
  local url = require("opencode.config").opts.server and require("opencode.config").opts.server.url
  if url == nil then
    return nil
  end

  return type(url) == "string"
      and require("opencode.server").new(url):catch(function()
        error("Failed to connect to configured `opencode` server URL: " .. url, 0)
      end)
    or type(url) == "function"
      and require("opencode.promise")
        .new(function(resolve, reject)
          url(function(resolved_url) ---@param resolved_url string|nil
            if resolved_url then
              resolve(resolved_url)
            else
              reject("Configured `opencode` server URL resolved to `nil`")
            end
          end)
        end)
        :next(function(resolved_url)
          return require("opencode.server").new(resolved_url)
        end)
end

return M
