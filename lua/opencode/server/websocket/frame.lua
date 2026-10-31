local bit = require("bit")
local utils = require("opencode.server.websocket.utils")

local M = {}

local OPCODE_TEXT = 0x1
local OPCODE_CLOSE = 0x8
local OPCODE_PONG = 0xA

function M.decode_frame(data)
  if #data < 2 then
    return nil
  end

  local byte1 = string.byte(data, 1)
  local byte2 = string.byte(data, 2)

  local fin = bit.band(byte1, 0x80) ~= 0
  local opcode = bit.band(byte1, 0x0F)

  local masked = bit.band(byte2, 0x80) ~= 0
  local payload_len = bit.band(byte2, 0x7F)

  local offset = 2

  if payload_len == 126 then
    if #data < offset + 2 then
      return nil
    end
    payload_len = utils.unpack_u16(data, offset + 1)
    offset = offset + 2
  elseif payload_len == 127 then
    if #data < offset + 8 then
      return nil
    end
    payload_len = utils.unpack_u64(data, offset + 1)
    offset = offset + 8
  end

  local mask_key
  if masked then
    if #data < offset + 4 then
      return nil
    end
    mask_key = string.sub(data, offset + 1, offset + 4)
    offset = offset + 4
  end

  if #data < offset + payload_len then
    return nil
  end

  local payload = string.sub(data, offset + 1, offset + payload_len)

  if masked and mask_key then
    local decoded = {}
    for i = 1, #payload do
      local byte = string.byte(payload, i)
      local mask_byte = string.byte(mask_key, ((i - 1) % 4) + 1)
      table.insert(decoded, string.char(bit.bxor(byte, mask_byte)))
    end
    payload = table.concat(decoded)
  end

  return {
    fin = fin,
    opcode = opcode,
    masked = masked,
    payload = payload,
    consumed = offset + payload_len,
  }
end

function M.encode_frame(payload, opcode, masked)
  opcode = opcode or OPCODE_TEXT
  masked = masked or false

  local len = #payload
  local frame = {}

  table.insert(frame, string.char(bit.bor(0x80, opcode)))

  local byte2 = masked and 0x80 or 0x00

  if len <= 125 then
    table.insert(frame, string.char(bit.bor(byte2, len)))
  elseif len <= 65535 then
    table.insert(frame, string.char(bit.bor(byte2, 126)))
    table.insert(frame, utils.pack_u16(len))
  else
    table.insert(frame, string.char(bit.bor(byte2, 127)))
    table.insert(frame, utils.pack_u64(len))
  end

  if masked then
    local mask_key = {}
    for _ = 1, 4 do
      table.insert(mask_key, string.char(math.random(0, 255)))
    end
    local mask_str = table.concat(mask_key)
    table.insert(frame, mask_str)

    local masked_payload = {}
    for i = 1, len do
      local byte = string.byte(payload, i)
      local mask_byte = string.byte(mask_str, ((i - 1) % 4) + 1)
      table.insert(masked_payload, string.char(bit.bxor(byte, mask_byte)))
    end
    table.insert(frame, table.concat(masked_payload))
  else
    table.insert(frame, payload)
  end

  return table.concat(frame)
end

function M.close_frame()
  return M.encode_frame("", OPCODE_CLOSE, false)
end

function M.pong_frame()
  return M.encode_frame("", OPCODE_PONG, false)
end

function M.text_frame(payload)
  return M.encode_frame(payload, OPCODE_TEXT, false)
end

return M
