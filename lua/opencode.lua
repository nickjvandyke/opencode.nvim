---`opencode.nvim` public API.
local M = {}

----------
--- UI ---
----------

---Input a prompt for `opencode`.
---
--- - Press the up arrow to browse recent asks.
--- - Highlights and completes contexts and `opencode` subagents.
---   - Press `<Tab>` to trigger built-in completion.
--- - End the prompt with a space to append instead of submit.
--- - When using `snacks.input`, offers completions via in-process LSP.
---
---@param default? string Text to pre-fill the input with.
---@param opts? opencode.api.prompt.Opts Options for `prompt()`.
M.ask = function(default, opts)
  opts = opts or {}
  opts.context = opts.context or require("opencode.context").new()

  return require("opencode.ui.ask")
    .ask(default, opts.context)
    :next(function(input) ---@param input string
      -- TODO: Remove `opts.submit` in favor of just checking if the input ends with a space?
      -- (maybe even in `prompt()` itself?)
      -- Confusing to have both.
      -- I think it's better, but don't love the breaking change.
      -- Although for most users, I imagine they just use `opts.submit = false` and thus won't be affected.
      if input:sub(-1) == " " then
        opts.submit = false
      end
      opts.context:clear()
      return require("opencode.api.prompt").prompt(input, opts)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Select from all `opencode.nvim` functionality.
---
--- - Prompts
--- - Commands
--- - Server controls
---
--- Highlights and previews items when using `snacks.picker`.
---
---@param opts? opencode.select.Opts Override configured options for this call.
M.select = function(opts)
  return require("opencode.ui.select").select(opts):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

M.statusline = require("opencode.status").statusline

------------------------
--- Programmatic API ---
------------------------

---Prompt `opencode`.
---
--- - Resolves `prompt` if it references an `opts.prompts` entry by name.
--- - Injects `opts.contexts` into `prompt`.
--- - `opencode` will interpret `@` references to files or subagents
---
---@param prompt string
---@param opts? opencode.api.prompt.Opts
M.prompt = function(prompt, opts)
  return require("opencode.api.prompt").prompt(prompt, opts):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

---Command `opencode`.
---
---@param command opencode.Command|string The command to send. Can be built-in or reference your custom commands.
M.command = function(command)
  require("opencode.api.command").command(command):catch(function(err)
    if err then
      vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
    end
  end)
end

M.operator = require("opencode.api.operator").operator

----------------
--- Server ---
----------------

---Toggle the configured `opencode` server.
M.toggle = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.toggle then
    opts.server.toggle()
  else
    vim.notify("No server `toggle` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end
---Start the configured `opencode` server.
M.start = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.start then
    opts.server.start()
  else
    vim.notify("No server `start` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end
---Stop the configured `opencode` server.
M.stop = function()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.stop then
    opts.server.stop()
  else
    vim.notify("No server `stop` function configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end

--------------------
--- Integrations ---
--------------------

M.snacks_picker_send = require("opencode.integrations.pickers.snacks").send

return M
