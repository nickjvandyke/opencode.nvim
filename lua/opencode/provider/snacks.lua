---@module 'snacks'

---Provide an embedded `opencode` via [`snacks.terminal`](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).
---@class opencode.provider.Snacks : opencode.Provider
---
---@field opts snacks.terminal.Opts
---@field private _job_id number|nil
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
  self._job_id = nil
  self._pid = nil

  -- Hook into on_buf to capture the terminal job's PID when the buffer is created.
  -- This ensures PID capture happens automatically regardless of how the terminal is
  -- started (toggle, open), without duplicating the logic in each method.
  self.opts.win = self.opts.win or {}
  local user_on_buf = self.opts.win.on_buf
  self.opts.win.on_buf = function(win)
    if user_on_buf then
      user_on_buf(win)
    end
    -- Deferred because on_buf fires before the terminal job is fully started
    vim.defer_fn(function()
      if win.buf and vim.api.nvim_buf_is_valid(win.buf) then
        self._job_id = vim.b[win.buf].terminal_job_id
        if self._job_id then
          pcall(function()
            self._pid = vim.fn.jobpid(self._job_id)
          end)
        end
      end
    end, 100)
  end

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
  -- Kill via PID (most reliable during VimLeavePre,
  -- as vim.uv.kill and jobstop may not work when Neovim is shutting down)
  if self._pid then
    if vim.fn.has("unix") == 1 then
      vim.fn.system("kill -TERM " .. self._pid .. " 2>/dev/null")
    else
      pcall(vim.uv.kill, self._pid, "sigterm")
    end
    self._pid = nil
  end

  -- Also try jobstop as a fallback
  if self._job_id then
    pcall(vim.fn.jobstop, self._job_id)
    self._job_id = nil
  end

  -- Close the window via snacks
  local win = self:get()
  if win then
    win:close()
  end
end

return Snacks
