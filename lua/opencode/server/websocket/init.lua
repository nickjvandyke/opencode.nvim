local M = {}
local Client = require("opencode.server.websocket.client")
local handshake = require("opencode.server.websocket.handshake")
local tcp_server = require("opencode.server.websocket.tcp")

M.state = {
  server = nil,
  clients = {},
  port = nil,
  auth_token = nil,
}

local function remove_client(client)
  for i, connected_client in ipairs(M.state.clients) do
    if connected_client == client then
      table.remove(M.state.clients, i)
      break
    end
  end
end

local function broadcast(method, params)
  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  local sent = false
  for _, client in ipairs(M.state.clients) do
    if client:is_connected() then
      client:send_json(message)
      sent = true
    end
  end
  return sent
end

function M.start(port, auth_token)
  if M.state.server then
    return false, "Server already running on port " .. M.state.port
  end

  port = port or 0
  auth_token = auth_token or nil

  local server, err = tcp_server.create_server("127.0.0.1", port, function(tcp_client)
    local client = Client.new(tcp_client)

    local function handle_message(type, data)
      if type == "handshake" then
        local ok, headers = handshake.validate_upgrade_request(data, auth_token)
        if not ok then
          local response = "HTTP/1.1 400 Bad Request\r\n\r\n" .. (headers or "Invalid handshake")
          client:send(response)
          client:close()
          remove_client(client)
          return
        end

        local ws_key = headers["sec-websocket-key"]
        local response = handshake.create_response(ws_key, auth_token)
        client:send(response)
        client:set_state("connected")
        client.authenticated = auth_token and true or false

        table.insert(M.state.clients, client)
      elseif type == "message" then
        local ok, message = pcall(vim.json.decode, data)
        if ok and message then
          if message.method == "initialize" then
            local response = {
              jsonrpc = "2.0",
              id = message.id,
              result = {
                protocolVersion = "2025-11-25",
                serverInfo = {
                  name = "opencode.nvim",
                  version = "1.0.0",
                },
              },
            }
            client:send_json(response)
          elseif message.method == "notifications/initialized" then
            vim.schedule(function()
              require("opencode.editor.selection").update(true)
            end)
          end
        end
      end
    end

    local function handle_close()
      remove_client(client)
    end

    tcp_client:read_start(function(read_err, data)
      if read_err or not data then
        client:close()
        remove_client(client)
        return
      end

      client:handle_data(data, handle_message, handle_close)
    end)
  end)

  if not server then
    return false, err or "Failed to create server"
  end

  local sockname = server:getsockname()
  if not sockname then
    server:close()
    return false, "Failed to determine server port"
  end
  local actual_port = sockname.port

  M.state.server = server
  M.state.port = actual_port
  M.state.auth_token = auth_token

  return true, actual_port
end

function M.stop()
  for _, client in ipairs(M.state.clients) do
    client:close()
  end
  M.state.clients = {}

  if M.state.server then
    M.state.server:close()
    M.state.server = nil
  end

  M.state.port = nil
  M.state.auth_token = nil
end

function M.is_running()
  return M.state.server ~= nil
end

function M.get_port()
  return M.state.port
end

function M.get_auth_token()
  return M.state.auth_token
end

function M.broadcast_selection_changed(file_path, selection)
  return broadcast("selection_changed", {
    text = selection.text or "",
    filePath = file_path,
    fileUrl = vim.uri_from_fname(file_path),
    selection = {
      start = {
        line = selection.start_line,
        character = selection.start_col,
      },
      ["end"] = {
        line = selection.end_line,
        character = selection.end_col,
      },
      isEmpty = selection.is_empty or false,
    },
  })
end

function M.broadcast_at_mentioned(file_path, line_start, line_end)
  return broadcast("at_mentioned", {
    filePath = file_path,
    lineStart = line_start,
    lineEnd = line_end,
  })
end

return M
