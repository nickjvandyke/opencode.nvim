local M = {}

---@class opencode.server.discovery.Registration
---@field url string
---@field password? string
---@field pid? number
---@field version? string

---Read the registered OpenCode background services (URL + password), newest first.
---
---OpenCode v2 writes `service.json` to its state directory when the service
---starts, or `service-<channel>.json` for channels other than `latest`, `dev`,
---`beta` and `next` (e.g. Nix builds use `prod`). A registration may be stale
---if its server has since exited, so callers should try each in order.
---
---@return opencode.server.discovery.Registration[]
function M.registrations()
  local state_home = vim.env.XDG_STATE_HOME
  -- Mirror OpenCode's own resolution: XDG roots based on `os.homedir()`, which on
  -- Windows is `%USERPROFILE%` (where `$HOME` is not reliably set).
  local home = vim.uv.os_homedir() or vim.env.HOME or ""
  local state_dir = (state_home and state_home ~= "") and vim.fs.joinpath(state_home, "opencode")
    or vim.fs.joinpath(home, ".local", "state", "opencode")

  local candidates = {}
  for name in vim.fs.dir(state_dir) do
    if name == "service.json" or name:match("^service%-.+%.json$") then
      local path = vim.fs.joinpath(state_dir, name)
      -- fs_stat follows symlinks, so a linked registration file still counts
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "file" then
        table.insert(candidates, { name = name, path = path, mtime = stat.mtime })
      end
    end
  end
  table.sort(candidates, function(a, b)
    if a.mtime.sec ~= b.mtime.sec then
      return a.mtime.sec > b.mtime.sec
    end
    if (a.mtime.nsec or 0) ~= (b.mtime.nsec or 0) then
      return (a.mtime.nsec or 0) > (b.mtime.nsec or 0)
    end
    -- same mtime: prefer the default service.json, then sort by name
    if (a.name == "service.json") ~= (b.name == "service.json") then
      return a.name == "service.json"
    end
    return a.name < b.name
  end)

  local registrations = {}
  for _, candidate in ipairs(candidates) do
    local ok, lines = pcall(vim.fn.readfile, candidate.path)
    if ok and lines and #lines > 0 then
      local decoded_ok, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
      if decoded_ok and type(decoded) == "table" and type(decoded.url) == "string" then
        table.insert(registrations, {
          url = decoded.url,
          password = decoded.password,
          pid = decoded.pid,
          version = decoded.version,
        })
      end
    end
  end

  return registrations
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

  -- Try each registration in turn; a newer one may be left behind by an exited server
  local registrations = M.registrations()
  local function try(i)
    local registration = registrations[i]
    return require("opencode.server").new(registration.url, { password = registration.password }):catch(function(err)
      if registrations[i + 1] then
        return try(i + 1)
      end
      return Promise.reject(err or ("Failed to connect to registered OpenCode server at " .. registration.url))
    end)
  end
  if #registrations > 0 then
    return try(1)
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
---3. The background services registered in OpenCode's state directory (`service.json` or `service-<channel>.json`), newest first.
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
