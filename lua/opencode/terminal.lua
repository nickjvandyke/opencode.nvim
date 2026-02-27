local M = {}

---@class opencode.terminal.Opts : vim.api.keyset.win_config
local defaults = {
  split = "right",
  width = math.floor(vim.o.columns * 0.35),
}

local winid
local bufnr

---Apply buffer-local keymaps to send commands for Neovim-like message navigation.
---@param buf integer
local function keymaps(buf)
  local opts = { buffer = buf }

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

---Start if not running, else show/hide the window.
---@param cmd string
function M.toggle(cmd, opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})
  if bufnr == nil then
    -- TODO: Check for a terminal restored from a previous session and reuse it instead
    M.start(cmd, opts)
  else
    if winid ~= nil and vim.api.nvim_win_is_valid(winid) then
      -- Hide the window
      vim.api.nvim_win_hide(winid)
      winid = nil
    elseif bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
      -- Show the window
      local previous_win = vim.api.nvim_get_current_win()
      winid = vim.api.nvim_open_win(bufnr, true, opts)
      vim.api.nvim_set_current_win(previous_win)
    end
  end
end

---@param cmd string
function M.start(cmd, opts)
  opts = vim.tbl_deep_extend("force", defaults, opts or {})
  if bufnr == nil then
    local previous_win = vim.api.nvim_get_current_win()
    bufnr = vim.api.nvim_create_buf(true, false)
    winid = vim.api.nvim_open_win(bufnr, true, opts)

    M.setup(winid)

    vim.fn.jobstart(cmd, {
      term = true,
      on_exit = function()
        winid = nil
        bufnr = nil
      end,
    })

    vim.api.nvim_set_current_win(previous_win)
  end
end

function M.stop()
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
function M.setup(win)
  local buf = vim.api.nvim_win_get_buf(win)
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
      local ok, _pid = pcall(vim.fn.jobpid, vim.b[event.buf].terminal_job_id)
      if ok then
        pid = _pid
      end
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
        vim.cmd([[startinsert | call feedkeys("\<C-\>\<C-n>\<C-w>p", "n")]])
      end
    end,
  })

  -- When the terminal's job stops normally
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buf,
    once = true,
    callback = function()
      terminate(pid)
    end,
  })
  -- Neovim doesn't execute TermClose when exiting, so listen for ExitPre too
  vim.api.nvim_create_autocmd("ExitPre", {
    once = true,
    callback = function()
      terminate(pid)
    end,
  })
end

return M
