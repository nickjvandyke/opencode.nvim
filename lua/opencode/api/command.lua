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

---Command `opencode`.
---
---@param command opencode.Command|string The command to send. Can be built-in or reference your custom commands.
function M.command(command)
  require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      -- No need to register SSE here - commands don't trigger any.
      -- (except maybe the `input_*` commands? but no reason for user to use those).
      require("opencode.cli.client").tui_execute_command(command, server.port)
    end)
    :catch(function(err)
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end)
end

return M
