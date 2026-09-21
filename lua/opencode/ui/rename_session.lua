---@class opencode.rename_session.Opts
---@field prompt? string Text of the prompt.
---@field snacks? snacks.input.Opts Options for [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).

local M = {}

---@param server opencode.server.Server
---@param opts? opencode.rename_session.Opts Override configured options for this call.
---@return Promise<any>
function M.rename_session(server, opts)
  local config = require("opencode.config")
  ---@type snacks.input.Opts
  local input_opts = {
    prompt = "Rename session to: ",
  }
  input_opts = vim.tbl_deep_extend("keep", config.opts.rename_session or {}, input_opts)
  input_opts = vim.tbl_deep_extend("force", input_opts, opts or {})

  local snacks_ok, snacks = pcall(require, "snacks")
  if snacks_ok and snacks.config.get("input", {}).enabled then
    input_opts = vim.tbl_deep_extend("keep", input_opts, input_opts.snacks or {})
  end
  input_opts.snacks = nil

  return server:get_sessions():next(function(sessions)
    local current
    for _, session in ipairs(sessions) do
      if session.id == server.session_id then
        current = session
        break
      end
    end
    current = current or sessions[1]
    if not current then
      return require("opencode.promise").resolve(nil)
    end

    input_opts.default = current.title
    return require("opencode.promise.ui").input(input_opts):next(function(title)
      if not title or title == "" then
        return require("opencode.promise").resolve(nil)
      end
      return server:update_session(current.id, title)
    end)
  end)
end

return M
