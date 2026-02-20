---@module 'snacks.input'

local M = {}

---@class opencode.ask.Opts
---
---Text of the prompt.
---@field prompt? string
---
---Options for [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field snacks? snacks.input.Opts

---Prompt for input with `vim.ui.input`, with context- and server-aware completion.
---
---@param default? string Text to pre-fill the input with.
---@param context opencode.Context
---@return Promise<string> input
function M.ask(default, context)
  local Promise = require("opencode.promise")

  return require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      ---@type snacks.input.Opts
      local input_opts = {
        default = default,
        highlight = function(text)
          local rendered = context:render(text, server.subagents)
          return context.input_highlight(rendered.input)
        end,
      }
      -- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config,
      -- and to keep its fields optional. Double-merge is kinda ugly but seems like the lesser evil.
      input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask)
      input_opts = vim.tbl_deep_extend("force", input_opts, require("opencode.config").opts.ask.snacks)

      return Promise.input(input_opts)
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

-- FIX: Overridden by blink.cmp cmdline completion if enabled, and that won't have the below items.
-- Can we wire up the below as a blink.cmp cmdline source?

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
  local server = require("opencode.events").connected_server
  local agents = server and server.subagents or {}
  for _, agent in ipairs(agents) do
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
