local M = {}

---@class opencode.api.prompt.Opts
---@field clear? boolean Clear the TUI input before.
---@field submit? boolean Submit the TUI input after.
---@field context? opencode.Context The context the prompt is being made in.

---Prompt `opencode`.
---On success, clears the context. On failure, resumes the context.
---
---@param prompt string
---@param opts? opencode.api.prompt.Opts
---@return Promise
function M.prompt(prompt, opts)
  -- TODO: Referencing `ask = true` prompts doesn't actually ask.
  local referenced_prompt = require("opencode.config").opts.prompts[prompt]
  prompt = referenced_prompt and referenced_prompt.prompt or prompt
  opts = {
    clear = opts and opts.clear or false,
    submit = opts and opts.submit or false,
    context = opts and opts.context or require("opencode.context").new(),
  }

  local Promise = require("opencode.promise")
  return require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      return server.port
    end)
    :next(function(port) ---@param port number
      if opts.clear then
        return Promise.new(function(resolve)
          require("opencode.cli.client").tui_execute_command("prompt.clear", port, function()
            resolve(port)
          end)
        end)
      end
      return port
    end)
    :next(function(port) ---@param port number
      local rendered = opts.context:render(prompt)
      local plaintext = opts.context.plaintext(rendered.output)
      return Promise.new(function(resolve)
        require("opencode.cli.client").tui_append_prompt(plaintext, port, function()
          resolve(port)
        end)
      end)
    end)
    :next(function(port) ---@param port number
      if opts.submit then
        require("opencode.cli.client").tui_execute_command("prompt.submit", port)
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
