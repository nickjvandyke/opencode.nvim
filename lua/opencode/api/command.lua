local M = {}

---See available commands [here](https://github.com/sst/opencode/blob/dev/packages/opencode/src/cli/cmd/tui/event.ts).
---@alias opencode.Command
---| 'session.list'
---| 'session.new'
---| 'session.share'
---| 'session.interrupt'
---| 'session.compact'
---| 'session.page.up'
---| 'session.page.down'
---| 'session.half.page.up'
---| 'session.half.page.down'
---| 'session.first'
---| 'session.last'
---| 'session.undo'
---| 'session.redo'
---| 'prompt.submit'
---| 'prompt.clear'
---| 'agent.cycle'

---Send a command to `opencode`.
---
---@param command opencode.Command|string The command to send. Can be built-in or reference your custom commands.
---@return Promise
function M.command(command)
  return require("opencode.cli.server").get():next(function(server) ---@param server opencode.cli.server.Server
    -- TODO: Use `on_error` callbacks to reject?
    -- Rather than rely on non-obvious notifying lower down.
    require("opencode.cli.client").tui_execute_command(command, server.port)
  end)
end

return M
