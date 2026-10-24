local frame = require("opencode.server.websocket.frame")

local Client = {}
Client.__index = Client

function Client.new(tcp_client)
  local self = setmetatable({}, Client)
  self.client = tcp_client
  self.buffer = ""
  self.state = "handshake"
  self.authenticated = false
  return self
end

function Client:send(data)
  if self.client and not self.client:is_closing() then
    self.client:write(data)
  end
end

function Client:send_json(message)
  self:send(frame.text_frame(vim.json.encode(message)))
end

function Client:close()
  if self.client and not self.client:is_closing() then
    if self.state == "connected" then
      self:send(frame.close_frame())
    end
    self.client:close()
  end
  self.state = "closed"
  self.client = nil
end

function Client:handle_data(data, on_message, on_close)
  self.buffer = self.buffer .. data

  while #self.buffer > 0 do
    if self.state == "handshake" then
      local headers_end = self.buffer:find("\r\n\r\n")
      if not headers_end then
        break
      end

      local request = self.buffer:sub(1, headers_end + 3)
      self.buffer = self.buffer:sub(headers_end + 4)

      local ok = pcall(on_message, "handshake", request)
      if not ok then
        self:close()
        on_close()
        return
      end
    elseif self.state == "connected" then
      local decoded = frame.decode_frame(self.buffer)
      if not decoded then
        break
      end

      self.buffer = self.buffer:sub(decoded.consumed + 1)

      if not decoded.masked then
        self:close()
        on_close()
        return
      end

      if decoded.opcode == 0x8 then
        self:close()
        on_close()
        return
      elseif decoded.opcode == 0x9 then
        self:send(frame.pong_frame())
      elseif decoded.opcode == 0xA then
      elseif decoded.opcode == 0x1 then
        local ok = pcall(on_message, "message", decoded.payload)
        if not ok then
          self:close()
          on_close()
          return
        end
      end
    else
      break
    end
  end
end

function Client:set_state(state)
  self.state = state
end

function Client:is_connected()
  return self.state == "connected" and self.client and not self.client:is_closing()
end

return Client
