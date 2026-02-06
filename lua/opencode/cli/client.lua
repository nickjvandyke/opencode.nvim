---Call the `opencode` server.
--- - [docs](https://opencode.ai/docs/server/#apis)
--- - [implementation](https://github.com/sst/opencode/blob/dev/packages/opencode/src/server/server.ts)
local M = {}

---Generate a UUID v4 (cross-platform, no external dependencies)
---@return string UUID in format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
local function generate_uuid()
  local bytes = vim.uv.random(16) -- (uv.random is cryptographically secure :help uv.random())

  -- Convert to hex and format as UUID v4
  local hex = {}
  for i = 1, 16 do
    if bytes ~= nil then
      local byte_val = string.byte(bytes, i) or 0
      hex[i] = string.format("%02x", byte_val)
    end
  end

  hex[7] = "4" .. hex[7]:sub(2)
  hex[9] = string.format("%x", (tonumber(hex[9]:sub(1, 1), 16) % 4) + 8) .. hex[9]:sub(2)

  return string.format(
    "%s%s%s%s-%s%s-%s%s-%s%s-%s%s%s%s%s%s",
    hex[1],
    hex[2],
    hex[3],
    hex[4],
    hex[5],
    hex[6],
    hex[7],
    hex[8],
    hex[9],
    hex[10],
    hex[11],
    hex[12],
    hex[13],
    hex[14],
    hex[15],
    hex[16]
  )
end

---@param url string
---@param method string
---@param body table?
---@param on_success fun(response: table)?
---@param on_error fun(code: number, msg: string?)?
---@return number job_id
local function curl(url, method, body, on_success, on_error)
  local command = {
    "curl",
    "-s",
    "--connect-timeout",
    "1",
    "-X",
    method,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Accept: application/json",
    "-H",
    "Accept: text/event-stream",
    "-N", -- No buffering, for streaming SSEs
  }

  if body then
    table.insert(command, "-d")
    table.insert(command, vim.fn.json_encode(body))
  end

  table.insert(command, url)

  -- Buffer the response outside of the job callbacks - they may be called multiple times
  local response_buffer = {}
  local function process_response_buffer()
    if #response_buffer > 0 then
      local full_event = table.concat(response_buffer)
      response_buffer = {}
      vim.schedule(function()
        local ok, response = pcall(vim.fn.json_decode, full_event)
        if ok then
          if on_success then
            on_success(response)
          end
        else
          vim.notify(
            "Response decode error: " .. full_event .. "; " .. response,
            vim.log.levels.ERROR,
            { title = "opencode" }
          )
        end
      end)
    end
  end

  local stderr_lines = {}
  -- Would prefer `vim.system`, but it seems unable to handle rapid SSEs currently and occasionally drops them.
  return vim.fn.jobstart(command, {
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line == "" then
          -- Blank line indicates end of SSE event
          process_response_buffer()
        else
          -- Strip "data: " SSE prefix
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
        -- Process any remaining buffered data.
        process_response_buffer()
      elseif code ~= 18 and code ~= 143 then
        local stderr_message = #stderr_lines > 0 and table.concat(stderr_lines, "\n") or nil
        if on_error then
          on_error(code, stderr_message)
        else
          -- 18 = connection closed, 143 = SIGTERM (manual disconnect)
          local error_message = "curl command failed with exit code: "
            .. code
            .. "\nstderr:\n"
            .. (stderr_message or "<none>")
          vim.notify(error_message, vim.log.levels.ERROR, { title = "opencode" })
        end
      end
    end,
  })
end

---Call an opencode server endpoint.
---@param port number
---@param path string
---@param method "GET"|"POST"
---@param body table?
---@param on_success fun(response: table)?
---@param on_error fun(code: number, msg: string?)?
---@return number job_id
function M.call(port, path, method, body, on_success, on_error)
  return curl("http://localhost:" .. port .. path, method, body, on_success, on_error)
end

---@param text string
---@param port number
---@param callback fun(response: table)|nil
function M.tui_append_prompt(text, port, callback)
  M.call(port, "/tui/publish", "POST", { type = "tui.prompt.append", properties = { text = text } }, callback)
end

---@param command opencode.Command|string
---@param port number
---@param callback fun(response: table)|nil
function M.tui_execute_command(command, port, callback)
  M.call(port, "/tui/publish", "POST", { type = "tui.command.execute", properties = { command = command } }, callback)
end

---@param prompt string
---@param session_id string
---@param port number
---@param provider_id string
---@param model_id string
---@param callback fun(response: table)|nil
function M.send_message(prompt, session_id, port, provider_id, model_id, callback)
  local body = {
    sessionID = session_id,
    providerID = provider_id,
    modelID = model_id,
    parts = {
      {
        type = "text",
        id = generate_uuid(),
        text = prompt,
      },
    },
  }

  M.call(port, "/session/" .. session_id .. "/message", "POST", body, callback)
end

---@param port number
---@param permission number
---@param reply "once"|"always"|"reject"
---@param callback? fun(session: table)
function M.permit(port, permission, reply, callback)
  M.call(port, "/permission/" .. permission .. "/reply", "POST", {
    reply = reply,
  }, callback)
end

---@class opencode.cli.client.Agent
---@field name string
---@field description string
---@field mode "primary"|"subagent"

---@param port number
---@param callback fun(agents: opencode.cli.client.Agent[])
function M.get_agents(port, callback)
  M.call(port, "/agent", "GET", nil, callback)
end

---@class opencode.cli.client.Command
---@field name string
---@field description string
---@field template string
---@field agent string

---Get custom commands from `opencode`.
---
---@param port number
---@param callback fun(commands: opencode.cli.client.Command[])
function M.get_commands(port, callback)
  M.call(port, "/command", "GET", nil, callback)
end

---@class opencode.cli.client.SessionTime
---@field created integer time in milliseconds
---@field updated integer time in milliseconds

---@class opencode.cli.client.Session
---@field id string
---@field title string
---@field time opencode.cli.client.SessionTime

---Get sessions from `opencode`.
---
---@param port number
---@param callback fun(sessions: opencode.cli.client.Session[])
function M.get_sessions(port, callback)
  M.call(port, "/session", "GET", nil, callback)
end

---@class opencode.cli.client.SessionStatus

---Get sessions' status from `opencode`.
---
---@param port number
---@param callback fun(statuses: opencode.cli.client.SessionStatus[])
function M.get_sessions_status(port, callback)
  M.call(port, "/session/status", "GET", nil, callback)
end

---Select session in `opencode`.
---
---@param port number
---@param session_id string
function M.select_session(port, session_id)
  M.call(port, "/tui/select-session", "POST", { sessionID = session_id }, nil)
end

---@class opencode.cli.client.PathResponse
---@field directory string
---@field worktree string

---@param port number
---@param on_success fun(response: opencode.cli.client.PathResponse)
---@param on_error fun()
function M.get_path(port, on_success, on_error)
  M.call(port, "/path", "GET", nil, on_success, on_error)
end

---@class opencode.cli.client.Event
---@field type string
---@field properties table

---Calls the `/event` SSE endpoint and invokes `callback` for each event received.
---Stops any previous subscription, so only one is active at a time.
---
---@param port number
---@param callback fun(response: opencode.cli.client.Event)|nil
---@return number job_id
function M.sse_subscribe(port, callback)
  return M.call(port, "/event", "GET", nil, callback)
end

return M
