local M = {}

---Select an `opencode` server from a given list.
---
---@param servers opencode.cli.server.Server[]
---@return Promise<opencode.cli.server.Server>
function M.select_server(servers)
  local picker_opts = {
    prompt = "Select an `opencode` server:",
    format_item = function(server) ---@param server opencode.cli.server.Server
      return string.format("%s | %s | %d", server.title or "<No sessions>", server.cwd, server.port)
    end,
    snacks = {
      layout = {
        hidden = { "preview" },
      },
    },
  }
  picker_opts = vim.tbl_deep_extend("keep", picker_opts, require("opencode.config").opts.select or {})

  return require("opencode.promise").select(servers, picker_opts)
end

return M
