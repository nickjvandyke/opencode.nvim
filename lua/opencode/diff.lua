local M = {}

---@class opencode.events.session_diff.Opts
---
---Whether to enable the ability to review diff after the agent finishes responding
---@field enabled boolean
---
---Whether to open the review in a new tab (and reuse the same tab for navigation)
---@field open_in_tab? boolean

---@class opencode.diff.State
---@field bufnr number? Temporary buffer for diff display
---@field winnr number? Window number for diff display
---@field tabnr number? Tab number for diff display (when using open_in_tab)
---@field session_diff table? Session diff data for session review

M.state = {
  bufnr = nil,
  winnr = nil,
  tabnr = nil,
  session_diff = nil,
}

---Clean up diff buffer and state
function M.cleanup()
  if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.api.nvim_buf_delete(M.state.bufnr, { force = true })
  end

  M.state.bufnr = nil
end

---Check if diff content is actually empty (no meaningful changes)
---@param file_data table File diff data
---@return boolean
local function is_diff_empty(file_data)
  local before = file_data.before or ""
  local after = file_data.after or ""
  return before == after or (before == "" and after == "")
end

---Generate unified diff using vim.diff()
---@param file_path string Path to the file
---@param before string Original content
---@param after string New content
---@param additions number Number of additions
---@param deletions number Number of deletions
---@return string[] lines Lines of unified diff output
local function generate_unified_diff(file_path, before, after, additions, deletions)
  local lines = {}

  -- Add diff header
  table.insert(lines, string.format("diff --git a/%s b/%s", file_path, file_path))

  -- Handle edge cases
  local is_new_file = before == "" or before == nil
  local is_deleted_file = after == "" or after == nil

  if is_new_file then
    table.insert(lines, "new file")
    table.insert(lines, "--- /dev/null")
    table.insert(lines, string.format("+++ b/%s", file_path))
  elseif is_deleted_file then
    table.insert(lines, "deleted file")
    table.insert(lines, string.format("--- a/%s", file_path))
    table.insert(lines, "+++ /dev/null")
  else
    table.insert(lines, string.format("--- a/%s", file_path))
    table.insert(lines, string.format("+++ b/%s", file_path))
  end

  -- Add change stats
  table.insert(lines, string.format("@@ +%d,-%d @@", additions or 0, deletions or 0))
  table.insert(lines, "")

  -- Generate unified diff using vim.diff()
  if not is_new_file and not is_deleted_file then
    local ok, diff_result = pcall(vim.diff, before, after, {
      result_type = "unified",
      algorithm = "histogram",
      ctxlen = 3,
      indent_heuristic = true,
    })

    if ok and diff_result and diff_result ~= "" then
      -- vim.diff returns a string, split it into lines
      for _, line in ipairs(vim.split(diff_result, "\n")) do
        table.insert(lines, line)
      end
    else
      -- Fallback: show simple line-by-line diff
      table.insert(lines, "--- Original")
      for _, line in ipairs(vim.split(before, "\n")) do
        table.insert(lines, "- " .. line)
      end
      table.insert(lines, "")
      table.insert(lines, "+++ Modified")
      for _, line in ipairs(vim.split(after, "\n")) do
        table.insert(lines, "+ " .. line)
      end
    end
  elseif is_new_file and after then
    -- New file: show all lines as additions
    for _, line in ipairs(vim.split(after, "\n")) do
      table.insert(lines, "+ " .. line)
    end
  elseif is_deleted_file and before then
    -- Deleted file: show all lines as deletions
    for _, line in ipairs(vim.split(before, "\n")) do
      table.insert(lines, "- " .. line)
    end
  end

  return lines
end

