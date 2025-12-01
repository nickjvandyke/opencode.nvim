local M = {}

---@class opencode.events.session_diff.Opts
---
---Whether to enable the ability to review diff after the agent finishes responding
---@field enabled boolean
---
---Whether to use enhanced diff view with vim diff-mode (side-by-side)
---@field use_enhanced_diff? boolean
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

---Open changes in enhanced diff view using vim's diff-mode
---@param session_diff table Session diff data with files
function M.open_enhanced_diff(session_diff)
  -- If we already have an active diff view, close it first
  if M.state.enhanced_diff_tab and vim.api.nvim_tabpage_is_valid(M.state.enhanced_diff_tab) then
    M.cleanup_enhanced_diff()
  end

  -- Write before content to temp files for each changed file
  local temp_dir = vim.fn.tempname() .. "_opencode_diff"
  vim.fn.mkdir(temp_dir, "p")

  local file_entries = {}

  for _, file_data in ipairs(session_diff.files) do
    -- Write before content to temp file
    local temp_before = temp_dir .. "/" .. vim.fn.fnamemodify(file_data.file, ":t") .. ".before"
    vim.fn.writefile(vim.split(file_data.before or "", "\n"), temp_before)

    -- Use actual file for after (it already has new content from OpenCode)
    local actual_file = file_data.file

    -- Store mapping for cleanup
    if not M.state.enhanced_diff_temp_files then
      M.state.enhanced_diff_temp_files = {}
    end
    table.insert(M.state.enhanced_diff_temp_files, temp_before)

    table.insert(file_entries, {
      path = file_data.file,
      oldpath = nil,
      status = "M",
      stats = {
        additions = file_data.additions or 0,
        deletions = file_data.deletions or 0,
      },
      temp_before = temp_before,
      actual_file = actual_file,
    })
  end

  -- Store session data for later use
  M.state.enhanced_diff_session = session_diff
  M.state.enhanced_diff_temp_dir = temp_dir
  M.state.enhanced_diff_files = file_entries
  M.state.enhanced_diff_current_index = 1
  M.state.enhanced_diff_panel_visible = false

  -- Open first file in diff mode
  if #file_entries > 0 then
    -- Create a new tab for the diff view
    vim.cmd("tabnew")
    M.state.enhanced_diff_tab = vim.api.nvim_get_current_tabpage()

    -- Show the first file
    M.enhanced_diff_show_file(1)

    -- Show file panel by default if multiple files
    if #file_entries > 1 then
      vim.defer_fn(function()
        M.enhanced_diff_show_panel()
      end, 100) -- Small delay to let diff view settle
    end

    -- Set up autocommand to cleanup on tab close
    vim.api.nvim_create_autocmd("TabClosed", {
      pattern = tostring(M.state.enhanced_diff_tab),
      callback = function()
        M.cleanup_enhanced_diff_silent()
      end,
      once = true,
      desc = "Cleanup OpenCode diff temp files on tab close",
    })
  end
end

---Navigate to next file in enhanced diff view
function M.enhanced_diff_next_file()
  if not M.state.enhanced_diff_files or not M.state.enhanced_diff_current_index then
    return
  end

  local current = M.state.enhanced_diff_current_index
  local total = #M.state.enhanced_diff_files

  if current < total then
    M.state.enhanced_diff_current_index = current + 1
    M.enhanced_diff_show_file(M.state.enhanced_diff_current_index)
  end
end

---Navigate to previous file in enhanced diff view
function M.enhanced_diff_prev_file()
  if not M.state.enhanced_diff_files or not M.state.enhanced_diff_current_index then
    return
  end

  local current = M.state.enhanced_diff_current_index

  if current > 1 then
    M.state.enhanced_diff_current_index = current - 1
    M.enhanced_diff_show_file(M.state.enhanced_diff_current_index)
  end
end

---Toggle the file panel visibility
function M.enhanced_diff_toggle_panel()
  if not M.state.enhanced_diff_files then
    return
  end

  if M.state.enhanced_diff_panel_visible then
    M.enhanced_diff_hide_panel()
  else
    M.enhanced_diff_show_panel()
  end
end

