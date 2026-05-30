local M = {}

---@alias opencode.status.Status
---| "idle"
---| "busy"
---| "error"

---@alias opencode.status.Icon
---| "󰚩"
---| "󱜙"
---| "󱚡"
---| "󱚧"

---@type opencode.status.Status|nil
M.status = nil
---@type string|nil
M.url = nil

---@return string
function M.statusline()
  local url = (M.url and (" " .. M.url:gsub("^%w+://", "")) or "")
  return M.icon() .. url
end

---@return opencode.status.Icon
function M.icon()
  if M.status == "idle" then
    return "󰚩"
  elseif M.status == "busy" then
    return "󱜙"
  elseif M.status == "error" then
    return "󱚡"
  else
    return "󱚧"
  end
end

---@param event opencode.server.Event
---@param url string
function M.update(event, url)
  M.url = url

  if
    event.type == "server.connected" or (event.type == "session.status" and event.properties.status.type == "idle")
  then
    M.status = "idle"
  elseif event.type == "session.status" and event.properties.status.type == "busy" then
    M.status = "busy"
  elseif event.type == "session.status" and event.properties.status.type == "error" then
    M.status = "error"
  elseif event.type == "server.instance.disposed" then
    M.status = nil
    M.url = nil
  end
end

return M
