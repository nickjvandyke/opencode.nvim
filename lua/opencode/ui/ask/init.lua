---@module 'snacks.input'

---@class opencode.ask.Opts
---@field prompt? string Text of the prompt.
---@field snacks? snacks.input.Opts Options for [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).

local M = {}

---@param default? string Text to pre-fill the input with.
---@param context opencode.context.Context
---@return Promise<string> input
function M.ask(default, context)
  local config = require("opencode.config")
  ---@type snacks.input.Opts
  local input_opts = {
    default = default,
    highlight = function(text)
      return context:render(text).input:input_highlight()
    end,
  }
  input_opts = vim.tbl_deep_extend("keep", config.opts.ask, input_opts)

  local snacks_ok, snacks = pcall(require, "snacks")
  if snacks_ok and snacks.config.get("input", {}).enabled then
    -- snacks.input expects its specific options at the root level.
    -- Unlike snacks.picker, which expects them under a `snacks` field.
    -- We nest our own `ask.snacks` for consistency, and then merge it to the root here.
    --
    -- Note that we only merge when passing to `snacks.input`.
    -- Even though it has no effect, passing these opts to the native `vim.ui.input` will error because
    -- they mix string and integer keys which Neovim doesn't support in `vim.g` (see comment on `vim.g.opencode_opts`),
    -- and Neovim's native `vim.ui.select` implementation apparently uses those.
    input_opts = vim.tbl_deep_extend("keep", input_opts, config.opts.ask.snacks)
  end

  return require("opencode.promise.ui").input(input_opts):catch(function(err)
    context:resume()
    return require("opencode.promise").reject(err)
  end)
end

-- FIX: Overridden by blink.cmp cmdline completion if enabled, and that won't have the below items.
-- Can we wire up the below as a blink.cmp cmdline source?

---Completion function for context placeholders and OpenCode subagents.
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
  local server = require("opencode.server").connected
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
