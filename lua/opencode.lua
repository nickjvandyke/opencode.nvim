---`opencode.nvim` public API.
local M = {}

----------
--- UI ---
----------

---Input a prompt for OpenCode.
---
--- - End the prompt with a space to append instead of submit.
--- - Press `<Up>` to browse recent asks.
--- - Highlights and completes contexts and OpenCode subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Provided by in-process LSP when using `snacks.input`.
---
---@param default? string Text to pre-fill the input with.
function M.ask(default)
  local context = require("opencode.context").new()

  require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return require("opencode.ui.ask").ask(default, server, context):next(function(input) ---@param input string
        return require("opencode.api.prompt").prompt(input, server, context)
      end)
    end)
    :catch(function(err)
      context:resume()
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Select from all `opencode.nvim` functionality.
---
--- - Prompts
--- - Commands
--- - Servers
---
--- Highlights and previews items when using `snacks.picker`.
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return require("opencode.ui.select").select(opts, server)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

M.statusline = require("opencode.events.status").statusline

------------------------
--- Programmatic API ---
------------------------

---Prompt OpenCode.
---
--- - End the prompt with a space to append instead of submit.
--- - OpenCode will interpret references to files or subagents
---
---@param prompt string
function M.prompt(prompt)
  require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return require("opencode.api.prompt").prompt(prompt, server)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Command OpenCode.
---
---@param command opencode.Command|string
function M.command(command)
  require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return require("opencode.api.command").command(command, server)
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
      end
    end)
end

---Wraps `prompt` as an operator, supporting ranges and dot-repeat.
---
---@param prompt string
function M.operator(prompt)
  ---@param kind "char"|"line"|"block"
  _G.opencode_prompt_operator = function(kind)
    local start_pos = vim.api.nvim_buf_get_mark(0, "[")
    local end_pos = vim.api.nvim_buf_get_mark(0, "]")
    if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
      start_pos, end_pos = end_pos, start_pos
    end

    local context = require("opencode.context").new({
      from = { start_pos[1], start_pos[2] },
      to = { end_pos[1], end_pos[2] },
      kind = kind,
    })

    require("opencode.server.discovery")
      .get()
      :next(function(server) ---@param server opencode.server.Server
        return require("opencode.api.prompt").prompt(prompt, server, context)
      end)
      :catch(function(err)
        if err then
          vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end)
  end

  vim.o.operatorfunc = "v:lua.opencode_prompt_operator"
  return "g@"
end

M.format = require("opencode.context").format

----------------
--- Server ---
----------------

---Start the configured OpenCode server.
function M.start()
  local opts = require("opencode.config").opts
  if opts.server and opts.server.start then
    opts.server.start()
  else
    vim.notify("No `vim.g.opencode_opts.server.start` configured", vim.log.levels.ERROR, { title = "opencode" })
  end
end
return M
