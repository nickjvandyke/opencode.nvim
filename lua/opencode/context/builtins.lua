local M = {}

---Range if present, else cursor position.
---@param context opencode.context.Context
function M.this(context)
  if context.range then
    return require("opencode.context").format(context.buf, {
      start_line = context.range.from[1],
      start_col = (context.range.kind ~= "line") and context.range.from[2] or nil,
      end_line = (context.range.kind ~= "line" or context.range.from[1] ~= context.range.to[1]) and context.range.to[1]
        or nil,
      end_col = (context.range.kind ~= "line") and context.range.to[2] or nil,
    })
  else
    return require("opencode.context").format(context.buf, {
      start_line = context.cursor[1],
      start_col = context.cursor[2] + 1,
    })
  end
end

---The buffer.
---@param context opencode.context.Context
function M.buffer(context)
  return require("opencode.context").format(context.buf)
end

---All open buffers.
function M.buffers()
  local file_list = {}
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local path = require("opencode.context").format(buf.bufnr)
    if path then
      table.insert(file_list, path)
    end
  end
  if #file_list == 0 then
    return nil
  end
  return table.concat(file_list, ", ")
end

---The visible lines in all open windows.
function M.visible_text()
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local location = require("opencode.context").format(buf, {
      start_line = vim.fn.line("w0", win),
      end_line = vim.fn.line("w$", win),
    })
    if location then
      table.insert(visible, location)
    end
  end
  if #visible == 0 then
    return nil
  end
  return table.concat(visible, ", ")
end

---@param diagnostic vim.Diagnostic
---@return string
function M.format_diagnostic(diagnostic)
  local location = require("opencode.context").format(diagnostic.bufnr, {
    start_line = diagnostic.lnum + 1,
    start_col = diagnostic.col + 1,
    end_line = diagnostic.end_lnum + 1,
    end_col = diagnostic.end_col + 1,
  })

  return string.format(
    "%s (%s): %s",
    location,
    diagnostic.source or "unknown",
    vim.trim(diagnostic.message:gsub("%s+", " "))
  )
end

---Diagnostics for the buffer, or overlapping the range if present.
---@param context opencode.context.Context
function M.diagnostics(context)
  local diagnostics = vim.diagnostic.get(context.buf)

  if context.range then
    local from_line = context.range.from[1] - 1
    local to_line = context.range.to[1] - 1
    local from_col = context.range.from[2]
    local to_col = context.range.to[2]

    diagnostics = vim.tbl_filter(function(d)
      if d.lnum > to_line or d.end_lnum < from_line then
        return false
      end

      local oline = math.max(d.lnum, from_line)
      local oend = math.min(d.end_lnum, to_line)
      if oline == oend then
        local dc1 = (oline == d.lnum) and d.col or 0
        local dc2 = (oline == d.end_lnum) and d.end_col or math.huge
        local sc1 = (oline == from_line) and from_col or 0
        local sc2 = (oline == to_line) and to_col or math.huge
        return dc1 <= sc2 and dc2 >= sc1
      end

      return true
    end, diagnostics)
  end

  if #diagnostics == 0 then
    return nil
  end

  local diagnostic_strings = vim.tbl_map(function(diagnostic)
    return "- " .. M.format_diagnostic(diagnostic)
  end, diagnostics)

  return #diagnostics .. " diagnostic(s):" .. "\n" .. table.concat(diagnostic_strings, "\n")
end

---Formatted quickfix list entries.
function M.quickfix()
  local qflist = vim.fn.getqflist()
  if #qflist == 0 then
    return nil
  end
  local lines = {}
  for _, entry in ipairs(qflist) do
    local has_buf = entry.bufnr ~= 0 and vim.api.nvim_buf_get_name(entry.bufnr) ~= ""
    if has_buf then
      table.insert(
        lines,
        require("opencode.context").format(entry.bufnr, {
          start_line = entry.lnum,
          start_col = entry.col,
        })
      )
    end
  end
  return table.concat(lines, ", ")
end

---The git diff (unified diff format).
function M.git_diff()
  local result = vim.system({ "git", "--no-pager", "diff" }, { text = true }):wait()
  if result.code == 129 then
    return nil
  end
  require("opencode.util").check_system_call(result, "git diff")
  if result.stdout == "" then
    return nil
  end
  return result.stdout
end

---Global marks.
function M.marks()
  local marks = {}
  for _, mark in ipairs(vim.fn.getmarklist()) do
    if mark.mark:match("^'[A-Z]$") then
      table.insert(
        marks,
        require("opencode.context").format(mark.pos[1], {
          start_line = mark.pos[2],
          start_col = mark.pos[3],
        })
      )
    end
  end
  if #marks == 0 then
    return nil
  end
  return table.concat(marks, ", ")
end

return M
