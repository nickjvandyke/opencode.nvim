local M = {}

---@class opencode.events.Opts
---
---Whether to subscribe to Server-Sent Events (SSE) from `opencode` and execute `OpencodeEvent:<event.type>` autocmds.
---@field enabled? boolean
---
---Reload buffers edited by `opencode` in real-time.
---Requires `vim.o.autoread = true`.
---@field reload? boolean
---
---@field permissions? opencode.events.permissions.Opts

---How often `opencode` sends heartbeat events.
local OPENCODE_HEARTBEAT_INTERVAL_MS = 30000

---@class opencode.events.State
---@field heartbeat_timer uv_timer_t
---@field subscription_job_id? number
---@field connected_server? opencode.server.Server

---@type table<integer, opencode.events.State>
local tab_states = {}

---@param tab? integer
---@return opencode.events.State, integer
local function get_state(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  if not tab_states[tab] then
    tab_states[tab] = {
      heartbeat_timer = vim.uv.new_timer(),
      subscription_job_id = nil,
      connected_server = nil,
    }
  end
  return tab_states[tab], tab
end

local function refresh_compat_connected_server()
  local state = tab_states[vim.api.nvim_get_current_tabpage()]
  M.connected_server = state and state.connected_server or nil
end

local function disconnect_state(state)
  if state.subscription_job_id then
    vim.fn.jobstop(state.subscription_job_id)
  end
  if state.heartbeat_timer then
    state.heartbeat_timer:stop()
  end

  state.subscription_job_id = nil
  state.connected_server = nil
end

local function prune_invalid_tab_states()
  for tab, state in pairs(tab_states) do
    if not vim.api.nvim_tabpage_is_valid(tab) then
      disconnect_state(state)
      if state.heartbeat_timer and not state.heartbeat_timer:is_closing() then
        state.heartbeat_timer:close()
      end
      tab_states[tab] = nil
    end
  end
end

---The currently-connected `opencode` server, if any.
---Executes autocmds for received SSEs with type `OpencodeEvent:<event.type>`, passing the event and server port as data.
---Cleared when the server disposes itself, the connection errors, the heartbeat disappears, or we connect to a new server.
---@type opencode.server.Server?
M.connected_server = nil

function M.get_connected_server(tab)
  prune_invalid_tab_states()
  local state = tab_states[tab or vim.api.nvim_get_current_tabpage()]
  return state and state.connected_server or nil
end

---@param server opencode.server.Server
---@param tab? integer
function M.connect(server, tab)
  local state
  state, tab = get_state(tab)
  M.disconnect(tab)

  require("opencode.promise")
    .resolve(server)
    :next(function(_server) ---@param _server opencode.server.Server
      state.subscription_job_id = _server:sse_subscribe(function(response) ---@param response opencode.server.Event
        state.connected_server = _server
        refresh_compat_connected_server()

        if state.heartbeat_timer then
          state.heartbeat_timer:start(OPENCODE_HEARTBEAT_INTERVAL_MS + 5000, 0, vim.schedule_wrap(function()
            M.disconnect(tab)
          end))
        end

        if require("opencode.config").opts.events.enabled then
          vim.api.nvim_exec_autocmds("User", {
            pattern = "OpencodeEvent:" .. response.type,
            data = {
              event = response,
              -- Can't pass metatable through here, so listeners need to reconstruct the server object if they want to use its methods
              port = _server.port,
              tab = tab,
            },
          })
        end
      end, function()
        -- This is also called when the connection is closed normally by `vim.fn.jobstop`.
        -- i.e. when disconnecting before connecting to a new server.
        -- In that case, don't re-execute disconnect - it'd disconnect from the new server.
        if state.connected_server == _server then
          -- Server disappeared ungracefully, e.g. process killed, network error, etc.
          M.disconnect(tab)
        end
      end)
    end)
    :catch(function(err)
      vim.notify("Failed to subscribe to SSEs: " .. err, vim.log.levels.WARN, { title = "opencode" })
    end)
end

---@param tab? integer
function M.disconnect(tab)
  prune_invalid_tab_states()
  local state = tab_states[tab or vim.api.nvim_get_current_tabpage()]
  if not state then
    refresh_compat_connected_server()
    return
  end

  disconnect_state(state)
  refresh_compat_connected_server()
end

vim.api.nvim_create_autocmd("TabEnter", {
  callback = function()
    prune_invalid_tab_states()
    refresh_compat_connected_server()
  end,
})

return M
