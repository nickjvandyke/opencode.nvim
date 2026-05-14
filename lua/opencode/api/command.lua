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
---@param command opencode.Command|string The command to send.
---@return Promise
function M.command(command)
  return require("opencode.server").get():next(function(server) ---@param server opencode.server.Server
    server:tui_execute_command(command)
    -- opencode v1.0 prompts for a second interrupt; keep the Neovim command single-action.
    if command == "session.interrupt" then
      server:tui_execute_command(command)
    end
  end)
end

return M
