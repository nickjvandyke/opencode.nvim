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
---
---@field session_diff? opencode.events.session_diff.Opts

local heartbeat_timer = vim.uv.new_timer()
local OPENCODE_HEARTBEAT_INTERVAL_MS = 30000

---Subscribe to `opencode`'s Server-Sent Events (SSE) to execute `OpencodeEvent:<event.type>` autocmds.
function M.subscribe()
  if not require("opencode.config").opts.events.enabled then
    return
  end

  require("opencode.cli.server")
    .get_port(false)
    :next(function(port)
      require("opencode.cli.client").sse_subscribe(
        port,
        ---@param response opencode.cli.client.Event
        function(response)
          heartbeat_timer:stop()
          heartbeat_timer:start(
            OPENCODE_HEARTBEAT_INTERVAL_MS + 5000,
            0,
            vim.schedule_wrap(require("opencode.events").unsubscribe)
          )

          vim.api.nvim_exec_autocmds("User", {
            pattern = "OpencodeEvent:" .. response.type,
            data = {
              event = response,
              port = port,
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
  heartbeat_timer:stop()
  require("opencode.cli.client").sse_unsubscribe()

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
