local M = {}

---@param prompt string
---@param server opencode.server.Server
---@param context? opencode.context.Context
---@return Promise
function M.prompt(prompt, server, context)
  context = context or require("opencode.context").new()

  local rendered = context:render(prompt, server.subagents)
  local plaintext = context.plaintext(rendered.output)
  return server
    :tui_append_prompt(plaintext)
    :next(function()
      if not prompt:match(" $") then
        return server:tui_execute_command("prompt.submit")
      end
    end)
    :next(function()
      context:clear()
    end)
    :catch(function(err)
      context:resume()
      return require("opencode.promise").reject(err)
    end)
end

return M