---Show diff review for an assistant message
---@param message table Message info from message.updated event
---@param opts opencode.events.session_diff.Opts
function M.show_message_diff(message, opts)
  -- Extract diffs from message.summary.diffs
  local diffs = message.summary and message.summary.diffs or {}

  if #diffs == 0 then
    return -- No diffs to show
  end

  -- Filter out empty diffs
  local files_with_changes = {}
  for _, file_data in ipairs(diffs) do
    if not is_diff_empty(file_data) then
      table.insert(files_with_changes, {
        file = file_data.file,
        before = file_data.before,
        after = file_data.after,
        additions = file_data.additions,
        deletions = file_data.deletions,
      })
    end
  end

  -- Only show review if we have non-empty files
  if #files_with_changes == 0 then
    return
  end

  M.state.session_diff = {
    session_id = message.sessionID,
    message_id = message.id,
    files = files_with_changes,
    current_index = 1,
  }

  M.show_review(opts)
end

---Revert a single file to its original state using 'before' content
---@param file_data table File diff data with 'before' content
function M.revert_file(file_data)
  if not file_data.before then
    vim.notify(
      string.format("Cannot revert %s: no 'before' content available", file_data.file),
      vim.log.levels.WARN,
      { title = "opencode" }
    )
    return false
  end

  local lines = vim.split(file_data.before, "\n")
  local success = pcall(vim.fn.writefile, lines, file_data.file)

  if success then
    -- Reload the buffer if it's open
    local bufnr = vim.fn.bufnr(file_data.file)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("edit!")
      end)
    end
    return true
  else
    vim.notify(string.format("Failed to revert %s", file_data.file), vim.log.levels.ERROR, { title = "opencode" })
    return false
  end
end

---Accept all changes (close review UI)
function M.accept_all_changes()
  vim.notify("Accepted all changes", vim.log.levels.INFO, { title = "opencode" })
  M.cleanup_session_diff()
end

