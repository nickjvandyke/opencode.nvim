---@class opencode.events.permissions.edits.Opts
---
---Whether to diff proposed edits from `opencode` for acceptance or rejection.
---@field enabled? boolean

local M = {}

---@type string?
local current_edit_request_id = nil
---@type nil|integer
local diff_tabpage = nil
---@type nil|integer
local diff_new_buf = nil
---@type nil|integer
local diff_tab_closed_autocmd = nil

local diff_cleanup_group = vim.api.nvim_create_augroup("OpencodeEditDiffCleanup", { clear = false })

local function clear_tab_closed_autocmd()
  if diff_tab_closed_autocmd then
    pcall(vim.api.nvim_del_autocmd, diff_tab_closed_autocmd)
    diff_tab_closed_autocmd = nil
  end
end

local function cleanup_diff()
  clear_tab_closed_autocmd()
  current_edit_request_id = nil
  diff_tabpage = nil

  if diff_new_buf and vim.api.nvim_buf_is_valid(diff_new_buf) then
    vim.api.nvim_buf_delete(diff_new_buf, { force = true })
  end
  diff_new_buf = nil
end

local function close_diff_tab()
  if diff_tabpage and vim.api.nvim_tabpage_is_valid(diff_tabpage) then
    vim.api.nvim_set_current_tabpage(diff_tabpage)
    vim.cmd("tabclose")
  end

  cleanup_diff()
end

local function register_diff_tab_cleanup()
  clear_tab_closed_autocmd()

  local tabpage = diff_tabpage
  diff_tab_closed_autocmd = vim.api.nvim_create_autocmd("TabClosed", {
    group = diff_cleanup_group,
    callback = function()
      if tabpage and not vim.api.nvim_tabpage_is_valid(tabpage) then
        cleanup_diff()
      end
    end,
    desc = "Clean up opencode edit diff buffer",
  })
end

---@param event opencode.server.Event
---@param server opencode.server.Server
function M.diff(event, server)
  local opts = require("opencode.config").opts.events.permissions or {}

  if event.type == "permission.asked" and event.properties.permission == "edit" then
    local idle_delay_ms = opts.idle_delay_ms or 1000
    vim.notify(
      "`opencode` requested permission — awaiting idle…",
      vim.log.levels.INFO,
      { title = "opencode", timeout = idle_delay_ms }
    )
    require("opencode.util").on_user_idle(idle_delay_ms, function()
      -- TODO: Handle multi-file edits?
      -- When would opencode even do that?
      -- for _, file in ipairs(event.properties.metadata.diff) do

      local diff = event.properties.metadata.diff

      local patch_filepath = vim.fn.tempname() .. ".patch"
      if vim.fn.writefile(vim.split(diff, "\n"), patch_filepath) ~= 0 then
        vim.notify(
          "Failed to write patch file to diff opencode edit request",
          vim.log.levels.ERROR,
          { title = "opencode" }
        )
        return
      end

      local filepath = event.properties.metadata.filepath

      -- Diffing changes some of the buffer's display options (namely folding) to make it easier to compare side-by-side,
      -- so open the target file in a new tab first.
      vim.cmd("tabnew " .. vim.fn.fnameescape(filepath))
      -- FIX: Sometimes rejects? Or displays no changes? Particularly with a single inline change. Malformed patch?
      vim.cmd("silent vert diffpatch " .. vim.fn.fnameescape(patch_filepath))

      diff_tabpage = vim.api.nvim_get_current_tabpage()
      diff_new_buf = vim.api.nvim_get_current_buf()
      register_diff_tab_cleanup()

      vim.bo[diff_new_buf].buflisted = false

      current_edit_request_id = event.properties.id

      ---@param reply opencode.server.permission.Reply
      local function permit(reply)
        server:permit(event.properties.id, reply)
      end

      -- Override native accept/reject keymaps to reject the edit as a whole first, if it hasn't been already
      vim.keymap.set("n", "dp", function()
        if current_edit_request_id then
          -- Clear so we don't close the tabpage in the "permission.replied" handler
          -- and user can continue accepting/rejecting individual hunks (and then close the tabpage manually)
          current_edit_request_id = nil
          permit("reject")
        end
        return "dp"
      end, { buffer = true, desc = "Accept opencode edit hunk", expr = true })
      vim.keymap.set("n", "do", function()
        if current_edit_request_id then
          current_edit_request_id = nil
          permit("reject")
        end
        return "do"
      end, { buffer = true, desc = "Reject opencode edit hunk", expr = true })
      -- Accept/reject edit as a whole
      vim.keymap.set("n", "da", function()
        permit("once")
      end, { buffer = true, desc = "Accept opencode edit" })
      vim.keymap.set("n", "dr", function()
        permit("reject")
      end, { buffer = true, desc = "Reject opencode edit" })
      -- Close diff
      vim.keymap.set("n", "q", function()
        close_diff_tab()
      end, { buffer = true, desc = "Close opencode edit diff" })
    end)
  elseif event.type == "permission.replied" and current_edit_request_id == event.properties.requestID then
    -- Entire edit was accepted or rejected, either in the plugin or TUI; close the diff
    close_diff_tab()
  end
end

return M
