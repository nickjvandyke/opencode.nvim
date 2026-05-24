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

---@class opencode.status.State
---@field status opencode.status.Status|nil
---@field url string|nil

---@type table<integer, opencode.status.State>
local states_by_tab = {}

---@param tab? integer
---@return integer
local function normalize_tab(tab)
  return tab or vim.api.nvim_get_current_tabpage()
end

---@param tab? integer
---@return opencode.status.State
local function get_state(tab)
  tab = normalize_tab(tab)
  states_by_tab[tab] = states_by_tab[tab] or {}
  return states_by_tab[tab]
end

local function refresh_compat_state()
  local state = get_state()
  M.status = state.status
  M.url = state.url
end

---@return string
function M.statusline()
  local state = get_state()
  local url = (state.url and (" " .. state.url:gsub("^%w+://", "")) or "")
  return M.icon_for_status(state.status) .. url
end

---@param status? opencode.status.Status
---@return opencode.status.Icon
function M.icon_for_status(status)
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

---@return opencode.status.Icon
function M.icon()
  return M.icon_for_status(M.status)
end

---@param event opencode.server.Event
---@param url string
---@param tab? integer
function M.update(event, url, tab)
  local state = get_state(tab)
  state.url = url

  if
    event.type == "server.connected" or (event.type == "session.status" and event.properties.status.type == "idle")
  then
    state.status = "idle"
  elseif event.type == "session.status" and event.properties.status.type == "busy" then
    state.status = "busy"
  elseif event.type == "session.status" and event.properties.status.type == "error" then
    state.status = "error"
  elseif event.type == "server.instance.disposed" then
    state.status = nil
    state.url = nil
  end

  refresh_compat_state()
end

vim.api.nvim_create_autocmd("TabEnter", {
  callback = function()
    refresh_compat_state()
  end,
})

return M