---Show the file panel with all changed files
function M.enhanced_diff_show_panel()
  if not M.state.enhanced_diff_files or M.state.enhanced_diff_panel_visible then
    return
  end

  -- Create panel buffer
  local panel_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[panel_buf].buftype = "nofile"
  vim.bo[panel_buf].bufhidden = "wipe"
  vim.bo[panel_buf].swapfile = false
  vim.bo[panel_buf].filetype = "opencode-diff-panel"
  vim.api.nvim_buf_set_name(panel_buf, "OpenCode Files")

  -- Build panel content
  local lines = {}
  table.insert(lines, "OpenCode Changed Files")
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "")

  for i, entry in ipairs(M.state.enhanced_diff_files) do
    local marker = (i == M.state.enhanced_diff_current_index) and "▶ " or "  "
    local stats = string.format("+%d -%d", entry.stats.additions, entry.stats.deletions)
    table.insert(lines, string.format("%s%d. %s %s", marker, i, vim.fn.fnamemodify(entry.path, ":t"), stats))
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "Keymaps:")
  table.insert(lines, "  <Enter>  Jump to file")
  table.insert(lines, "  <Tab>    Next file")
  table.insert(lines, "  <S-Tab>  Previous file")
  table.insert(lines, "  ]x       Next hunk")
  table.insert(lines, "  [x       Previous hunk")
  table.insert(lines, "  gp       Toggle panel")
  table.insert(lines, "  R        Revert file")
  table.insert(lines, "  q        Close diff")

  vim.bo[panel_buf].modifiable = true
  vim.api.nvim_buf_set_lines(panel_buf, 0, -1, false, lines)
  vim.bo[panel_buf].modifiable = false

  -- Calculate panel width as 20% of screen width (minimum 15 columns)
  local total_width = vim.o.columns
  local panel_width = math.max(15, math.floor(total_width * 0.2))

  -- Open panel in a left vertical split
  vim.cmd("topleft " .. panel_width .. "vsplit")
  local panel_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(panel_win, panel_buf)

  -- Panel window options
  vim.wo[panel_win].number = false
  vim.wo[panel_win].relativenumber = false
  vim.wo[panel_win].signcolumn = "no"
  vim.wo[panel_win].foldcolumn = "0"
  vim.wo[panel_win].cursorline = true

  -- Store panel state
  M.state.enhanced_diff_panel_buf = panel_buf
  M.state.enhanced_diff_panel_win = panel_win
  M.state.enhanced_diff_panel_visible = true

  -- Set up panel keybindings
  local keymap_opts = { buffer = panel_buf, nowait = true, silent = true }

  vim.keymap.set("n", "<CR>", function()
    M.enhanced_diff_panel_select()
  end, vim.tbl_extend("force", keymap_opts, { desc = "Jump to selected file" }))

  vim.keymap.set("n", "gp", function()
    M.enhanced_diff_hide_panel()
  end, vim.tbl_extend("force", keymap_opts, { desc = "Close file panel" }))

  vim.keymap.set("n", "q", function()
    M.cleanup_enhanced_diff()
  end, vim.tbl_extend("force", keymap_opts, { desc = "Close OpenCode diff" }))

  -- Move cursor back to diff windows
  vim.cmd("wincmd l")
end

---Hide the file panel
function M.enhanced_diff_hide_panel()
  if not M.state.enhanced_diff_panel_visible then
    return
  end

  if M.state.enhanced_diff_panel_win and vim.api.nvim_win_is_valid(M.state.enhanced_diff_panel_win) then
    vim.api.nvim_win_close(M.state.enhanced_diff_panel_win, true)
  end

  M.state.enhanced_diff_panel_buf = nil
  M.state.enhanced_diff_panel_win = nil
  M.state.enhanced_diff_panel_visible = false
end

---Jump to the file selected in the panel
function M.enhanced_diff_panel_select()
  if not M.state.enhanced_diff_panel_buf or not M.state.enhanced_diff_files then
    return
  end

  -- Get current line in panel
  local line = vim.api.nvim_win_get_cursor(0)[1]

  -- Lines 1-3 are header, files start at line 4
  local file_index = line - 3

  if file_index >= 1 and file_index <= #M.state.enhanced_diff_files then
    -- Hide panel before showing file
    M.enhanced_diff_hide_panel()
    M.state.enhanced_diff_current_index = file_index
    M.enhanced_diff_show_file(file_index)
  end
end

