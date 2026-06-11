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
---@param command opencode.Command|string
---@param server opencode.server.Server
---@return Promise
function M.command(command, server)
  return server:tui_execute_command(command):next(function()
    if command == "session.interrupt" then
      -- Evidently OpenCode only uses this command for their "double-tap Esc to interrupt" user keybind.
      -- So we have to double-send it to actually interrupt.
      return server:tui_execute_command(command)
    end
  end)
end

return M
