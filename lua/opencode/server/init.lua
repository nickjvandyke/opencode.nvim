---@class opencode.server.Opts
---
---The port to look for `opencode` on.
---When set, _only_ this port will be checked.
---When not set, _all_ `opencode` processes will be checked.
---Be sure to also launch `opencode` accordingly, e.g. `opencode --port 12345`.
---@field port? number|fun(callback: fun(port?: number))
---
---Basic auth username.
---@field username? string
---
---Basic auth password.
---@field password? string
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

---Attempt to connect to an `opencode` server and fetch its health and details.
---Rejects if the health fails — the last line of defense against false-positive server discovery.
---Rejection message is non-empty if from a valid `opencode` server.
---@param port number
---@return Promise<opencode.server.Server>
function Server.new(port)
  local self = setmetatable({ port = port }, Server)
  local Promise = require("opencode.promise")

  return Promise.new(function(resolve, reject)
    -- Serially check health first to confirm that this is a valid and authenticated `opencode` server
    self:get_health(function()
      resolve(true)
    end, function(_, _, status) ---@param status number
      if status == 401 then
        reject("Unauthorized response from `opencode` on port " .. self.port)
      else
        reject()
      end
    end)
  end)
    :next(function()
      return Promise.all({
        Promise.new(function(resolve)
          self:get_path(function(path)
            local cwd = path.directory or path.worktree
            resolve(cwd)
          end)
        end),
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
---@param on_error? fun(code: number, msg: string?, status: number?)
---@param opts? { persistent?: boolean }
---@return number job_id
function Server:curl(path, method, body, on_success, on_error, opts)
  local url = "http://localhost:" .. self.port .. path
  opts = opts or {
    persistent = false,
  }

  local cmd = {
    "curl",
    "-s", -- Silent
    "-S", -- Except for errors/stderr
    "--fail-with-body",
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

  -- Route the request to the TUI whose working directory matches Neovim's.
  -- In single-TUI / integrated-mode setups this matches the only TUI trivially.
  -- In multi-TUI setups (`opencode serve` + several `opencode attach --dir ...`)
  -- this ensures `tui.*` events are delivered to the intended TUI.
  local nvim_cwd = vim.fn.getcwd()
  if nvim_cwd and nvim_cwd ~= "" then
    table.insert(command, "-H")
    table.insert(command, "x-opencode-directory: " .. nvim_cwd)
  end

  if opts.max_time then
    table.insert(command, "--max-time")
    table.insert(command, tostring(opts.max_time))
  end

  local username = require("opencode.config").opts.server.username
  local password = require("opencode.config").opts.server.password
  if username and password then
    -- We can always send credentials; servers with no auth set just ignore them
    -- TODO: Track auth per-server?
    -- Seems like an uncommon need.
    -- Would require more robust discovery configuration.
    table.insert(cmd, "--user")
    table.insert(cmd, username .. ":" .. password)
  end

  if not opts.persistent then
    table.insert(cmd, "--max-time")
    table.insert(cmd, 2)
  end

  if body then
    table.insert(cmd, "-d")
    table.insert(cmd, vim.fn.json_encode(body))
  end

  table.insert(cmd, url)

  local function on_error_wrapper(code, msg, status)
    if on_error then
      on_error(code, msg, status)
    else
      -- TODO: Eventually all errors should go through `on_error` for higher-level handling
      vim.notify(msg, vim.log.levels.ERROR, { title = "opencode" })
    end
  end

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
          on_error_wrapper(-1, error_message)
        end
      end)
    end
  end

  local stderr_lines = {}
  return vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line == "" and opts.persistent then
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
        local stderr_message = #stderr_lines > 0 and table.concat(stderr_lines, "") or nil
        local status

        local detail_lines = { "Request to " .. url .. " failed with exit code: " .. code }
        if response_message and response_message ~= "" then
          table.insert(detail_lines, "Response:\n" .. response_message)
        end
        if stderr_message and stderr_message ~= "" then
          table.insert(detail_lines, "Stderr:\n" .. stderr_message)
          -- Afaict `curl` requires manual parsing of the response code one way or another regardless of flags :/
          status = stderr_message:match("The requested URL returned error: (%d+)$")
          status = tonumber(status)
        end

        local error_message = table.concat(detail_lines, "\n")
        on_error_wrapper(code, error_message, status)
      end
    end,
  })
end

---@param on_success fun(response: opencode.server.PathResponse)
---@param on_error fun(code: number, msg: string?, status: number?)
function Server:get_health(on_success, on_error)
  return self:curl("/global/health", "GET", nil, on_success, on_error)
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
function Server:get_agents(callback)
  return self:curl("/agent", "GET", nil, callback)
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
function Server:get_commands(callback)
  return self:curl("/command", "GET", nil, callback)
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
function Server:get_sessions(callback)
  return self:curl("/session", "GET", nil, callback)
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
  return self:curl("/event", "GET", nil, on_success, on_error, { persistent = true })
end

return Server
