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

local heartbeat_timer = vim.uv.new_timer()
---How often `opencode` sends heartbeat events.
local OPENCODE_HEARTBEAT_INTERVAL_MS = 30000
---@type number?
local subscription_job_id = nil

---The currently-connected `opencode` server, if any.
---Executes autocmds for received SSEs.
---Cleared when the server disposes itself, the connection errors, or the heartbeat disappears.
---@type opencode.cli.server.Server?
M.connected_server = nil

---Subscribe to `opencode`'s Server-Sent Events (SSE) to execute `OpencodeEvent:<event.type>` autocmds.
---@param server opencode.cli.server.Server
function M.connect(server)
  if not require("opencode.config").opts.events.enabled then
    return
  end

  M.disconnect()

  require("opencode.promise")
    .resolve(server)
    :next(function(_server) ---@param _server opencode.cli.server.Server
      subscription_job_id = require("opencode.cli.client").sse_subscribe(
        _server.port,
        function(response) ---@param response opencode.cli.client.Event
          M.connected_server = _server

          if heartbeat_timer then
            heartbeat_timer:stop()
            heartbeat_timer:start(OPENCODE_HEARTBEAT_INTERVAL_MS + 5000, 0, vim.schedule_wrap(M.disconnect))
          end

          vim.api.nvim_exec_autocmds("User", {
            pattern = "OpencodeEvent:" .. response.type,
            data = {
              event = response,
              port = _server.port,
            },
          })
        end,
        function()
          -- Server disappeared ungracefully, e.g. process killed, network error, etc.
          M.disconnect()
        end
      )
    end)
    :catch(function(err)
      vim.notify("Failed to subscribe to SSE: " .. err, vim.log.levels.WARN)
    end)
end

function M.disconnect()
  if subscription_job_id then
    vim.fn.jobstop(subscription_job_id)
  end
  if heartbeat_timer then
    heartbeat_timer:stop()
  end

  M.connected_server = nil
end

return M
