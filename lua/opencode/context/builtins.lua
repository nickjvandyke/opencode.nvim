local M = {}

---Range if present, else cursor position.
---@param context opencode.context.Context
function M.this(context)
  if context.range then
    local from = { context.range.from[1] }
    local to = { context.range.to[1] }
    if context.range.kind ~= "line" then
      from[2] = context.range.from[2] + 1
      to[2] = context.range.to[2] + 1
    end
    return context.format({ buf = context.buf, from = from, to = to, rel = context.server.cwd })
  else
    return context.format({
      buf = context.buf,
      from = { context.cursor[1], context.cursor[2] + 1 },
      rel = context.server.cwd,
    })
  end
end

---The buffer.
---@param context opencode.context.Context
function M.buffer(context)
  return context.format({ buf = context.buf, rel = context.server.cwd })
end

---All open buffers.
---@param context opencode.context.Context
function M.buffers(context)
  local file_list = {}
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local path = context.format({ buf = buf.bufnr, rel = context.server.cwd })
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
---@param context opencode.context.Context
function M.visible_text(context)
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local location = context.format({
      buf = buf,
      from = { vim.fn.line("w0", win) },
      to = { vim.fn.line("w$", win) },
      rel = context.server.cwd,
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

  ---@param diagnostic vim.Diagnostic
  ---@return string
  local function format_diagnostic(diagnostic)
    local location = context.format({
      buf = diagnostic.bufnr,
      from = { diagnostic.lnum + 1, diagnostic.col + 1 },
      to = { diagnostic.end_lnum + 1, diagnostic.end_col + 1 },
      rel = context and context.server.cwd,
    })

    return string.format(
      "%s (%s): %s",
      location,
      diagnostic.source or "unknown",
      vim.trim(diagnostic.message:gsub("%s+", " "))
    )
  end

  local diagnostic_strings = vim.tbl_map(function(diagnostic)
    return "- " .. format_diagnostic(diagnostic)
  end, diagnostics)

  return #diagnostics .. " diagnostic(s):" .. "\n" .. table.concat(diagnostic_strings, "\n")
end

---Formatted quickfix list entries.
---@param context opencode.context.Context
function M.quickfix(context)
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
        context.format({ buf = entry.bufnr, from = { entry.lnum, entry.col }, rel = context.server.cwd })
      )
    end
  end
  return table.concat(lines, ", ")
end

---Global marks.
---@param context opencode.context.Context
function M.marks(context)
  local marks = {}
  for _, mark in ipairs(vim.fn.getmarklist()) do
    if mark.mark:match("^'[A-Z]$") then
      table.insert(
        marks,
        context.format({ buf = mark.pos[1], from = { mark.pos[2], mark.pos[3] }, rel = context.server.cwd })
      )
    end
  end
  if #marks == 0 then
    return nil
  end
  return table.concat(marks, ", ")
end

return M
