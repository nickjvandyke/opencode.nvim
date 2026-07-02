---@class opencode.events.Opts
---@field enabled? boolean Subscribe to OpenCode's SSEs to dispatch `OpencodeEvent:*` autocmds.
---@field reload? boolean Reload buffers edited by OpenCode in real-time. Requires `vim.o.autoread = true`.
---@field quickfix? boolean Add files read and edited by OpenCode to a quickfix list.
---@field permissions? opencode.events.permissions.Opts

local M = {}

---@param response opencode.server.Event
---@param server opencode.server.Server
function M.emit(response, server)
  if require("opencode.config").opts.events.enabled then
    vim.api.nvim_exec_autocmds("User", {
      pattern = "OpencodeEvent:" .. response.type,
      data = {
        event = response,
        -- Can't pass metatable through here, so listeners need to reconstruct the server object if they want to use its methods
        url = server.url,
      },
    })
  end
end

return M
