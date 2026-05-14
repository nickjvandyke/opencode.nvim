---@class opencode.events.permissions.edits.Opts
---
---Whether to diff proposed edits from `opencode` for acceptance or rejection.
---@field enabled? boolean

local M = {}

---@type string?
local current_edit_request_id = nil
---@type nil|integer
local diff_tabpage = nil

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
      -- Close any buffer with the same name, to avoid "Buffer with this name already exists" error when successive edit requests come in for the same file.
      vim.cmd("silent! bwipeout " .. filepath .. ".new")

      -- Diffing changes some of the buffer's display options (namely folding) to make it easier to compare side-by-side,
      -- so open the target file in a new tab first.
      vim.cmd("tabnew " .. filepath)
      -- FIX: Sometimes rejects? Or displays no changes? Particularly with a single inline change. Malformed patch?
      vim.cmd("silent vert diffpatch " .. patch_filepath)

      diff_tabpage = vim.api.nvim_get_current_tabpage()
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
        vim.cmd("tabclose")
        current_edit_request_id = nil
        diff_tabpage = nil
      end, { buffer = true, desc = "Close opencode edit diff" })
    end)
  elseif event.type == "permission.replied" and current_edit_request_id == event.properties.requestID then
    -- Entire edit was accepted or rejected, either in the plugin or TUI; close the diff
    current_edit_request_id = nil
    if diff_tabpage and vim.api.nvim_tabpage_is_valid(diff_tabpage) then
      vim.api.nvim_set_current_tabpage(diff_tabpage)
      vim.cmd("tabclose")
      diff_tabpage = nil
    end
  end
end

return M
