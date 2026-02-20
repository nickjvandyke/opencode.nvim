---@module 'snacks'

local util = require("opencode.provider.util")

---Provide an embedded `opencode` via [`snacks.terminal`](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).
---@class opencode.provider.Snacks : opencode.Provider
---
---@field opts snacks.terminal.Opts
---@field private _pid number|nil
local Snacks = {}
Snacks.__index = Snacks
Snacks.name = "snacks"

---@class opencode.provider.snacks.Opts : snacks.terminal.Opts

---@param opts? opencode.provider.snacks.Opts
---@return opencode.provider.Snacks
function Snacks.new(opts)
  local self = setmetatable({}, Snacks)
  self.opts = opts or {}
  self._pid = nil

  -- Hook into on_buf to capture the terminal job's PID when the buffer is created.
  -- We must capture the PID eagerly at startup because by the time VimLeavePre fires
  -- and stop() is called, the terminal job has been cleared and terminal_job_id is no
  -- longer available. This also ensures PID capture happens automatically regardless
  -- of how the terminal is started (toggle, open), without duplicating the logic.
  self.opts.win = self.opts.win or {}
  local user_on_buf = self.opts.win.on_buf
  self.opts.win.on_buf = function(win)
    if user_on_buf then
      user_on_buf(win)
    end
    ---@diagnostic disable: invisible -- accessing private fields from closure within constructor
    vim.api.nvim_create_autocmd("TermOpen", {
      buffer = win.buf,
      once = true,
      callback = function()
        self:get_pid()
      end,
    })
    ---@diagnostic enable: invisible
  end

  return self
end

---Check if `snacks.terminal` is available and enabled.
function Snacks.health()
  local snacks_ok, snacks = pcall(require, "snacks")
  ---@cast snacks Snacks
  if not snacks_ok then
    return "`snacks.nvim` is not available.", {
      "Install `snacks.nvim` and enable `snacks.terminal.`",
    }
  elseif not snacks.config.get("terminal", {}).enabled then
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
  util.kill(self._pid)
  self._pid = nil

  local win = self:get()
  if win then
    win:close()
  end
end

---Capture and cache the PID of the terminal job.
---@return number?
function Snacks:get_pid()
  local buf = self:get() and self:get().buf
  if not self._pid and buf then
    local job_id = vim.b[buf].terminal_job_id
    if job_id then
      local ok, pid = pcall(vim.fn.jobpid, job_id)
      if ok then
        self._pid = pid
      end
    end
  end

  return self._pid
end

return Snacks
