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
        return Promise.reject("No OpenCode servers found with overlapping CWD")
      elseif #servers_sharing_cwd == 1 then
        return servers_sharing_cwd[1]
      else
        return require("opencode.ui.select_server").select_server(servers_sharing_cwd)
      end
    end)
end

---Look for an OpenCode server every second, rejecting if not found after five seconds.
---
---@return Promise<opencode.server.Server>
local function poll()
  local Promise = require("opencode.promise")
  local poll_timer, timer_err, timer_errname = vim.uv.new_timer()
  if not poll_timer then
    return Promise.reject("Failed to create timer to poll for OpenCode: " .. timer_errname .. ": " .. timer_err)
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

---Find and connect to an OpenCode server. Tries, in order:
---
---1. The currently connected server.
---2. The configured URL in `require("opencode.config").opts.server.url`.
---3. All local servers that overlap with Neovim's CWD. Automatically selects if just one, otherwise prompts to select from them.
---4. Calling `vim.g.opencode_opts.server.start` and retrying the above over five seconds.
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
        return Promise.reject("Failed to start OpenCode: " .. start_result)
      end

      return poll()
    end)
    :next(function(server) ---@param server opencode.server.Server
      return server:connect()
    end)
end

---Search for `opencode` processes on this machine and attempt to resolve them to servers.
---
---@return Promise<opencode.server.Server[]>
function M.locally()
  local Promise = require("opencode.promise")
  return require("opencode.server.discovery.process")
    .get()
    :next(function(processes)
      if #processes == 0 then
        return Promise.reject("No `opencode ... --port` processes found")
      end
      return processes
    end)
    :next(function(processes) ---@param processes opencode.server.discovery.process.Process[]
      -- `all_settled` because we expect non-servers (falsely discovered processes) to reject
      return Promise.all_settled(
        vim.tbl_map(function(process) ---@param process opencode.server.discovery.process.Process
          return require("opencode.server").new("http://localhost:" .. process.port)
        end, processes)
      )
    end)
    :next(function(results) ---@param results { status: string, value?: opencode.server.Server, reason?: any }[]
      local servers = {}
      for _, result in ipairs(results) do
        if result.status == "fulfilled" then
          table.insert(servers, result.value)
        end
      end

      if #servers == 0 then
        for _, result in ipairs(results) do
          if result.status == "rejected" and result.reason then
            -- Prefer to surface a specific rejection - it's likely from a valid server (e.g. unauthenticated)
            return Promise.reject(result.reason)
          end
        end

        return Promise.reject("No OpenCode servers found")
      end

      return servers
    end)
end

---Attempt to connect to the OpenCode server at `vim.g.opencode_opts.server.url`.
---
---@return Promise<opencode.server.Server>?
function M.configured()
  local url = require("opencode.config").opts.server and require("opencode.config").opts.server.url
  if url == nil then
    return nil
  end

  return type(url) == "string"
      and require("opencode.server").new(url):catch(function()
        return require("opencode.promise").reject("Failed to connect to configured OpenCode server URL: " .. url)
      end)
    or type(url) == "function"
      and require("opencode.promise")
        .new(function(resolve, reject)
          url(function(resolved_url) ---@param resolved_url string|nil
            if resolved_url then
              resolve(resolved_url)
            else
              reject("Configured OpenCode server URL resolved to `nil`")
            end
          end)
        end)
        :next(function(resolved_url)
          return require("opencode.server").new(resolved_url)
        end)
end

return M
