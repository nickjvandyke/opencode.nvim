---@class opencode.events.permissions.edits.Opts
---@field enabled? boolean Whether to diff proposed edits for acceptance or rejection.

local M = {}

---@type integer?
local current_edit_request_id = nil
---@type integer?
local diff_tabpage = nil

---@param event opencode.server.Event | { type: "permission.asked" } | { type: "permission.replied" }
---@return Promise<opencode.server.PermissionReply|nil>
function M.diff(event)
  local Promise = require("opencode.promise")

  if event.type == "permission.asked" and event.properties.permission == "edit" then
    local diff = event.properties.metadata.diff

    local filepath = event.properties.metadata.filepath
    local absolute_filepath = vim.fn.fnamemodify(filepath, ":p")

    -- Opencode sends the absolute path sometimes with the HOME and sometimes without
    -- It has something to do with the path of the opencode server cwd wrt the file/directory
    if vim.fn.filereadable(absolute_filepath) == 1 then
      filepath = absolute_filepath
    elseif vim.env.HOME and vim.env.HOME ~= "" then
      local home_filepath = vim.fs.normalize(vim.fs.joinpath(vim.env.HOME, filepath))
      if vim.fn.filereadable(home_filepath) == 1 then
        filepath = home_filepath
      end
    end

    if vim.fn.filereadable(filepath) ~= 1 then
      return Promise.reject("Cannot resolve OpenCode edit target file: " .. filepath)
    end

    local patch_filepath = vim.fn.tempname() .. ".patch"
    if vim.fn.writefile(vim.split(diff, "\n"), patch_filepath) ~= 0 then
      return Promise.reject("Failed to write patch file to diff OpenCode edit request")
    end

    filepath = vim.fn.fnameescape(filepath)

    -- Diffing changes some of the buffer's display options (namely folding) to make it easier to compare side-by-side,
    -- so open the target file in a new tab first.
    vim.cmd("tabnew " .. filepath)
    --  FIX: Errors in diff occur due to opencode's trimDiff function
    vim.cmd("silent vert diffpatch " .. patch_filepath)

    local diff_buff = vim.api.nvim_get_current_buf()
    -- When done, wipe out the buffer to avoid "Buffer with this name already exists" error when successive edit requests come in for the same file.
    -- Also prevents it from lingering in e.g. pickers and `:ls`.
    vim.bo[diff_buff].bufhidden = "wipe"
    diff_tabpage = vim.api.nvim_get_current_tabpage()
    current_edit_request_id = event.properties.id

    return Promise.new(function(resolve)
      -- Override native hunk-specific keymaps to reject the edit as a whole first
      vim.keymap.set("n", "dp", function()
        if current_edit_request_id then
          -- Clear so we don't close the tabpage in the "permission.replied" handler
          -- and user can continue accepting/rejecting individual hunks (and then close the tabpage manually)
          current_edit_request_id = nil
          resolve("reject")
        end
        return "dp"
      end, { buffer = true, desc = "Accept OpenCode edit hunk", expr = true })
      vim.keymap.set("n", "do", function()
        if current_edit_request_id then
          current_edit_request_id = nil
          resolve("reject")
        end
        return "do"
      end, { buffer = true, desc = "Reject OpenCode edit hunk", expr = true })

      -- Accept/reject edit as a whole
      vim.keymap.set("n", "da", function()
        resolve("once")
      end, { buffer = true, desc = "Accept OpenCode edit" })

      vim.keymap.set("n", "dr", function()
        resolve("reject")
      end, { buffer = true, desc = "Reject OpenCode edit" })

      -- Close diff without accepting/rejecting
      vim.keymap.set("n", "q", function()
        vim.cmd("tabclose")
        current_edit_request_id = nil
        diff_tabpage = nil
        resolve(nil)
      end, { buffer = true, desc = "Close OpenCode edit diff" })
    end)
  elseif event.type == "permission.replied" and current_edit_request_id == event.properties.requestID then
    -- Entire edit was accepted or rejected, either in the plugin or TUI; close the diff
    current_edit_request_id = nil
    if diff_tabpage and vim.api.nvim_tabpage_is_valid(diff_tabpage) then
      vim.api.nvim_set_current_tabpage(diff_tabpage)
      vim.cmd("tabclose")
      diff_tabpage = nil
      return Promise.resolve(nil)
    end
  end

  return Promise.resolve(nil)
end

return M
