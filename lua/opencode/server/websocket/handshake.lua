local utils = require("opencode.server.websocket.utils")

local M = {}

function M.validate_upgrade_request(request, expected_auth_token)
  local headers = utils.parse_http_headers(request)

  if not headers["upgrade"] or headers["upgrade"]:lower() ~= "websocket" then
    return false, "Missing or invalid Upgrade header"
  end

  if not headers["connection"] or not headers["connection"]:lower():find("upgrade") then
    return false, "Missing or invalid Connection header"
  end

  if not headers["sec-websocket-version"] or headers["sec-websocket-version"] ~= "13" then
    return false, "Missing or invalid Sec-WebSocket-Version header"
  end

  if not headers["sec-websocket-key"] then
    return false, "Missing Sec-WebSocket-Key header"
  end

  if expected_auth_token then
    local auth_header = headers["x-claude-code-ide-authorization"] or headers["x-opencode-ide-authorization"]
    if not auth_header then
      return false, "Missing authentication header"
    end

    if not utils.constant_time_compare(auth_header, expected_auth_token) then
      return false, "Invalid authentication token"
    end
  end

  return true, headers
end

function M.create_accept_key(websocket_key)
  local combined = websocket_key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  return utils.base64_encode(utils.sha1(combined))
end

function M.create_response(websocket_key, auth_token)
  local response = {
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. M.create_accept_key(websocket_key),
  }

  if auth_token then
    table.insert(response, "X-OpenCode-IDE-Authorization: " .. auth_token)
  end

  table.insert(response, "")
  table.insert(response, "")

  return table.concat(response, "\r\n")
end

return M
