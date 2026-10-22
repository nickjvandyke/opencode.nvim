local M = {}

---Run a registered OpenCode command in the resolved session.
---
---@param name string
---@param text string Arguments for the command.
---@param server opencode.server.Server
---@return Promise<any>
function M.command(name, text, server)
  return server:resolve_session():next(function(session)
    return server:run_command(session.id, name, text)
  end)
end

return M
