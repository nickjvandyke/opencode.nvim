---@class opencode.server.Opts
---
---The port to look for `opencode` on.
---When set, _only_ this port will be checked.
---When not set, _all_ `opencode` processes will be checked.
---Be sure to also launch `opencode` accordingly, e.g. `opencode --port 12345`.
---@field port? number|fun(callback: fun(port?: number))
---
---Start an `opencode` server.
---Called when when none are found; will retry after.
---@field start? fun()|false
---
---@field stop? fun()|false
---
---@field toggle? fun()|false

---An `opencode` server.
---@class opencode.server.Server
---@field port number
---@field cwd string
---@field title string
---@field subagents opencode.server.Agent[]
local Server = {}
Server.__index = Server

---Attempt to connect to an `opencode` server and fetch its details.
---Rejects if the connection or requests fail — the last line of defense against false-positive server discovery.
---@param port number
---@return Promise<opencode.server.Server>
function Server.new(port)
  local self = setmetatable({ port = port }, Server)
  local Promise = require("opencode.promise")
  local unavailable_message = "No `opencode` responding on port: " .. port

  return Promise.new(function(resolve, reject)
    -- Serially get path first to confirm that this is a valid `opencode` server before making other requests in parallel
    self:get_path(function(path)
      local cwd = path.directory or path.worktree
      if cwd then
        resolve(cwd)
      else
        reject(unavailable_message)
      end
    end, function()
      reject(unavailable_message)
    end)
  end)
    :next(function(cwd) ---@param cwd string
      return Promise.all({
        cwd,
        Promise.new(function(resolve)
          self:get_sessions(function(session)
            local title = session[1] and session[1].title or "<No sessions>"
            resolve(title)
          end)
        end),
        Promise.new(function(resolve)
          self:get_agents(function(agents)
            local subagents = vim.tbl_filter(function(agent)
              return agent.mode == "subagent"
            end, agents)
            resolve(subagents)
          end)
        end),
      })
    end)
    :next(function(results) ---@param results { [1]: string, [2]: string, [3]: opencode.server.Agent[] }
      self.port = port
      self.cwd = results[1]
      self.title = results[2]
      self.subagents = results[3]
      return self
    end)
end

---@param path string
---@param method "GET"|"POST"
---@param body table?
---@param on_success? fun(response: table)
---@param on_error? fun(code: number, msg: string?)
---@param opts? { max_time?: number }
---@return number job_id
function Server:curl(path, method, body, on_success, on_error, opts)
  local url = "http://localhost:" .. self.port .. path
  opts = opts or {
    max_time = 2,
  }

  local command = {
    "curl",
    "-s",
    "-S",
    "--fail",
    "-X",
    method,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "Accept: text/event-stream",
    "-N",
  }

  if opts.max_time then
    table.insert(command, "--max-time")
    table.insert(command, tostring(opts.max_time))
  end

  if body then
    table.insert(command, "-d")
    table.insert(command, vim.fn.json_encode(body))
  end

  table.insert(command, url)

  local response_buffer = {}
  local function process_response_buffer()
    if #response_buffer > 0 then
      local full_event = table.concat(response_buffer)
      response_buffer = {}
      vim.schedule(function()
        local ok, result = pcall(vim.fn.json_decode, full_event)
        if ok then
          if on_success then
            on_success(result)
          end
        else
          local error_message = "Failed to decode response from "
            .. url
            .. "\nResponse: "
            .. full_event
            .. "\nError: "
            .. result
          if on_error then
            on_error(-1, error_message)
          else
            vim.notify(error_message, vim.log.levels.ERROR, { title = "opencode" })
          end
        end
      end)
    end
  end

  local stderr_lines = {}
  return vim.fn.jobstart(command, {
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line == "" then
          process_response_buffer()
        else
          local clean_line = (line:gsub("^data: ?", ""))
          table.insert(response_buffer, clean_line)
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_lines, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        process_response_buffer()
      else
        local response_message = #response_buffer > 0 and table.concat(response_buffer, "\n") or nil
        local stderr_message = #stderr_lines > 0 and table.concat(stderr_lines, "\n") or nil
        local detail_lines = { "Request to " .. url .. " failed with exit code: " .. code }
        if stderr_message and stderr_message ~= "" then
          table.insert(detail_lines, "stderr:\n" .. stderr_message)
        end
        if response_message and response_message ~= "" then
          table.insert(detail_lines, "response:\n" .. response_message)
        end
        local error_message = table.concat(detail_lines, "\n")
        if on_error then
          on_error(code, error_message)
        else
          vim.notify(error_message, vim.log.levels.ERROR, { title = "opencode" })
        end
      end
    end,
  })
