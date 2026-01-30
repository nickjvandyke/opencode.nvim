---@module 'snacks'

---Provide an embedded `opencode` via [`snacks.terminal`](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).
---@class opencode.provider.Snacks : opencode.Provider
---
---@field opts snacks.terminal.Opts
local Snacks = {}
Snacks.__index = Snacks
Snacks.name = "snacks"

---@class opencode.provider.snacks.Opts : snacks.terminal.Opts

---@param opts? opencode.provider.snacks.Opts
---@return opencode.provider.Snacks
function Snacks.new(opts)
  local self = setmetatable({}, Snacks)
  self.opts = opts or {}
  return self
end

---Check if `snacks.terminal` is available and enabled.
function Snacks.health()
  local snacks_ok, snacks = pcall(require, "snacks")
  if not snacks_ok then
    return "`snacks.nvim` is not available.", {
      "Install `snacks.nvim` and enable `snacks.terminal.`",
    }
  elseif not snacks and snacks.config.get("terminal", {}).enabled then
    return "`snacks.terminal` is not enabled.",
      {
        "Enable `snacks.terminal` in your `snacks.nvim` configuration.",
      }
  end

  return true
end

function Snacks:get()
  ---@type snacks.terminal.Opts
  local opts = vim.tbl_deep_extend("force", self.opts, { create = false })
  local win = require("snacks.terminal").get(self.cmd, opts)
  return win
end

function Snacks:toggle()
  require("snacks.terminal").toggle(self.cmd, self.opts)
end

function Snacks:start()
  if not self:get() then
    require("snacks.terminal").open(self.cmd, self.opts)
  end
end

function Snacks:stop()
  local win = self:get()
  if win then
    -- TODO: Stop the job first so we don't get error exit code.
    -- Not sure how to get the job ID from snacks API though.
    win:close()
  end
end

return Snacks
