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
--- - End the prompt with `\n` to append instead of submit.
--- - Additionally, when using `snacks.input`:
---   - Press `<C-CR>` to append instead of submit.
---   - When using `blink.cmp`, registers `opts.ask.blink_cmp_sources`.
---
---@param default? string Text to pre-fill the input with.
---@param opts? opencode.api.prompt.Opts Options for `prompt()`.
M.ask = function(default, opts)
  opts = opts or {}
  opts.context = opts.context or require("opencode.context").new()

  return require("opencode.ui.ask")
    .ask(default, opts.context)
    :next(function(input) ---@param input string
      -- TODO: Should we remove `opts.clear` and `opts.submit` in favor of just checking if the input ends with `\n`?
      -- (maybe even in `prompt()` itself?)
      -- Confusing to have both.
      -- I think it's better, but don't love the breaking change.
      -- Although for most users, I imagine they just use `opts.submit = false` and thus won't be affected.
      if input:sub(-2) == "\\n" then
        input = input:sub(1, -3) .. "\n" -- Remove the escaped `\n` and add an actual newline character for `opencode` to interpret.
        opts.clear = false
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
---   - Fetches custom commands from `opencode`
--- - Provider controls
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

---Select the active `opencode` session.
M.select_session = function()
  return require("opencode.ui.select_session")
    .select_session()
    :next(function(result) ---@param result { port: number, session: opencode.cli.client.Session }
      require("opencode.cli.client").select_session(result.port, result.session.id)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
      end
    end)
end

---Select an `opencode` server to connect to,
---sending future requests to it and subscribing to its events.
M.select_server = function()
  -- Should we also offer connected and configured server here?
  return require("opencode.cli.server")
    .get_all_servers_in_nvim_cwd()
    :next(function(servers) ---@param servers opencode.cli.server.Server[]
      return require("opencode.ui.select_server").select_server(servers)
    end)
    :next(function(server) ---@param server opencode.cli.server.Server
      require("opencode.events").connect(server)
      return server
    end)
    :catch(function(err)
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
    vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
  end)
end

M.operator = require("opencode.api.operator").operator

----------------
--- Provider ---
----------------

M.toggle = require("opencode.provider").toggle
M.start = require("opencode.provider").start
M.stop = require("opencode.provider").stop

--------------------
--- Integrations ---
--------------------

M.snacks_picker_send = require("opencode.integrations.pickers.snacks").send

return M
