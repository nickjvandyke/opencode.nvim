local M = {}

---@param prompt string
---@param context opencode.context.Context
---@return Promise<any>
function M.prompt(prompt, context)
  local Promise = require("opencode.promise")
  return (
    prompt:match("%.%.%.$") and require("opencode.ui.ask").ask(prompt:gsub("%.%.%.$", ""), context)
    or Promise.resolve(prompt)
  )
    :next(function(_prompt)
      local plaintext = context:render(_prompt).output:plaintext()

      return context.server:tui_append_prompt(plaintext):next(function()
        if not _prompt:match(" $") then
          return context.server:tui_execute_command("prompt.submit")
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
