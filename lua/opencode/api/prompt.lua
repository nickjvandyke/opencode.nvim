local M = {}

---@class opencode.api.prompt.Opts
---@field submit? boolean Submit the TUI input after.
---@field context? opencode.Context The context the prompt is being made in.

---Prompt `opencode`.
---On success, clears the context. On failure, resumes the context.
---
---@param prompt string
---@param opts? opencode.api.prompt.Opts
---@return Promise
function M.prompt(prompt, opts)
  opts = {
    submit = opts and opts.submit or false,
    context = opts and opts.context or require("opencode.context").new(),
  }

  local Promise = require("opencode.promise")
  return require("opencode.server")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      local rendered = opts.context:render(prompt, server.subagents)
      local plaintext = opts.context.plaintext(rendered.output)
      return Promise.new(function(resolve)
        server:tui_append_prompt(plaintext, function()
          resolve(server)
        end)
      end)
    end)
    :next(function(server) ---@param server opencode.server.Server
      if opts.submit then
        server:tui_execute_command("prompt.submit")
      end
    end)
    :next(function()
      opts.context:clear()
    end)
    :catch(function(err)
      opts.context:resume()
      return Promise.reject(err)
    end)
end

return M
