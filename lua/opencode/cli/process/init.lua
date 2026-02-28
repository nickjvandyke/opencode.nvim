local M = {}

---An `opencode` process.
---Retrieval is platform-dependent.
---@class opencode.cli.process.Process
---@field pid number
---@field port number

---@return opencode.cli.process.Process[]
function M.get()
  if vim.fn.has("win32") == 1 then
    return require("opencode.cli.process.windows").get()
  else
    return require("opencode.cli.process.unix").get()
  end
end

return M
