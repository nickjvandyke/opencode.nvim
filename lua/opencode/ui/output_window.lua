local M = {}
M.namespace = vim.api.nvim_create_namespace("opencode_ui")

---Apply extmarks to a buffer
---@param buf integer Buffer ID
---@param extmarks table<number, OutputExtmark[]> Extmarks indexed by line
---@param line_offset? integer Line offset to apply to extmarks, defaults to 0
function M.set_extmarks(buf, extmarks, line_offset)
  if not extmarks or type(extmarks) ~= "table" then
    return
  end

  line_offset = line_offset or 0

  for line_idx, marks in pairs(extmarks) do
    for _, mark in ipairs(marks) do
      local actual_mark = type(mark) == "function" and mark() or mark
      local target_line = line_offset + line_idx --[[@as integer]]
      if actual_mark.end_row then
        actual_mark.end_row = actual_mark.end_row + line_offset
      end
      local start_col = actual_mark.start_col
      if actual_mark.start_col then
        actual_mark.start_col = nil ---@diagnostic disable-line: inject-field
      end
      ---@cast actual_mark vim.api.keyset.set_extmark
      pcall(vim.api.nvim_buf_set_extmark, buf, M.namespace, target_line, start_col or 0, actual_mark)
    end
  end
end

---Set the buffer contents
---@param buf integer Buffer ID
---@param lines string[] The lines to set
---@param start_line? integer The starting line to set, defaults to 0
---@param end_line? integer The last line to set, defaults to -1
function M.set_lines(buf, lines, start_line, end_line)
  start_line = start_line or 0
  end_line = end_line or -1

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, start_line, end_line, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

return M
