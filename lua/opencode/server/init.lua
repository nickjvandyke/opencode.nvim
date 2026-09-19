---@class opencode.server.Opts
---Full URL of an OpenCode server, e.g. `"http://127.0.0.1:4096"`.
---Bypasses local discovery and connects directly.
---If pointing to a headless server, you _must_ attach a TUI via `opencode attach <URL>`.
---@field url? string | fun(callback: fun(url?: string))
---@field connect? boolean Whether to connect to an OpenCode server before interacting with it, listening for events and targeting it for future interactions.
---@field username? string Basic auth username.
---@field password? string Basic auth password.
---@field start? fun() | false Start an OpenCode server. Called when none are found; will retry after.

---@class opencode.server.Credentials
---@field username? string
---@field password? string

---An OpenCode server. OpenCode v2 runs a single background daemon that all clients (TUI, desktop, etc.) attach to.
---@class opencode.server.Server
---@field url string
---@field username string
---@field password? string
---@field version? string
---@field subscription_job_id? number
---@field heartbeat_timer? uv.uv_timer_t
local Server = {}
Server.__index = Server

---@class opencode.server.Session
---@field id string
---@field title string
---@field agent? string
---@field location? { directory: string }
---@field time { created: integer, updated: integer, idle?: integer, viewed?: integer, archived?: integer }

---@class opencode.server.PermissionRequest
---@field id string
---@field sessionID string
---@field action string
---@field resources string[]
---@field save? string[]
---@field metadata? table
---@field source? table
---@field message? string

---@alias opencode.server.PermissionReply
---| "once"
---| "always"
---| "reject"

---Events emitted by OpenCode.
---Note the v2 shape: `{ id, type, data }` (v1 used `{ type, properties }`).
---Not exhaustive.
---@alias opencode.server.Event
---| { id: string, type: "file.edited" | "filesystem.changed", data: { file: string } }
---| { id: string, type: "permission.asked", data: opencode.server.PermissionRequest }
---| { id: string, type: "permission.replied", data: { sessionID: string, requestID: string, reply: opencode.server.PermissionReply } }
---| { id: string, type: "server.connected", data: table }
---| { id: string, type: "global.disposed", data: table }
---| { id: string, type: "session.status", data: { sessionID: string, status: { type: "idle" | "busy" | "retry" } } }
---| { id: string, type: "session.execution.failed", data: table }
---| { id: string, type: string, data: table }

---Attempt to connect to an OpenCode server and fetch its details.
---Rejects if the info request fails — the last line of defense against false-positive server discovery.
---
---@param url string
---@param credentials? opencode.server.Credentials
---@return Promise<opencode.server.Server>
function Server.new(url, credentials)
  local self = setmetatable({}, Server)
  url = url:gsub("/$", "")
  self.url = url

  local config = require("opencode.config").opts.server or {}
  local creds = credentials or {}
  self.username = creds.username or config.username or "opencode"
  self.password = creds.password or config.password
  self.heartbeat_timer = vim.uv.new_timer()

  local Promise = require("opencode.promise")
  return self:request("/api/info", "GET"):next(function(info)
    self.version = info and info.version
    return Promise.resolve(self)
  end)
end

---@param path string
---@param method "GET" | "POST" | "PATCH" | "DELETE"
---@param body table?
---@param on_success fun(response: table?)
---@param on_error fun(msg: string, code: number, status: number?)
---@param opts? { persistent?: boolean, max_time?: number, on_heartbeat?: fun() }
---@return number job_id
function Server:curl(path, method, body, on_success, on_error, opts)
  local url = self.url .. path
  opts = opts or {}

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

  if self.password and self.password ~= "" then
    -- We can always send credentials; servers with no auth set just ignore them
    table.insert(cmd, "--user")
    table.insert(cmd, (self.username or "opencode") .. ":" .. self.password)
  end

  -- OpenCode v2 routes instance requests by directory. Without it, a shared
  -- service answers for its own ambient cwd instead of Neovim's project.
  -- Note OpenCode will resolve closest matches, like walking up parent directories.
  local directory = vim.fn.getcwd()
  if directory and directory ~= "" then
    table.insert(cmd, "-H")
    table.insert(cmd, "x-opencode-directory: " .. vim.uri_encode(directory))
  end

  if not opts.persistent then
    table.insert(cmd, "--max-time")
    table.insert(cmd, opts.max_time or 2)
  end

  if body ~= nil then
    -- `vim.fn.json_encode({})` encodes an empty table as `[]`, but the API expects `{}`.
    table.insert(cmd, "-d")
    table.insert(cmd, next(body) == nil and "{}" or vim.fn.json_encode(body))
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
        if line == "" then
          -- SSE frame terminator for streaming responses, else a line-split artifact to ignore.
          if opts.persistent then
            process_response_buffer()
          end
        elseif line:sub(1, 1) == ":" then
          -- SSE comment, e.g. OpenCode's `: heartbeat`. Proves liveness without a payload.
          if opts.on_heartbeat then
            vim.schedule(opts.on_heartbeat)
          end
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
        if #response_buffer > 0 then
          process_response_buffer()
        elseif on_success then
          -- Empty success body, e.g. a `204 No Content` response.
          vim.schedule(function()
            on_success(nil)
          end)
        end
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

