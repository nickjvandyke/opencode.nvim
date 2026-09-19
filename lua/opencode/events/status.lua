local M = {}

---@type "idle" | "busy" | "error" | nil
local status = nil
---@type string?
M.url = nil

---@return string
function M.statusline()
  local url = (M.url and (" " .. M.url:gsub("^%w+://", "")) or "")
  return M.icon() .. url
end

---@return "󰚩" | "󱜙" | "󱚡" | "󱚧"
function M.icon()
  if status == "idle" then
    return "󰚩"
  elseif status == "busy" then
    return "󱜙"
  elseif status == "error" then
    return "󱚡"
  else
    return "󱚧"
  end
end

---@param event opencode.server.Event
---@param url string
function M.update(event, url)
  M.url = url

  if event.type == "server.connected" then
    status = "idle"
  elseif event.type == "session.status" then
    local kind = event.data and event.data.status and event.data.status.type
    if kind == "idle" then
      status = "idle"
    elseif kind == "busy" or kind == "retry" then
      status = "busy"
    end
  elseif event.type == "session.execution.failed" then
    status = "error"
  elseif event.type == "global.disposed" or event.type == "server.instance.disposed" then
    M.reset()
  end
end

function M.reset()
  status = nil
  M.url = nil
end

return M
