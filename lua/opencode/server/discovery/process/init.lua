local M = {}

---An `opencode` process.
---Retrieval is platform-dependent.
---@class opencode.server.discovery.process.Process
---@field pid number
---@field port number

---@return opencode.server.discovery.process.Process[]
function M.get()
  if vim.fn.has("win32") == 1 then
    return require("opencode.server.discovery.process.windows").get()
  else
    return require("opencode.server.discovery.process.unix").get()
  end
end

return M
