local M = {}
local server = require("opencode.server.websocket")

M.state = {
  last_selection = nil,
  enabled = false,
  debounce_timer = nil,
}

local function is_visual_mode(mode)
  return mode == "v" or mode == "V" or mode == "\22"
end

local function get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.api.nvim_get_mode().mode

  if not is_visual_mode(mode) then
    return nil
  end

  local anchor = vim.fn.getpos("v")
  local cursor = vim.api.nvim_win_get_cursor(0)

  if anchor[2] == 0 then
    return nil
  end

  local start_pos = { anchor[2], anchor[3] }
  local end_pos = { cursor[1], cursor[2] + 1 }
  if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
    start_pos, end_pos = end_pos, start_pos
  end

  local start_line = start_pos[1]
  local start_col = start_pos[2]
  local end_line = end_pos[1]
  local end_col = end_pos[2]

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    return nil
  end

  local text
  if mode == "V" then
    start_col = 1
    end_col = #(lines[#lines] or "")
    text = table.concat(lines, "\n")
  elseif start_line == end_line then
    text = string.sub(lines[1] or "", start_col, end_col)
  else
    lines[1] = string.sub(lines[1] or "", start_col)
    lines[#lines] = string.sub(lines[#lines] or "", 1, end_col)
    text = table.concat(lines, "\n")
  end

  return {
    start_line = start_line - 1,
    start_col = start_col - 1,
    end_line = end_line - 1,
    end_col = end_col,
    text = text,
    is_empty = #text == 0,
  }
end

local function get_cursor_position()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  return {
    start_line = line - 1,
    start_col = col,
    end_line = line - 1,
    end_col = col,
    text = "",
    is_empty = true,
  }
end

local function get_current_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if filepath == "" or not filepath:match("^/") then
    return nil
  end

  local mode = vim.api.nvim_get_mode().mode
  local selection

  if is_visual_mode(mode) then
    selection = get_visual_selection()
  else
    selection = get_cursor_position()
  end

  if not selection then
    return nil
  end

  return {
    file_path = filepath,
    selection = selection,
  }
end

local function selection_key(selection)
  if not selection then
    return ""
  end
  return string.format(
    "%s:%d:%d-%d:%d:%s",
    selection.file_path,
    selection.selection.start_line,
    selection.selection.start_col,
    selection.selection.end_line,
    selection.selection.end_col,
    selection.selection.text
  )
end

local function has_selection_changed(current)
  if not M.state.last_selection then
    return true
  end

  local last_key = selection_key(M.state.last_selection)
  local current_key = selection_key(current)

  return last_key ~= current_key
end

function M.update(force)
  if not server.is_running() then
    return
  end

  local current = get_current_selection()

  if current and (force or has_selection_changed(current)) then
    server.broadcast_selection_changed(current.file_path, current.selection)
    M.state.last_selection = current
  end
end

local function debounce_send_selection()
  if M.state.debounce_timer then
    M.state.debounce_timer:stop()
    M.state.debounce_timer:close()
    M.state.debounce_timer = nil
  end

  local timer = vim.uv.new_timer()
  if not timer then
    M.update()
    return
  end

  M.state.debounce_timer = timer
  timer:start(
    100,
    0,
    vim.schedule_wrap(function()
      if M.state.debounce_timer == timer then
        M.state.debounce_timer = nil
        timer:close()
        M.update()
      end
    end)
  )
end

local function on_cursor_moved()
  if not M.state.enabled then
    return
  end
  debounce_send_selection()
end

local function on_mode_changed()
  if not M.state.enabled then
    return
  end
  debounce_send_selection()
end

local function on_buf_enter()
  if not M.state.enabled then
    return
  end
  debounce_send_selection()
end

local function on_text_changed()
  if not M.state.enabled then
    return
  end
  debounce_send_selection()
end

function M.enable()
  if M.state.enabled then
    return
  end

  M.state.enabled = true

  local group = vim.api.nvim_create_augroup("OpenCodeLiveContext", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = on_cursor_moved,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = on_mode_changed,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = on_buf_enter,
  })

  vim.api.nvim_create_autocmd("TextChanged", {
    group = group,
    callback = on_text_changed,
  })

  M.update()
end

function M.disable()
  if not M.state.enabled then
    return
  end

  M.state.enabled = false
  vim.api.nvim_del_augroup_by_name("OpenCodeLiveContext")

  if M.state.debounce_timer then
    M.state.debounce_timer:stop()
    M.state.debounce_timer:close()
    M.state.debounce_timer = nil
  end

  M.state.last_selection = nil
end

function M.is_enabled()
  return M.state.enabled
end

function M.send_at_mention(file_path, line_start, line_end)
  if not server.is_running() then
    return false, "Live context is not running"
  end

  if not server.broadcast_at_mentioned(file_path, line_start, line_end) then
    return false, "OpenCode TUI is not connected"
  end

  return true, nil
end

function M.send_visual_selection_as_mention()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  if filepath == "" or not filepath:match("^/") then
    return false, "Current buffer is not a file"
  end

  local selection = get_visual_selection()
  if not selection then
    return false, "No visual selection to attach"
  end

  return M.send_at_mention(filepath, selection.start_line, selection.end_line)
end

function M.send_range_as_mention(line_start, line_end)
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" or not filepath:match("^/") then
    return false, "Current buffer is not a file"
  end

  return M.send_at_mention(filepath, line_start - 1, line_end - 1)
end

return M
