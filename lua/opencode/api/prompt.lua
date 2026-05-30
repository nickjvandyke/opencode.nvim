local M = {}

---@class opencode.api.prompt.Opts
---
---The context the prompt is being made in.
---On success, clears the context. On failure, resumes the context.
---@field context? opencode.Context

---@param prompt string
---@param opts? opencode.api.prompt.Opts
---@return Promise
function M.prompt(prompt, opts)
  local context = opts and opts.context or require("opencode.context").new()

  local Promise = require("opencode.promise")
  return require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      local rendered = context:render(prompt, server.subagents)
      local plaintext = context.plaintext(rendered.output)
      return server:tui_append_prompt(plaintext):next(function()
        if not prompt:match(" $") then
          return server:tui_execute_command("prompt.submit")
        else
          return true
        end
      end)
    end)
    :next(function()
      context:clear()
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

return M
