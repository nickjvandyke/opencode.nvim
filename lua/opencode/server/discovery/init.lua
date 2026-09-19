local M = {}

---@class opencode.server.discovery.Registration
---@field url string
---@field password? string
---@field pid? number
---@field version? string

---Read the registered OpenCode background service (URL + password).
---
---OpenCode v2 writes `service.json` to its state directory when the service
---starts. The plugin connects to that URL with the generated password.
---
---@return opencode.server.discovery.Registration?
local function registered()
  local state_home = vim.env.XDG_STATE_HOME
  -- Mirror OpenCode's own resolution: XDG roots based on `os.homedir()`, which on
  -- Windows is `%USERPROFILE%` (where `$HOME` is not reliably set).
  local home = vim.uv.os_homedir() or vim.env.HOME or ""
  local state_dir = (state_home and state_home ~= "") and vim.fs.joinpath(state_home, "opencode")
    or vim.fs.joinpath(home, ".local", "state", "opencode")
  local path = vim.fs.joinpath(state_dir, "service.json")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then
    return nil
  end

  local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if decoded_ok and type(decoded) == "table" and type(decoded.url) == "string" then
    return {
      url = decoded.url,
      password = decoded.password,
      pid = decoded.pid,
      version = decoded.version,
    }
  end

  return nil
end

local function find()
  local Promise = require("opencode.promise")
  local connected_server = require("opencode.server").connected
  if connected_server then
    return Promise.resolve(connected_server)
  end

  local configured = M.configured()
  if configured then
    return configured
  end

  local info = registered()
  if info then
    return require("opencode.server").new(info.url, { password = info.password }):catch(function(err)
      return Promise.reject(err or ("Failed to connect to registered OpenCode server at " .. info.url))
    end)
  end

  return Promise.reject("No OpenCode server found")
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
---3. The background service registered in OpenCode's state directory (`service.json`).
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

      local server_opts = require("opencode.config").opts.server

      -- A configured URL is authoritative; don't start a local server for it.
      if server_opts and server_opts.url ~= nil then
        return Promise.reject(err)
      end

      local start = server_opts and server_opts.start

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
    :next(function(server)
      if require("opencode.config").opts.server.connect then
        return server:connect()
      else
        return Promise.resolve(server)
      end
    end)
end

---The registered OpenCode background service (URL + password), if any.
---Useful for callers that need the raw registration before a full server connection.
---
---@return opencode.server.discovery.Registration?
function M.registration()
  return registered()
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
          url(function(resolved_url) ---@param resolved_url string?
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
