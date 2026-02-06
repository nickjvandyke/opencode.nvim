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
local OPENCODE_HEARTBEAT_INTERVAL_MS = 30000
---@type number?
local subscription_job_id = nil
---@type opencode.cli.server.Server?
M.subscribed_server = nil

---Subscribe to `opencode`'s Server-Sent Events (SSE) to execute `OpencodeEvent:<event.type>` autocmds.
---
---@param server opencode.cli.server.Server The port to subscribe to. If nil, will attempt to find an active `opencode` server.
function M.subscribe(server)
  if not require("opencode.config").opts.events.enabled then
    return
  end

  if subscription_job_id then
    M.unsubscribe()
  end

  require("opencode.promise")
    .resolve(server)
    :next(function(_server) ---@param _server opencode.cli.server.Server
      subscription_job_id = require("opencode.cli.client").sse_subscribe(
        _server.port,
        function(response) ---@param response opencode.cli.client.Event
          M.subscribed_server = _server
          heartbeat_timer:stop()
          heartbeat_timer:start(OPENCODE_HEARTBEAT_INTERVAL_MS + 5000, 0, vim.schedule_wrap(M.unsubscribe))

          vim.api.nvim_exec_autocmds("User", {
            pattern = "OpencodeEvent:" .. response.type,
            data = {
              event = response,
              port = _server.port,
            },
          })
        end
      )
    end)
    :catch(function(err)
      vim.notify("Failed to subscribe to SSE: " .. err, vim.log.levels.WARN)
    end)
end

function M.unsubscribe()
  if subscription_job_id then
    vim.fn.jobstop(subscription_job_id)
  end
  M.subscribed_server = nil
  heartbeat_timer:stop()

  vim.api.nvim_exec_autocmds("User", {
    pattern = "OpencodeEvent:server.disconnected",
    data = {
      event = {
        type = "server.disconnected",
      },
    },
  })
end

return M
