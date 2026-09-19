---@class opencode.events.permissions.edits.Opts
---@field enabled? boolean Whether to diff proposed edits for acceptance or rejection.

local M = {}

---@type string?
local current_edit_request_id = nil
---@type integer?
local diff_tabpage = nil

---Extract the diff and target file from an OpenCode v2 edit permission request.
---
---v2 shape: `{ action = "edit", resources = { file }, metadata = { files = { { file, patch, ... } } } }`
---
---TODO: this `metadata.files` shape is OpenCode v2.0.10-specific. Newer builds drop the
---diff from the edit permission request; if that ships, reconstruct it from the pending
---tool call (the event's `source` points at the message/call, whose input carries
---`path`/`oldString`/`newString`).
---
---@param event opencode.server.Event
---@return { diff: string, filepath: string }?
function M.preview(event)
  local data = event.data
  if event.type ~= "permission.asked" or data.action ~= "edit" then
    return nil
  end

  local files = data.metadata and data.metadata.files
  -- A multi-file edit only shows files[1] while the reply covers the whole request,
  -- so approve/reject blindly on the rest. Defer those to the generic permission prompt.
  -- TODO: the multi-file `patch` tool also sends a combined `metadata.diff`/`metadata.filepath`;
  -- consider displaying that instead of falling back entirely.
  if not files or #files ~= 1 then
    return nil
  end
  local file = files[1]
  if not file or not file.patch then
    return nil
  end

  return { diff = file.patch, filepath = file.file or (data.resources and data.resources[1]) }
end

---@param event opencode.server.Event
---@return Promise<opencode.server.PermissionReply>
function M.diff(event)
  local Promise = require("opencode.promise")

  local edit = M.preview(event)
  if edit then
    local diff = edit.diff

    local filepath = edit.filepath
    local absolute_filepath = vim.fn.fnamemodify(filepath, ":p")

    -- Opencode sends the absolute path sometimes with the HOME and sometimes without
    -- It has something to do with the path of the opencode server cwd wrt the file/directory
    if vim.fn.isdirectory(vim.fs.dirname(absolute_filepath)) == 1 then
      filepath = absolute_filepath
    else
      -- `os.homedir()` matches OpenCode's own resolution (and works on Windows),
      -- where `$HOME` is not reliably set.
      local home = vim.uv.os_homedir() or vim.env.HOME
      if home and home ~= "" then
        local home_filepath = vim.fs.normalize(vim.fs.joinpath(home, filepath))
        if vim.fn.isdirectory(vim.fs.dirname(home_filepath)) == 1 then
          filepath = home_filepath
        end
      end
    end

    if vim.fn.isdirectory(vim.fs.dirname(filepath)) ~= 1 then
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
    current_edit_request_id = event.data.id

    return Promise.new(function(resolve, reject)
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
        reject()
      end, { buffer = true, desc = "Close OpenCode edit diff" })
    end)
  elseif event.type == "permission.replied" and current_edit_request_id == event.data.requestID then
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
