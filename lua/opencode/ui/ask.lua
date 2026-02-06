---@module 'snacks.input'

local M = {}

---@class opencode.ask.Opts
---
---Text of the prompt.
---@field prompt? string
---
---Completion sources to automatically register when using [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md) and [`blink.cmp`](https://github.com/Saghen/blink.cmp).
---The `"opencode"` source offers completions and previews for contexts and `opencode` subagents.
---@field blink_cmp_sources? string[]
---
---Options for [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field snacks? snacks.input.Opts

---Input a prompt for `opencode`.
---
--- - Press the up arrow to browse recent asks.
--- - Highlights and completes contexts and `opencode` subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Registers `opts.ask.blink_cmp_sources` when using `snacks.input` and `blink.cmp`.
---
---@param default? string Text to pre-fill the input with.
---@param opts? opencode.api.prompt.Opts Options for `prompt()`.
function M.ask(default, opts)
  opts = opts or {}
  opts.context = opts.context or require("opencode.context").new()
  require("opencode.cmp.blink").context = opts.context
  local Promise = require("opencode.promise")

  ---@type snacks.input.Opts
  local input_opts = {
    default = default,
    highlight = function(text)
      local rendered = opts.context:render(text)
      -- Transform to `:help input()-highlight` format
      return vim.tbl_map(function(extmark)
        return { extmark.col, extmark.end_col, extmark.hl_group }
      end, opts.context.extmarks(rendered.input))
    end,
    completion = "customlist,v:lua.opencode_completion",
    -- `snacks.input`-only options
    win = {
      b = {
        -- Enable `blink.cmp` completion
        completion = true,
      },
      bo = {
        -- Custom filetype to enable `blink.cmp` source on
        filetype = "opencode_ask",
      },
      on_buf = function(win)
        -- Wait as long as possible to check for `blink.cmp` loaded - many users lazy-load on `InsertEnter`.
        -- And OptionSet :runtimepath didn't seem to fire for lazy.nvim. And/or it may never fire if already loaded.
        vim.api.nvim_create_autocmd("InsertEnter", {
          once = true,
          buffer = win.buf,
          callback = function()
            if package.loaded["blink.cmp"] then
              require("opencode.cmp.blink").setup(require("opencode.config").opts.ask.blink_cmp_sources)
            end
          end,
        })
      end,
    },
  }
  -- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config,
  -- and to keep its fields optional. Double-merge is kinda ugly but seems like the lesser evil.
  input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask)
  input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask.snacks)

  require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      return server.port
    end)
    :next(function(port) ---@param port number
      return Promise.new(function(resolve)
        require("opencode.cli.client").get_agents(port, function(agents)
          opts.context.agents = vim.tbl_filter(function(agent)
            return agent.mode == "subagent"
          end, agents)

          resolve(true)
        end)
      end)
    end)
    :next(function()
      return Promise.input(input_opts)
    end)
    :next(function(input) ---@param input string
      require("opencode").prompt(input, opts)
      opts.context:clear()
    end)
    :catch(function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
      end
      opts.context:resume()
    end)
end

-- FIX: Overridden by blink.cmp cmdline completion if both are enabled, and that won't have our items.
-- Possible to register our blink source there? But only active in our own vim.ui.input calls.

---Completion function for context placeholders and `opencode` subagents.
---Must be a global variable for use with `vim.ui.select`.
---
---@param ArgLead string The text being completed.
---@param CmdLine string The entire current input line.
---@param CursorPos number The cursor position in the input line.
---@return table<string> items A list of filtered completion items.
_G.opencode_completion = function(ArgLead, CmdLine, CursorPos)
  -- Not sure if it's me or vim, but ArgLead = CmdLine... so we have to parse and complete the entire line, not just the last word.
  local start_idx, end_idx = CmdLine:find("([^%s]+)$")
  local latest_word = start_idx and CmdLine:sub(start_idx, end_idx) or nil

  local completions = {}
  for placeholder, _ in pairs(require("opencode.config").opts.contexts) do
    table.insert(completions, placeholder)
  end
  for _, agent in ipairs(require("opencode.cmp.blink").context.agents or {}) do
    table.insert(completions, "@" .. agent.name)
  end

  local items = {}
  for _, completion in pairs(completions) do
    if not latest_word then
      local new_cmd = CmdLine .. completion
      table.insert(items, new_cmd)
    elseif completion:find(latest_word, 1, true) == 1 then
      local new_cmd = CmdLine:sub(1, start_idx - 1) .. completion .. CmdLine:sub(end_idx + 1)
      table.insert(items, new_cmd)
    end
  end
  return items
end

return M