---Issue a request and resolve with the decoded response body.
---
---@param path string
---@param method "GET" | "POST" | "PATCH" | "DELETE"
---@param body table?
---@param opts? { max_time?: number }
---@return Promise<table?>
function Server:request(path, method, body, opts)
  return require("opencode.promise").new(function(resolve, reject)
    self:curl(path, method, body, resolve, reject, opts)
  end)
end

---Root sessions for Neovim's directory, newest first.
---
---@return Promise<opencode.server.Session[]>
function Server:get_sessions()
  local Promise = require("opencode.promise")
  -- The `directory` query scopes sessions to Neovim's project. The
  -- `x-opencode-directory` header alone does not scope this endpoint in v2.0.x.
  -- `parentID=null` restricts to root sessions (not subagents).
  local path = "/api/session?directory=" .. vim.uri_encode(vim.fn.getcwd()) .. "&order=desc&parentID=null"
  return self:request(path, "GET"):next(function(response)
    return Promise.resolve(response and response.data or {})
  end)
end

---Resolve the session to target for this Neovim instance: the most recently
---updated root session for the current directory.
---
---Resolved on every call; never cached. See the README for the documented ordering.
---
---@return Promise<opencode.server.Session>
function Server:resolve_session()
  local Promise = require("opencode.promise")
  return self:get_sessions():next(function(sessions)
    for _, session in ipairs(sessions) do
      if not (session.time and session.time.archived) then
        return Promise.resolve(session)
      end
    end

    return Promise.reject("No OpenCode session found for `" .. vim.fn.getcwd() .. "`. Start one in the TUI.")
  end)
end

---@param session_id string
---@param text string
---@return Promise<any>
function Server:prompt(session_id, text)
  return self:request("/api/session/" .. session_id .. "/prompt", "POST", { text = text })
end

---Registered OpenCode command templates (built-in and user-defined).
---
---@return Promise<{ name: string, description?: string }[]>
function Server:get_commands()
  local Promise = require("opencode.promise")
  return self:request("/api/command", "GET"):next(function(response)
    return Promise.resolve(response and response.data or {})
  end)
end

---Run a registered OpenCode command in a session.
---
---@param session_id string
---@param name string
---@param text string Arguments for the command.
---@return Promise<any>
function Server:run_command(session_id, name, text)
  return self:request("/api/session/" .. session_id .. "/command", "POST", { name = name, text = text })
end

---@param session_id string
---@param request_id string
---@param decision opencode.server.PermissionReply
---@return Promise<any>
function Server:permit(session_id, request_id, decision)
  return self:request(
    "/api/session/" .. session_id .. "/permission/" .. request_id .. "/reply",
    "POST",
    { decision = decision }
  )
end

---How often OpenCode sends heartbeat events.
local OPENCODE_HEARTBEAT_INTERVAL_MS = 10000

---The currently connected server.
---Cleared when the server disposes itself, the connection errors, or the heartbeat disappears.
---@type opencode.server.Server?
Server.connected = nil

---Subscribe to this server's SSE stream and dispatch autocmds for received events.
---Disconnects currently connected server first.
---Idempotent.
---
---@return Promise<opencode.server.Server> server Promise that resolves or rejects according to initial connection success.
function Server:connect()
  local Promise = require("opencode.promise")

  if Server.connected == self then
    return Promise.resolve(self)
  elseif Server.connected then
    Server.connected:disconnect()
  end

  local function reset_heartbeat()
    if self.heartbeat_timer then
      self.heartbeat_timer:start(
        OPENCODE_HEARTBEAT_INTERVAL_MS + 1000,
        0,
        vim.schedule_wrap(function()
          self:disconnect()
        end)
      )
    end
  end

  return Promise.new(function(resolve, reject)
    self.subscription_job_id = self:curl(
      "/api/event",
      "GET",
      nil,
      function(response)
        reset_heartbeat()

        if response.type == "server.connected" then
          Server.connected = self
          resolve(self)
        elseif response.type == "global.disposed" or response.type == "server.instance.disposed" then
          self:disconnect()
        end

        require("opencode.events").emit(response, self)
      end,
      -- Server disappeared ungracefully, e.g. process killed, network error, etc.
      -- Also called on manual disconnects, like our `vim.fn.jobstop`.
      function(msg)
        local was_connected = Server.connected == self
        self:disconnect()
        if not was_connected then
          reject(msg)
        end
      end,
      { persistent = true, on_heartbeat = reset_heartbeat }
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
    require("opencode.events.status").reset()
  end
end

return Server
