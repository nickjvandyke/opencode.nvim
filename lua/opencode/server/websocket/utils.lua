local bit = require("bit")

local M = {}

local utf8_char_pattern = "[%z\1-\127\194-\244][\128-\191]*"

function M.pack_u16(value)
  return string.char(bit.band(bit.rshift(value, 8), 0xFF), bit.band(value, 0xFF))
end

function M.pack_u32(value)
  return string.char(
    bit.band(bit.rshift(value, 24), 0xFF),
    bit.band(bit.rshift(value, 16), 0xFF),
    bit.band(bit.rshift(value, 8), 0xFF),
    bit.band(value, 0xFF)
  )
end

function M.pack_u64(value)
  local high = math.floor(value / 0x100000000)
  local low = value % 0x100000000
  return M.pack_u32(high) .. M.pack_u32(low)
end

function M.unpack_u16(value, offset)
  local high, low = value:byte(offset, offset + 1)
  return high * 0x100 + low
end

function M.unpack_u64(value, offset)
  local b1, b2, b3, b4, b5, b6, b7, b8 = value:byte(offset, offset + 7)
  local high = ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
  local low = ((b5 * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
  return high * 0x100000000 + low
end

function M.utf8_len(str)
  local len = 0
  for _ in str:gmatch(utf8_char_pattern) do
    len = len + 1
  end
  return len
end

function M.utf8_sub(str, start_char, end_char)
  local result = {}
  local char_index = 0

  for char in str:gmatch(utf8_char_pattern) do
    char_index = char_index + 1
    if char_index >= start_char and (not end_char or char_index <= end_char) then
      table.insert(result, char)
    end
  end

  return table.concat(result)
end

function M.sha1(str)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0

  local msg = str .. "\128"
  local len = #str * 8

  local zero_bytes = (56 - (#msg % 64)) % 64
  msg = msg .. string.rep("\0", zero_bytes)
  msg = msg .. M.pack_u64(len)

  for i = 1, #msg, 64 do
    local chunk = string.sub(msg, i, i + 63)
    local words = {}

    for j = 1, 16 do
      local offset = (j - 1) * 4 + 1
      local b1, b2, b3, b4 = chunk:byte(offset, offset + 3)
      words[j] = ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
    end

    for j = 17, 80 do
      words[j] = bit.rol(bit.bxor(words[j - 3], words[j - 8], words[j - 14], words[j - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4

    for j = 1, 80 do
      local f, k
      if j <= 20 then
        f = bit.bor(bit.band(b, c), bit.band(bit.bnot(b), d))
        k = 0x5A827999
      elseif j <= 40 then
        f = bit.bxor(b, c, d)
        k = 0x6ED9EBA1
      elseif j <= 60 then
        f = bit.bor(bit.band(b, c), bit.band(b, d), bit.band(c, d))
        k = 0x8F1BBCDC
      else
        f = bit.bxor(b, c, d)
        k = 0xCA62C1D6
      end

      local temp = bit.band(bit.rol(a, 5) + f + e + k + words[j], 0xFFFFFFFF)
      e = d
      d = c
      c = bit.rol(b, 30)
      b = a
      a = temp
    end

    h0 = bit.band(h0 + a, 0xFFFFFFFF)
    h1 = bit.band(h1 + b, 0xFFFFFFFF)
    h2 = bit.band(h2 + c, 0xFFFFFFFF)
    h3 = bit.band(h3 + d, 0xFFFFFFFF)
    h4 = bit.band(h4 + e, 0xFFFFFFFF)
  end

  return M.pack_u32(h0) .. M.pack_u32(h1) .. M.pack_u32(h2) .. M.pack_u32(h3) .. M.pack_u32(h4)
end

function M.base64_encode(str)
  local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local result = {}
  for i = 1, #str, 3 do
    local b1 = string.byte(str, i)
    local b2 = string.byte(str, i + 1) or 0
    local b3 = string.byte(str, i + 2) or 0
    local n = b1 * 65536 + b2 * 256 + b3

    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64

    table.insert(result, string.sub(b64chars, c1 + 1, c1 + 1))
    table.insert(result, string.sub(b64chars, c2 + 1, c2 + 1))
    table.insert(result, i + 1 <= #str and string.sub(b64chars, c3 + 1, c3 + 1) or "=")
    table.insert(result, i + 2 <= #str and string.sub(b64chars, c4 + 1, c4 + 1) or "=")
  end

  return table.concat(result)
end

function M.parse_http_headers(request)
  local headers = {}
  local lines = vim.split(request, "\r\n")

  for i, line in ipairs(lines) do
    if i > 1 and line ~= "" then
      local key, value = line:match("^([^:]+):%s*(.+)$")
      if key and value then
        headers[key:lower()] = value
      end
    end
  end

  return headers
end

function M.constant_time_compare(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then
    return false
  end

  local result = 0
  for i = 1, #a do
    result = bit.bor(result, bit.bxor(string.byte(a, i), string.byte(b, i)))
  end

  return result == 0
end

return M