end

---@param text string
---@param callback fun(response: table)|nil
function Server:tui_append_prompt(text, callback)
  return self:curl("/tui/publish", "POST", { type = "tui.prompt.append", properties = { text = text } }, callback)
end

---@param command opencode.Command|string
---@param callback fun(response: table)|nil
function Server:tui_execute_command(command, callback)
  return self:curl(
    "/tui/publish",
    "POST",
    { type = "tui.command.execute", properties = { command = command } },
    callback
  )
end

---@alias opencode.server.permission.Reply
---| "once"
---| "always"
---| "reject"

---@param permission number
---@param reply opencode.server.permission.Reply
---@param callback? fun(session: table)
function Server:permit(permission, reply, callback)
  return self:curl("/permission/" .. permission .. "/reply", "POST", { reply = reply }, callback)
end

---@class opencode.server.Agent
---@field name string
---@field description string
---@field mode "primary"|"subagent"

---@param callback fun(agents: opencode.server.Agent[])
function Server:get_agents(callback, on_error)
  return self:curl("/agent", "GET", nil, callback, on_error)
end

---@class opencode.server.Command
---@field name string
---@field description string
---@field template string
---@field agent string

---Get custom commands from `opencode`.
---However, currently it does not seem to support executing these commands.
---
---@param callback fun(commands: opencode.server.Command[])
function Server:get_commands(callback, on_error)
  return self:curl("/command", "GET", nil, callback, on_error)
end

---@class opencode.server.SessionTime
---@field created integer time in milliseconds
---@field updated integer time in milliseconds

---@class opencode.server.Session
---@field id string
---@field title string
---@field time opencode.server.SessionTime

---Get sessions from `opencode`.
---
---@param callback fun(sessions: opencode.server.Session[])
function Server:get_sessions(callback, on_error)
  return self:curl("/session", "GET", nil, callback, on_error)
end

---Select session in `opencode`.
---
---@param session_id string
function Server:select_session(session_id)
  return self:curl("/tui/select-session", "POST", { sessionID = session_id }, nil)
end

---@class opencode.server.PathResponse
---@field directory string
---@field worktree string

---@param on_success fun(response: opencode.server.PathResponse)
---@param on_error fun()
function Server:get_path(on_success, on_error)
  return self:curl("/path", "GET", nil, on_success, on_error)
end

---@alias opencode.server.event.type
---| "server.connected"
---| "server.instance.disposed"
---| "session.idle"
---| "session.diff"
---| "session.heartbeat"
---| "message.updated"
---| "message.part.updated"
---| "permission.updated"
---| "permission.replied"
---| "session.error"

---@class opencode.server.Event
---@field type opencode.server.event.type|string
---@field properties table

---@param on_success fun(response: opencode.server.Event)|nil Invoked with each received event.
---@param on_error fun(code: number, msg: string?)|nil
---@return number job_id
function Server:sse_subscribe(on_success, on_error)
  return self:curl("/event", "GET", nil, on_success, on_error, { max_time = 0 })
end

---@return Promise<opencode.server.Server[]>
function Server.get_all()
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    local processes = require("opencode.server.process").get()
    if #processes == 0 then
      reject("No `opencode` processes found")
    else
      resolve(processes)
    end
  end):next(function(processes) ---@param processes opencode.server.process.Process[]
    return Promise.all_settled(vim.tbl_map(function(process) ---@param process opencode.server.process.Process
      return Server.new(process.port)
    end, processes)):next(
      function(results) ---@param results Promise<{status: string, value?: opencode.server.Server, reason?: any}[]>
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
    or type(port_opt) == "number" and Server.new(port_opt)
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
        return Server.new(port)
      end)
    or Server.get_all():next(function(servers) ---@param servers opencode.server.Server[]
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
function Server.get()
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

return Server
