local M = {}

---@class opencode.terminal.Opts : vim.api.keyset.win_config
---@class opencode.terminal.SetupOpts
---@field restore_focus? boolean Return focus to the previously focused window after the initial redraw workaround. Defaults to true.

local winid
local bufnr

---Start if not running, else show/hide the window.
---@param cmd string
---@param opts? opencode.terminal.Opts
function M.toggle(cmd, opts)
  opts = opts or {
    split = "right",
    width = math.floor(vim.o.columns * 0.35),
  }

  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_hide(winid)
    winid = nil
  elseif bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    local previous_win = vim.api.nvim_get_current_win()
    winid = vim.api.nvim_open_win(bufnr, true, opts)
    vim.api.nvim_set_current_win(previous_win)
  else
    M.open(cmd, opts)
  end
end

---@param cmd string
---@param opts? opencode.terminal.Opts
function M.open(cmd, opts)
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {
    split = "right",
    width = math.floor(vim.o.columns * 0.35),
  }

  local previous_win = vim.api.nvim_get_current_win()
  bufnr = vim.api.nvim_create_buf(false, false)
  winid = vim.api.nvim_open_win(bufnr, true, opts)

  vim.api.nvim_create_autocmd("ExitPre", {
    once = true,
    callback = function()
      -- Delete the buffer so session doesn't save + restore it.
      -- Not worth the complexity to handle a restored terminal,
      -- and this is consistent with most other Neovim terminal plugins.
      M.close()
    end,
  })

  M.setup(winid)

  -- Redraw terminal buffer on initial render.
  -- Fixes empty columns on the right side.
  -- Only affects our implementation for some reason; I don't see this issue in `snacks.terminal`.
  local auid
  auid = vim.api.nvim_create_autocmd("TermRequest", {
    buffer = bufnr,
    callback = function(ev)
      if ev.data.cursor[1] > 1 then
        vim.api.nvim_del_autocmd(auid)
        vim.api.nvim_set_current_win(winid)
        -- Enter insert mode to trigger redraw, then exit and return to previous window.
        vim.cmd([[startinsert | call feedkeys("\<C-\>\<C-n>\<C-w>p", "n")]])
      end
    end,
  })

  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function()
      M.close()
    end,
  })

  vim.api.nvim_set_current_win(previous_win)
end

function M.close()
  local job_id = bufnr and vim.b[bufnr].terminal_job_id
  if job_id then
    vim.fn.jobstop(job_id)
  end

  if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
    winid = nil
  end
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    bufnr = nil
  end
end

---Apply buffer-local keymaps to send commands for Neovim-like message navigation.
---@param buf integer
local function keymaps(buf)
  local opts = { buffer = buf }

  -- TODO: Explicitly target the server running in this terminal
  vim.keymap.set("n", "<C-u>", function()
    require("opencode").command("session.half.page.up")
  end, vim.tbl_extend("force", opts, { desc = "Scroll up half page" }))

  vim.keymap.set("n", "<C-d>", function()
    require("opencode").command("session.half.page.down")
  end, vim.tbl_extend("force", opts, { desc = "Scroll down half page" }))

  vim.keymap.set("n", "gg", function()
    require("opencode").command("session.first")
  end, vim.tbl_extend("force", opts, { desc = "Go to first message" }))

  vim.keymap.set("n", "G", function()
    require("opencode").command("session.last")
  end, vim.tbl_extend("force", opts, { desc = "Go to last message" }))

  vim.keymap.set("n", "<Esc>", function()
    require("opencode").command("session.interrupt")
  end, vim.tbl_extend("force", opts, { desc = "Interrupt current session (esc)" }))
end

-- Kill the terminal job and process.
-- HACK: https://github.com/anomalyco/opencode/issues/13001
---@param pid integer
local function terminate(pid)
  -- Neovim sends SIGHUP to the terminal job, but that causes `opencode` to restart itself.
  -- SIGTERM actually stops it.
  if vim.fn.has("unix") == 1 then
    -- Negative PID means terminate the entire process group - important because `opencode` spawns child processes for some stuff.
    -- And some shells, like `fish`, spawn an extra process for the shell itself and then the actual command as a child of that.
    os.execute("kill -TERM -" .. pid .. " 2>/dev/null")
  else
    pcall(vim.uv.kill, pid, "SIGTERM")
  end
end

---Apply `opencode` integrations to the given terminal buffer.
--- - Keymaps for Neovim-like message navigation.
--- - Properly clean up `opencode` process on close.
---@param win integer
---@param opts? opencode.terminal.SetupOpts
function M.setup(win, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    restore_focus = true,
  })

  local buf = vim.api.nvim_win_get_buf(win)
  ---@type integer|nil
  local pid

  vim.api.nvim_create_autocmd("TermOpen", {
    buffer = buf,
    once = true,
    callback = function(event)
      -- Because jobsttart runs with term=true, Neovim converts the created buffer
      -- into a terminal buffer which resets the keymaps. So we have to wait until the buffer
      -- is a terminal to apply our local keymaps.
      keymaps(event.buf)
      -- Cache PID eagerly at terminal open time because by the time ExitPre fires,
      -- the job has been cleared and terminal_job_id is no longer available.
      _, pid = pcall(vim.fn.jobpid, vim.b[event.buf].terminal_job_id)
    end,
  })

  -- Redraw terminal buffer on initial render.
  -- Fixes empty columns on the right side.
  local auid
  auid = vim.api.nvim_create_autocmd("TermRequest", {
    buffer = buf,
    callback = function(ev)
      if ev.data.cursor[1] > 1 then
        vim.api.nvim_del_autocmd(auid)
        vim.api.nvim_set_current_win(win)
        if opts.restore_focus then
          vim.cmd([[startinsert | call feedkeys("\<C-\>\<C-n>\<C-w>p", "n")]])
        else
          vim.cmd("startinsert")
        end
      end
    end,
  })

  -- When the terminal's job stops normally
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      if pid then
        terminate(pid)
      end
    end,
  })

  -- Neovim doesn't execute TermClose when exiting, so listen for ExitPre too
  vim.api.nvim_create_autocmd("ExitPre", {
    once = true,
    callback = function()
      if pid then
        terminate(pid)
      end
    end,
  })
end

return M
