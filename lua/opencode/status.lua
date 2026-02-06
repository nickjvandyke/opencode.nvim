local M = {}

---@alias opencode.status.Status
---| "idle"
---| "error"
---| "responding"
---| "requesting_permission"

---@alias opencode.status.Icon
---| "󰚩"
---| "󱜙"
---| "󱚟"
---| "󱚡"
---| "󱚧"

---@type opencode.status.Status|nil
M.status = nil

---@return opencode.status.Icon
function M.statusline_icon()
  if M.status == "idle" then
    return "󰚩"
  elseif M.status == "responding" then
    return "󱜙"
  elseif M.status == "requesting_permission" then
    return "󱚟"
  elseif M.status == "error" then
    return "󱚡"
  else
    return "󱚧"
  end
end

---@return string
function M.statusline()
  local subscribed_server = require("opencode.events").subscribed_server
  local port = subscribed_server and subscribed_server.port
  return M.statusline_icon() .. (port and (" :" .. tostring(port)) or "")
end

---@param event opencode.cli.client.Event
function M.update(event)
  if
    event.type == "server.connected"
    or event.type == "session.idle"
    -- `session.idle` seems frequently followed by a few `message.updated`s...
    -- but `session.diff` seems to be a more definitive idle signal.
    -- It's sometimes also emitted in the middle of a response, but NBD.
    or event.type == "session.diff"
    -- Pretty good fallback
    or event.type == "session.heartbeat"
  then
    M.status = "idle"
  elseif
    event.type == "message.updated"
    or event.type == "message.part.updated"
    or event.type == "permission.replied"
  then
    M.status = "responding"
  elseif event.type == "permission.updated" then
    M.status = "requesting_permission"
  elseif event.type == "session.error" then
    M.status = "error"
  elseif event.type == "server.disconnected" then
    -- NOTE: *we* send server.disconnected when unsubscribing or `opencode`'s heartbeat disappears
    M.status = nil
  end
end

return M
