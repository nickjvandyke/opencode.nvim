---@class opencode.server.Opts
---
---Full URL of an `opencode` server, e.g. `"http://localhost:4096"`.
---If set, bypasses local process discovery and connects directly.
---You _must_ run `opencode` with the `--port` flag to expose its server.
---If pointing to a headless server, you _must_ attach a TUI via `opencode attach <URL>`.
---@field url? string|fun(callback: fun(url?: string))
---
---Basic auth username.
---@field username? string
---
---Basic auth password.
---@field password? string
---
---Start an `opencode` server.
---Called when when none are found; will retry after.
---May return a `Promise` that resolves when the server is ready;
---if so, server discovery polling waits for it.
---@field start? (fun(): Promise?)|false
---
---@field stop? (fun(): Promise?)|false
---
---@field toggle? (fun(): Promise?)|false

---An `opencode` server.
---@class opencode.server.Server
---@field url string
---@field cwd string
---@field title string
---@field subagents opencode.server.Agent[]
---@field subscription_job_id? number
---@field heartbeat_timer? uv.uv_timer_t
local Server = {}
Server.__index = Server

---Attempt to connect to an `opencode` server and fetch its health and details.
---Rejects if the health fails — the last line of defense against false-positive server discovery.
---Rejection message is non-empty if from a valid `opencode` server.
---@param url string
---@return Promise<opencode.server.Server>
function Server.new(url)
  local self = setmetatable({}, Server)
  self.url = url:gsub("/$", "")
  self.heartbeat_timer = vim.uv.new_timer()

  local Promise = require("opencode.promise")

  -- Serially check health first to confirm that this is a valid and authenticated `opencode` server.
  -- Would like to differentiate headless servers, but not possible afaict unfortunately.
  -- No endpoint exposes such information, and TUI commands sent to a headless server with none attached just no-op, with no tell in the respone.
  -- So user must manually `opencode attach` in that case.
  return self
    :get_health()
    :next(function()
      return Promise.all({
        self:get_path():next(function(path)
          return path.directory or path.worktree
        end),
        self:get_sessions():next(function(sessions)
          return sessions[1] and sessions[1].title or "<No sessions>"
        end),
        self:get_agents():next(function(agents)
          return vim.tbl_filter(function(agent)
            return agent.mode == "subagent"
          end, agents)
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

---Human-readable name, stripping the protocol prefix.
---@return string
function Server:display_name()
  local name = self.url:gsub("^%w+://", "")
  return name
end

---@param path string
---@param method "GET"|"POST"
---@param body table?
---@param on_success fun(response: table)
---@param on_error fun(msg: string?, code: number, status: number?)
---@param opts? { persistent?: boolean }
---@return number job_id
function Server:curl(path, method, body, on_success, on_error, opts)
  local url = self.url .. path
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
          on_error(error_message, -1)
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
        on_error(error_message, code, status)
      end
    end,
  })
end

---@return Promise
function Server:get_health()
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/global/health", "GET", nil, resolve, function(msg, _, status)
      if status == 401 then
        reject("Unauthorized response from `opencode` at " .. self:display_name())
      else
        reject(msg)
      end
    end)
  end)
end

---@param text string
---@return Promise
function Server:tui_append_prompt(text)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/tui/publish", "POST", { type = "tui.prompt.append", properties = { text = text } }, resolve, reject)
  end)
end

---@param command opencode.Command|string
---@return Promise
function Server:tui_execute_command(command)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl(
      "/tui/publish",
      "POST",
      { type = "tui.command.execute", properties = { command = command } },
      resolve,
      reject
    )
  end)
end

---@alias opencode.server.permission.Reply
---| "once"
---| "always"
---| "reject"

---@param permission number
---@param reply opencode.server.permission.Reply
---@return Promise
function Server:permit(permission, reply)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/permission/" .. permission .. "/reply", "POST", { reply = reply }, resolve, reject)
  end)
end

---@class opencode.server.Agent
---@field name string
---@field description string
---@field mode "primary"|"subagent"

---@return Promise<opencode.server.Agent[]>
function Server:get_agents()
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/agent", "GET", nil, resolve, reject)
  end)
end

---@class opencode.server.Command
---@field name string
---@field description string
---@field template string
---@field agent string

---@class opencode.server.SessionTime
---@field created integer time in milliseconds
---@field updated integer time in milliseconds

---@class opencode.server.Session
---@field id string
---@field title string
---@field time opencode.server.SessionTime

---Get sessions from `opencode`.
---
---@return Promise<opencode.server.Session[]>
function Server:get_sessions()
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/session", "GET", nil, resolve, reject)
  end)
end

---Select session in `opencode`.
---
---@param session_id string
---@return Promise
function Server:select_session(session_id)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/tui/select-session", "POST", { sessionID = session_id }, resolve, reject)
  end)
end

---@class opencode.server.PathResponse
---@field directory string
---@field worktree string

---@return Promise<opencode.server.PathResponse>
function Server:get_path()
  return require("opencode.promise").new(function(resolve, reject)
    self:curl("/path", "GET", nil, resolve, reject)
  end)
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

---@param on_success fun(response: opencode.server.Event) Invoked with each received event.
---@param on_error fun(msg: string?, code: number)
---@return number job_id
function Server:sse_subscribe(on_success, on_error)
  return self:curl("/event", "GET", nil, on_success, on_error, { persistent = true })
end

---How often `opencode` sends heartbeat events.
local OPENCODE_HEARTBEAT_INTERVAL_MS = 10000

---The currently connected server.
---Cleared when the server disposes itself, the connection errors, or the heartbeat disappears.
---@type opencode.server.Server?
Server.connected = nil

---Subscribe to this server's SSE stream and dispatch autocmds for received events.
---Disconnects currently connected server first.
---Idempotent.
---@return Promise<opencode.server.Server> server Promise that resolves or rejects according to initial connection success.
function Server:connect()
  local Promise = require("opencode.promise")

  if Server.connected == self then
    return Promise.resolve(self)
  elseif Server.connected then
    Server.connected:disconnect()
  end

  return Promise.new(function(resolve, reject)
    self.subscription_job_id = self:sse_subscribe(
      function(response)
        if self.heartbeat_timer then
          self.heartbeat_timer:start(OPENCODE_HEARTBEAT_INTERVAL_MS + 1000, 0, vim.schedule_wrap(self.disconnect))
        end

        if response.type == "server.connected" then
          Server.connected = self
          resolve(self)
        elseif response.type == "server.instance.disposed" then
          self:disconnect()
        end

        if require("opencode.config").opts.events.enabled then
          vim.api.nvim_exec_autocmds("User", {
            pattern = "OpencodeEvent:" .. response.type,
            data = {
              event = response,
              -- Can't pass metatable through here, so listeners need to reconstruct the server object if they want to use its methods
              url = self.url,
            },
          })
        end
      end,
      -- Server disappeared ungracefully, e.g. process killed, network error, etc.
      -- Also called on manual disconnects, like our `vim.fn.jobstop`.
      function(msg)
        local was_connected = Server.connected == self
        self:disconnect()
        if not was_connected then
          reject(msg)
        end
      end
    )
  end)
end

---Unsubscribe from this server's SSE stream and stop the heartbeat timer.
---Idempotent.
function Server:disconnect()
  if self.subscription_job_id then
    vim.fn.jobstop(self.subscription_job_id)
    self.subscription_job_id = nil
  end
  if self.heartbeat_timer then
    self.heartbeat_timer:stop()
  end

  if Server.connected == self then
    Server.connected = nil
  end
end

return Server
