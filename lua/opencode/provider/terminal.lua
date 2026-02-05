---Provide an embedded `opencode` via a [Neovim terminal](https://neovim.io/doc/user/terminal.html) buffer.
---@class opencode.provider.Terminal : opencode.Provider
---
---@field opts opencode.provider.terminal.Opts
---
---@field bufnr? integer
---@field winid? integer
local Terminal = {}
Terminal.__index = Terminal
Terminal.name = "terminal"

---@class opencode.provider.terminal.Opts : vim.api.keyset.win_config

function Terminal.new(opts)
  local self = setmetatable({}, Terminal)
  self.opts = opts or {}
  self.winid = nil
  self.bufnr = nil
  return self
end

function Terminal.health()
  return true
end

---Start if not running, else hide/show the window.
function Terminal:toggle()
  if self.bufnr == nil then
    self:start()
  else
    if self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid) then
      -- Hide the window
      vim.api.nvim_win_hide(self.winid)
      self.winid = nil
    elseif self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
      -- Show the window
      local previous_win = vim.api.nvim_get_current_win()
      self.winid = vim.api.nvim_open_win(self.bufnr, true, self.opts)
      vim.api.nvim_set_current_win(previous_win)
    end
  end
end

---Open a window with a terminal buffer.
function Terminal:start()
  if self.bufnr == nil then
    local previous_win = vim.api.nvim_get_current_win()

    self.bufnr = vim.api.nvim_create_buf(true, false)
    self.winid = vim.api.nvim_open_win(self.bufnr, true, self.opts)

    -- Redraw terminal buffer on initial render.
    -- Fixes empty columns on the right side.
    local auid
    auid = vim.api.nvim_create_autocmd("TermRequest", {
      buffer = self.bufnr,
      callback = function(ev)
        if ev.data.cursor[1] > 1 then
          vim.api.nvim_del_autocmd(auid)
          vim.api.nvim_set_current_win(self.winid)
          vim.cmd([[startinsert | call feedkeys("\<C-\>\<C-n>\<C-w>p", "n")]])
        end
      end,
    })

    -- because jobsttart runs with term=true neovim converts the created buffer
    -- into a terminal buffer which resets the keymap so we have to wait until the buffer
    -- will become a terminal to apply our local keymaps
    vim.api.nvim_create_autocmd("TermOpen", {
      buffer = self.bufnr,
      once = true,
      callback = function(event)
        require("opencode.keymaps").apply(event.buf)
      end,
    })

    vim.fn.jobstart(self.cmd, {
      term = true,
      on_exit = function()
        self.winid = nil
        self.bufnr = nil
      end,
    })

    vim.api.nvim_set_current_win(previous_win)
  end
end

---Close the window, delete the buffer.
function Terminal:stop()
  if self.winid ~= nil and vim.api.nvim_win_is_valid(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
    self.winid = nil
  end
  if self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

return Terminal