---Show a specific file in the diff view
---@param index number File index to show
function M.enhanced_diff_show_file(index)
  local file_entry = M.state.enhanced_diff_files[index]
  if not file_entry then
    return
  end

  -- Save panel state
  local panel_was_visible = M.state.enhanced_diff_panel_visible

  -- Hide panel temporarily
  if panel_was_visible then
    M.enhanced_diff_hide_panel()
  end

  -- Close all windows except panel in current tab
  vim.cmd("only")

  -- Create a scratch buffer for the "before" content
  local before_buf = vim.api.nvim_create_buf(false, true)
  local before_lines = vim.fn.readfile(file_entry.temp_before)
  vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, before_lines)
  vim.bo[before_buf].buftype = "nofile"
  vim.bo[before_buf].bufhidden = "wipe"
  vim.bo[before_buf].swapfile = false

  -- Set a unique buffer name
  local buf_name = string.format("opencode://before/%d/%s", index, vim.fn.fnamemodify(file_entry.path, ":t"))
  pcall(vim.api.nvim_buf_set_name, before_buf, buf_name)

  -- Detect filetype from the actual file
  local ft = vim.filetype.match({ filename = file_entry.actual_file }) or ""
  vim.bo[before_buf].filetype = ft

  -- Open the before buffer on the left
  vim.api.nvim_set_current_buf(before_buf)

  -- Open the actual file (after) on the right
  vim.cmd("rightbelow vertical diffsplit " .. vim.fn.fnameescape(file_entry.actual_file))

  -- Enable diff mode
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")

  -- Store window references
  M.state.enhanced_diff_left_win = vim.fn.win_getid(vim.fn.winnr("h"))
  M.state.enhanced_diff_right_win = vim.fn.win_getid()

  -- Set up keybindings for both diff windows
  local keymap_opts = { buffer = true, nowait = true, silent = true }

  for _, bufnr in ipairs({
    vim.api.nvim_win_get_buf(M.state.enhanced_diff_left_win),
    vim.api.nvim_win_get_buf(M.state.enhanced_diff_right_win),
  }) do
    vim.keymap.set(
      "n",
      "<Tab>",
      function()
        M.enhanced_diff_next_file()
      end,
      vim.tbl_extend("force", { buffer = bufnr, nowait = true, silent = true }, { desc = "Next file in OpenCode diff" })
    )

    vim.keymap.set(
      "n",
      "<S-Tab>",
      function()
        M.enhanced_diff_prev_file()
      end,
      vim.tbl_extend(
        "force",
        { buffer = bufnr, nowait = true, silent = true },
        { desc = "Previous file in OpenCode diff" }
      )
    )

    -- Hunk navigation with ]x and [x
    vim.keymap.set(
      "n",
      "]x",
      "]c",
      vim.tbl_extend("force", { buffer = bufnr, nowait = true, silent = true, remap = true }, { desc = "Next hunk" })
    )
    vim.keymap.set(
      "n",
      "[x",
      "[c",
      vim.tbl_extend(
        "force",
        { buffer = bufnr, nowait = true, silent = true, remap = true },
        { desc = "Previous hunk" }
      )
    )

    vim.keymap.set("n", "gp", function()
      M.enhanced_diff_toggle_panel()
    end, vim.tbl_extend("force", { buffer = bufnr, nowait = true, silent = true }, { desc = "Toggle file panel" }))

    vim.keymap.set("n", "q", function()
      M.cleanup_enhanced_diff()
    end, vim.tbl_extend("force", { buffer = bufnr, nowait = true, silent = true }, { desc = "Close OpenCode diff" }))

    vim.keymap.set("n", "R", function()
      M.enhanced_diff_revert_current()
    end, vim.tbl_extend("force", { buffer = bufnr, nowait = true, silent = true }, { desc = "Revert current file" }))
  end

  -- Restore panel if it was visible
  if panel_was_visible then
    M.enhanced_diff_show_panel()
  end

  vim.notify(
    string.format(
      "OpenCode Diff [%d/%d]: %s (]x/[x=hunks, gp=panel, Tab/S-Tab=files)",
      index,
      #M.state.enhanced_diff_files,
      vim.fn.fnamemodify(file_entry.path, ":t")
    ),
    vim.log.levels.INFO,
    { title = "opencode" }
  )
end

---Revert the current file being viewed
function M.enhanced_diff_revert_current()
  if not M.state.enhanced_diff_current_index or not M.state.enhanced_diff_session then
    return
  end

  local file_data = M.state.enhanced_diff_session.files[M.state.enhanced_diff_current_index]
  if file_data then
    M.revert_file(file_data)
    -- Refresh the diff view
    M.enhanced_diff_show_file(M.state.enhanced_diff_current_index)
  end
end

---Clean up enhanced diff temp files and state (silent version for autocmd)
function M.cleanup_enhanced_diff_silent()
  -- Hide panel if visible
  if M.state.enhanced_diff_panel_visible then
    M.enhanced_diff_hide_panel()
  end

  -- Clean up temp files
  if M.state.enhanced_diff_temp_dir and vim.fn.isdirectory(M.state.enhanced_diff_temp_dir) == 1 then
    vim.fn.delete(M.state.enhanced_diff_temp_dir, "rf")
  end

  -- Clear state
  M.state.enhanced_diff_files = nil
  M.state.enhanced_diff_current_index = nil
  M.state.enhanced_diff_session = nil
  M.state.enhanced_diff_temp_files = nil
  M.state.enhanced_diff_temp_dir = nil
  M.state.enhanced_diff_tab = nil
  M.state.enhanced_diff_panel_buf = nil
  M.state.enhanced_diff_panel_win = nil
  M.state.enhanced_diff_panel_visible = nil
  M.state.enhanced_diff_left_win = nil
  M.state.enhanced_diff_right_win = nil
end

---Clean up enhanced diff temp files and state
function M.cleanup_enhanced_diff()
  -- Close the diff tab
  if M.state.enhanced_diff_tab and vim.api.nvim_tabpage_is_valid(M.state.enhanced_diff_tab) then
    vim.api.nvim_set_current_tabpage(M.state.enhanced_diff_tab)
    vim.cmd("tabclose")
  end

  M.cleanup_enhanced_diff_silent()

  vim.notify("Closed OpenCode diff", vim.log.levels.INFO, { title = "opencode" })
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

  local session_diff = {
    session_id = message.sessionID,
    message_id = message.id,
    files = files_with_changes,
    current_index = 1,
  }

  -- Use enhanced diff view (side-by-side with vim diff-mode) if enabled
  if opts.use_enhanced_diff ~= false then
    M.open_enhanced_diff(session_diff)
    return
  end

  -- Fallback to basic unified diff view
  M.state.session_diff = session_diff
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