---Reject all changes (revert all files)
function M.reject_all_changes()
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  local reverted = 0
  for _, file_data in ipairs(diff_state.files) do
    if M.revert_file(file_data) then
      reverted = reverted + 1
    end
  end

  vim.notify(
    string.format("Reverted %d/%d files", reverted, #diff_state.files),
    vim.log.levels.INFO,
    { title = "opencode" }
  )
  M.cleanup_session_diff()
end

---Accept current file (mark as accepted, move to next)
---@param opts opencode.events.session_diff.Opts
function M.accept_current_file(opts)
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  local current_file = diff_state.files[diff_state.current_index]
  vim.notify(string.format("Accepted: %s", current_file.file), vim.log.levels.INFO, { title = "opencode" })

  -- Move to next file or close if done
  if diff_state.current_index < #diff_state.files then
    diff_state.current_index = diff_state.current_index + 1
    M.show_review(opts)
  else
    vim.notify("All files reviewed", vim.log.levels.INFO, { title = "opencode" })
    M.cleanup_session_diff()
  end
end

---Reject current file (revert it, move to next)
---@param opts opencode.events.session_diff.Opts
function M.reject_current_file(opts)
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  local current_file = diff_state.files[diff_state.current_index]
  M.revert_file(current_file)

  -- Move to next file or close if done
  if diff_state.current_index < #diff_state.files then
    diff_state.current_index = diff_state.current_index + 1
    M.show_review(opts)
  else
    vim.notify("All files reviewed", vim.log.levels.INFO, { title = "opencode" })
    M.cleanup_session_diff()
  end
end

---Navigate to next file
---@param opts opencode.events.session_diff.Opts
function M.next_file(opts)
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  if diff_state.current_index < #diff_state.files then
    diff_state.current_index = diff_state.current_index + 1
    M.show_review(opts)
  end
end

---Navigate to previous file
---@param opts opencode.events.session_diff.Opts
function M.prev_file(opts)
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  if diff_state.current_index > 1 then
    diff_state.current_index = diff_state.current_index - 1
    M.show_review(opts)
  end
end

---Clean up session diff state and UI
function M.cleanup_session_diff()
  if M.state.bufnr and vim.api.nvim_buf_is_valid(M.state.bufnr) then
    vim.api.nvim_buf_delete(M.state.bufnr, { force = true })
  end

  M.state.bufnr = nil
  M.state.winnr = nil
  M.state.tabnr = nil
  M.state.session_diff = nil
end

---Show session changes review UI
---@param opts opencode.events.session_diff.Opts
function M.show_review(opts)
  local diff_state = M.state.session_diff
  if not diff_state then
    return
  end

  local total_files = #diff_state.files
  local current_file = diff_state.files[diff_state.current_index]

  -- Reuse existing buffer if available, otherwise create new one
  local bufnr = M.state.bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = vim.api.nvim_create_buf(false, true)
    M.state.bufnr = bufnr

    -- Set buffer options
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "diff"
  end

  -- Build unified diff content
  local lines = {}
  table.insert(lines, string.format("=== OpenCode Changes Review [%d/%d] ===", diff_state.current_index, total_files))
  table.insert(lines, "")
  table.insert(lines, string.format("File: %s", current_file.file))
  table.insert(lines, string.format("Changes: +%d -%d", current_file.additions or 0, current_file.deletions or 0))
  table.insert(lines, "")

  -- Generate and insert unified diff
  local diff_lines = generate_unified_diff(
    current_file.file,
    current_file.before or "",
    current_file.after or "",
    current_file.additions,
    current_file.deletions
  )

  for _, line in ipairs(diff_lines) do
    table.insert(lines, line)
  end

  table.insert(lines, "")
  table.insert(lines, "=== Keybindings ===")
  table.insert(lines, "<n> next file  | <p> prev file")
  table.insert(lines, "<a> accept this file | <r> reject this file")
  table.insert(lines, "<A> accept all | <R> reject all")
  table.insert(lines, "<q> close review")

  -- Set buffer content
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  -- Handle window/tab display
  if opts.open_in_tab then
    -- Check if we have a tab already
    if M.state.tabnr and vim.api.nvim_tabpage_is_valid(M.state.tabnr) then
      -- Switch to the existing tab
      vim.api.nvim_set_current_tabpage(M.state.tabnr)
      -- Find the window in this tab showing our buffer
      local found_win = false
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(M.state.tabnr)) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
          vim.api.nvim_set_current_win(win)
          found_win = true
          break
        end
      end
      if not found_win then
        -- Create a new window in this tab
        vim.cmd("only")
        vim.api.nvim_win_set_buf(0, bufnr)
      end
    else
      -- Create a new tab
      vim.cmd("tabnew")
      M.state.tabnr = vim.api.nvim_get_current_tabpage()
      vim.api.nvim_win_set_buf(0, bufnr)
    end
  else
    -- Check if we have an existing window
    if M.state.winnr and vim.api.nvim_win_is_valid(M.state.winnr) then
      -- Reuse the existing window
      vim.api.nvim_set_current_win(M.state.winnr)
      vim.api.nvim_win_set_buf(M.state.winnr, bufnr)
    else
      -- Create a new split
      vim.cmd("vsplit")
      M.state.winnr = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(M.state.winnr, bufnr)
    end
  end

  -- Set up keybindings (need to wrap opts in closures)
  local keymap_opts = { buffer = bufnr, nowait = true, silent = true }

  vim.keymap.set("n", "n", function()
    M.next_file(opts)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Next file" }))
  vim.keymap.set("n", "p", function()
    M.prev_file(opts)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Previous file" }))
  vim.keymap.set("n", "a", function()
    M.accept_current_file(opts)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Accept this file" }))
  vim.keymap.set("n", "r", function()
    M.reject_current_file(opts)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Reject this file" }))
  vim.keymap.set("n", "A", M.accept_all_changes, vim.tbl_extend("force", keymap_opts, { desc = "Accept all" }))
  vim.keymap.set("n", "R", M.reject_all_changes, vim.tbl_extend("force", keymap_opts, { desc = "Reject all" }))
  vim.keymap.set("n", "q", M.cleanup_session_diff, vim.tbl_extend("force", keymap_opts, { desc = "Close review" }))

  vim.notify(
    string.format("Review [%d/%d]: %s", diff_state.current_index, total_files, current_file.file),
    vim.log.levels.INFO,
    { title = "opencode" }
  )
end

return M
