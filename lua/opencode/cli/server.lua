local M = {}

---@class opencode.cli.server.Opts
---
---The port to look for `opencode` on.
---When set, _only_ this port will be checked.
---When not set, _all_ `opencode` processes will be checked.
---Be sure to also launch `opencode` accordingly, e.g. `opencode --port 12345`.
---@field port? number
---
---Start an `opencode` server.
---Called when when none are found; will retry after.
---@field start? fun()|false
---
---@field stop? fun()|false
---
---@field toggle? fun()|false

---An `opencode` server.
---@class opencode.cli.server.Server
---@field port number
---@field cwd string
---@field title string
---@field subagents opencode.cli.client.Agent[]

---Verify that an `opencode` process is responding on the given port,
---and fetch some details about it.
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
    -- Serial instead of parallel so that `get_path` has verified it's a server before we make more requests to it.
    :next(
      function(cwd) ---@param cwd string
        return Promise.all({
          cwd,
          Promise.new(function(resolve)
            require("opencode.cli.client").get_sessions(port, function(session)
              -- This will be the most recently interacted session.
              -- Unfortunately `opencode` doesn't provide a way to get the currently selected TUI session.
              -- But they will probably have interacted with the session they want to connect to most recently.
              local title = session[1] and session[1].title or "<No sessions>"
              resolve(title)
            end)
          end),
          Promise.new(function(resolve)
            require("opencode.cli.client").get_agents(port, function(agents)
              local subagents = vim.tbl_filter(function(agent)
                return agent.mode == "subagent"
              end, agents)
              resolve(subagents)
            end)
          end),
        })
      end
    )
    :next(function(results) ---@param results { [1]: string, [2]: string, [3]: opencode.cli.client.Agent[] }
      return {
        port = port,
        cwd = results[1],
        title = results[2],
        subagents = results[3],
      }
    end)
end

---@return Promise<opencode.cli.server.Server[]>
function M.get_all()
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    local processes = require("opencode.cli.process").get()
    if #processes == 0 then
      reject("No `opencode` processes found")
    else
      resolve(processes)
    end
  end):next(function(processes) ---@param processes opencode.cli.process.Process[]
    local get_servers = vim.tbl_map(function(process) ---@param process opencode.cli.process.Process
      return get_server(process.port)
    end, processes)
    return Promise.all_settled(get_servers):next(
      function(results) ---@param results Promise<{status: string, value?: opencode.cli.server.Server, reason?: any}[]>
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
      end
    )
  end)
end

---Find an `opencode` server's port. Tries, in order:
---
---1. The currently subscribed server in `opencode.events`.
---2. The configured port in `require("opencode.config").opts.port`.
---3. All servers, prioritizing one sharing CWD with Neovim, and prompting the user to select if multiple are found.
---4. Calling `opts.server.start()`, then retrying the above.
---
---Upon success, subscribes to the server's events.
---
---@param launch boolean? Whether to launch a new server if none found. Defaults to true.
---@return Promise<opencode.cli.server.Server>
function M.get(launch)
  launch = launch ~= false
  local server_opts = require("opencode.config").opts.server or {}
  local connected_server = require("opencode.events").connected_server
  local Promise = require("opencode.promise")

  return (
    connected_server and Promise.resolve(connected_server) -- Maaayy want to verify the connected server is still valid, but it should pretty reliably disconnect itself ASAP
    or server_opts.port and get_server(server_opts.port)
    or M.get_all():next(function(servers) ---@param servers opencode.cli.server.Server[]
      local nvim_cwd = vim.fn.getcwd()
      local servers_in_cwd = vim.tbl_filter(function(server)
        -- Overlaps in either direction, with no non-empty mismatch
        return server.cwd:find(nvim_cwd, 0, true) == 1 or nvim_cwd:find(server.cwd, 0, true) == 1
      end, servers)

      if #servers_in_cwd == 1 then
        -- User most likely wants to connect to the single server in their CWD
        return servers_in_cwd[1]
      else
        -- Can't guess which one the user wants based on CWD - select from *all*
        return require("opencode.ui.select_server").select_server(servers)
      end
    end)
  )
    :next(function(server) ---@param server opencode.cli.server.Server
      if not connected_server or connected_server.port ~= server.port then
        require("opencode.events").connect(server)
      end
      return server
    end)
    :catch(function(err)
      if not err then
        -- Do nothing when select is cancelled
        return Promise.reject()
      end

      return Promise.new(function(resolve, reject)
        if not launch or not server_opts.start then
          -- Don't attempt to recover - just propagate the original error
          reject(err)
          return
        end

        local start_ok, start_result = pcall(server_opts.start)
        if not start_ok then
          return reject("Error starting `opencode`: " .. start_result)
        end

        -- Wait for the server to start
        vim.defer_fn(function()
          resolve(true)
        end, 2000)
      end):next(function()
        -- Retry
        return M.get(false)
      end)
    end)
end

return M
