local M = {}

---@param command opencode.server.Command | string
---@param server opencode.server.Server
---@return Promise<any>
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
