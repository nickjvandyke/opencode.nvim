---@module 'snacks.picker'

local NS_ID = vim.api.nvim_create_namespace("OpencodeContext")

---The context a prompt is being made in.
---Particularly useful when inputting or selecting a prompt
---because that changes the active mode, window, etc.
---So this stores state prior to that.
---@class opencode.Context
---@field win integer
---@field buf integer
---@field cursor integer[] The cursor positon. { row, col } (1,0-based).
---@field range? opencode.context.Range The operator range or visual selection range.
local Context = {}
Context.__index = Context

---@class opencode.context.Range
---@field from integer[] { line, col } (1,0-based)
---@field to integer[] { line, col } (1,0-based)
---@field kind "char"|"line"|"block"

---@param buf integer
---@return opencode.context.Range|nil
local function selection(buf)
  local mode = vim.fn.mode()
  local kind = (mode == "V" and "line") or (mode == "v" and "char") or (mode == "\22" and "block")
  if not kind then
    return nil
  end

  -- Exit visual mode for consistent marks
  if vim.fn.mode():match("[vV\22]") then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", true)
  end

  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  if kind == "block" and from[2] > to[2] then
    from[2], to[2] = to[2], from[2]
  end

  return {
    from = { from[1], from[2] },
    to = { to[1], to[2] },
    kind = kind,
  }
end

---@param buf integer
---@param range opencode.context.Range
local function highlight(buf, range)
  local from_row = range.from[1] - 1
  local from_col = range.from[2]

  if range.kind == "block" then
    local start_row = range.from[1] - 1
    local end_row = range.to[1] - 1
    local start_col = range.from[2]
    local end_col = range.to[2]
    for row = start_row, end_row do
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
      local clamp_col = math.min(end_col + 1, #line)
      if clamp_col > start_col then
        vim.api.nvim_buf_set_extmark(buf, NS_ID, row, start_col, {
          end_col = clamp_col,
          hl_group = "Visual",
        })
      end
    end
  else
    local end_row = range.kind ~= "line" and range.to[1] - 1 or range.to[1]
    local end_col = nil
    if range.kind ~= "line" then
      local line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""
      end_col = math.min(range.to[2] + 1, #line)
    end
    vim.api.nvim_buf_set_extmark(buf, NS_ID, from_row, from_col, {
      end_row = end_row,
      end_col = end_col,
      hl_group = "Visual",
    })
  end
end

---The currently active context.
---Stored globally so the LSP can access it to render contexts in completions.
---@type opencode.Context?
Context.current = nil

---@param range? opencode.context.Range The range of the operator or visual selection. Defaults to current visual selection, if any.
function Context.new(range)
  local self = setmetatable({}, Context)
  self.win = vim.api.nvim_get_current_win()
  self.buf = vim.api.nvim_get_current_buf()
  self.cursor = vim.api.nvim_win_get_cursor(self.win)
  self.range = range or selection(self.buf)

  Context.current = self

  if self.range then
    highlight(self.buf, self.range)
  end

  return self
end

function Context:clear()
  vim.api.nvim_buf_clear_namespace(self.buf, NS_ID, 0, -1)
end

function Context:resume()
  self:clear()
  if self.range ~= nil then
    vim.cmd("normal! gv")
  end
end

---Render `opts.contexts` in `prompt`.
---@param prompt string
---@param agents opencode.server.Agent[]
---@return { input: snacks.picker.Text[], output: snacks.picker.Text[] }
function Context:render(prompt, agents)
  local contexts = require("opencode.config").opts.contexts or {}

  local context_placeholders = vim.tbl_keys(contexts)
  local agent_placeholders = vim.tbl_map(function(agent)
    return "@" .. agent.name
  end, agents)

  ---@type table<string, { input: (fun(): snacks.picker.Text), output: (fun(): snacks.picker.Text) }>
  local placeholders = {}
  for _, context_placeholder in ipairs(context_placeholders) do
    placeholders[context_placeholder] = {
      input = function()
        return { context_placeholder, "OpencodeContextPlaceholder" }
      end,
      output = function()
        local value = contexts[context_placeholder](self)
        if value then
          return { value, "OpencodeContextValue" }
        else
          return { context_placeholder, "OpencodeContextPlaceholder" }
        end
      end,
    }
  end
  for _, agent_placeholder in ipairs(agent_placeholders) do
    placeholders[agent_placeholder] = {
      input = function()
        return { agent_placeholder, "OpencodeAgent" }
      end,
      output = function()
        return { agent_placeholder, "OpencodeAgent" }
      end,
    }
  end

  -- Extract placeholders to an integer-indexed array and sort by length descending
  -- so longer placeholders are matched first, in case of overlaps (e.g. `@buffer` and `@buffers`).
  local placeholder_keys = vim.tbl_keys(placeholders)
  table.sort(placeholder_keys, function(a, b)
    return #a > #b
  end)

  local input, output = {}, {}
  local i = 1
  while i <= #prompt do
    -- Find the next placeholder and its position
    local next_pos, next_placeholder = #prompt + 1, nil
    for _, placeholder in ipairs(placeholder_keys) do
      local pos = prompt:find(placeholder, i, true)
      if pos and pos < next_pos then
        next_pos = pos
        next_placeholder = placeholder
      end
    end

    -- Add plain text before the next placeholder
    local text = prompt:sub(i, next_pos - 1)
    if #text > 0 then
      table.insert(input, { text })
      table.insert(output, { text })
    end

    -- If a placeholder is found, replace it with its value
    if next_placeholder then
      table.insert(input, placeholders[next_placeholder].input())
      table.insert(output, placeholders[next_placeholder].output())
      i = next_pos + #next_placeholder
    else
      -- No more placeholders, break
      break
    end
  end

  return {
    input = input,
    output = output,
  }
end

---Convert rendered context to plaintext.
---@param rendered snacks.picker.Text[]
---@return string
function Context.plaintext(rendered)
  return table.concat(vim.tbl_map(
    ---@param part snacks.picker.Text
    function(part)
      return part[1]
    end,
    rendered
  ))
end

---Convert rendered context to extmarks.
---Handles multiline parts.
---@param rendered snacks.picker.Text[]
---@return snacks.picker.Extmark[]
function Context.extmarks(rendered)
  local row = 1
  local col = 1
  local extmarks = {}
  for _, part in ipairs(rendered) do
    local part_text = part[1]
    local part_hl = part[2] or nil
    local segments = vim.split(part_text, "\n", { plain = true })
    for i, segment in ipairs(segments) do
      if i > 1 then
        row = row + 1
        col = 1
      end
      ---@type snacks.picker.Extmark
      if part_hl then
        local extmark = {
          row = row,
          col = col - 1,
          end_col = col + #segment - 1,
          hl_group = part_hl,
        }
        table.insert(extmarks, extmark)
      end
      col = col + #segment
    end
  end
  return extmarks
end

---Transforms to `:help input()-highlight` format.
---@param rendered snacks.picker.Text[]
---return { [1]: integer, [2]: integer, [3]: string }[]
function Context.input_highlight(rendered)
  return vim.tbl_map(function(extmark)
    return { extmark.col, extmark.end_col, extmark.hl_group }
  end, Context.extmarks(rendered))
end

---Get the literal text of a buffer range, trimmed to columns.
---@param bufnr integer
---@param start_line integer 1-indexed
---@param start_col? integer 1-indexed
---@param end_line integer 1-indexed
---@param end_col? integer 1-indexed
---@return string
local function get_buffer_range_text(bufnr, start_line, start_col, end_line, end_col)
  end_line = end_line or start_line
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  if #lines == 0 then
    return ""
  end
  if start_col then
    lines[1] = lines[1]:sub(start_col)
  end
  if end_col then
    lines[#lines] = lines[#lines]:sub(1, end_col)
  end
  return table.concat(lines, "\n")
end

---Format a location for `opencode`.
---e.g. `opencode.lua:L21:C10-L65:C11` when backed by a file.
---When not backed by a file it returns the literal text of the range (if present) or the entire buffer.
---@param loc string|integer A buffer number or filepath.
---@param args? { start_line?: integer, start_col?: integer, end_line?: integer, end_col?: integer } 1-based
---@return string?
function Context.format(loc, args)
  local filepath = (type(loc) == "string" and loc) or (type(loc) == "number" and vim.api.nvim_buf_get_name(loc)) or nil
  if not filepath or filepath == "" then
    return nil
  end

  local start_line = args and args.start_line
  local start_col = args and args.start_col
  local end_line = args and args.end_line
  local end_col = args and args.end_col

  -- Normalize start/end (for reversed visual selections)
  if start_line and end_line and start_line > end_line then
    start_line, end_line = end_line, start_line
    if start_col and end_col then
      start_col, end_col = end_col, start_col
    end
  end

  -- For buffers not backed by a real file, return inline text
  if type(loc) == "number" then
    local filestat = vim.uv.fs_stat(filepath)
    if not filestat or filestat.type ~= "file" then
      return get_buffer_range_text(
        loc,
        start_line or 1,
        start_col,
        end_line or vim.api.nvim_buf_line_count(loc),
        end_col
      )
    end
  end

  local result = vim.fn.fnamemodify(filepath, ":p")
  if start_line then
    result = result .. ":" .. string.format("L%d", start_line)
    if start_col then
      result = result .. string.format(":C%d", start_col)
    end
    if end_line then
      result = result .. string.format("-L%d", end_line)
      if end_col then
        result = result .. string.format(":C%d", end_col)
      end
    end
  end

  return result
end

-- TODO: May be a better organization for these built-in `context.Fn`'s

---Range if present, else cursor position.
function Context:this()
  if self.range then
    return Context.format(self.buf, {
      start_line = self.range.from[1],
      start_col = (self.range.kind ~= "line") and self.range.from[2] or nil,
      end_line = (self.range.kind ~= "line" or self.range.from[1] ~= self.range.to[1]) and self.range.to[1] or nil,
      end_col = (self.range.kind ~= "line") and self.range.to[2] or nil,
    })
  else
    return Context.format(self.buf, {
      start_line = self.cursor[1],
      start_col = self.cursor[2] + 1,
    })
  end
end

---The current buffer.
function Context:buffer()
  return Context.format(self.buf)
end

---All open buffers.
function Context:buffers()
  local file_list = {}
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local path = Context.format(buf.bufnr)
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
function Context:visible_text()
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local location = Context.format(buf, {
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
function Context.format_diagnostic(diagnostic)
  local location = Context.format(diagnostic.bufnr, {
    start_line = diagnostic.lnum + 1,
    start_col = diagnostic.col + 1,
    end_line = diagnostic.end_lnum + 1,
    end_col = diagnostic.end_col + 1,
  })

  return string.format(
    "%s (%s): %s",
    location,
    diagnostic.source or "unknown source",
    diagnostic.message:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
  )
end

---Diagnostics for the current buffer.
function Context:diagnostics()
  local diagnostics = vim.diagnostic.get(self.buf)
  if #diagnostics == 0 then
    return nil
  end

  local diagnostic_strings = vim.tbl_map(function(diagnostic)
    return "- " .. Context.format_diagnostic(diagnostic)
  end, diagnostics)

  return #diagnostics .. " diagnostics:" .. "\n" .. table.concat(diagnostic_strings, "\n")
end

---Formatted quickfix list entries.
function Context:quickfix()
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
        Context.format(entry.bufnr, {
          start_line = entry.lnum,
          start_col = entry.col,
        })
      )
    end
  end
  return table.concat(lines, ", ")
end

---The git diff (unified diff format).
function Context:git_diff()
  local result = vim.system({ "git", "--no-pager", "diff" }, { text = true }):wait()
  if result.code == 129 then
    -- Not a git repository
    return nil
  end
  require("opencode.util").check_system_call(result, "git diff")
  if result.stdout == "" then
    return nil
  end
  return result.stdout
end

---Global marks.
function Context:marks()
  local marks = {}
  for _, mark in ipairs(vim.fn.getmarklist()) do
    if mark.mark:match("^'[A-Z]$") then
      table.insert(
        marks,
        Context.format(mark.pos[1], {
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

---[`grapple.nvim`](https://github.com/cbochs/grapple.nvim) tags.
function Context:grapple_tags()
  local is_available, grapple = pcall(require, "grapple")
  if not is_available then
    return nil
  end
  local tags = grapple.tags()
  if not tags or #tags == 0 then
    return nil
  end
  local paths = {}
  for _, tag in ipairs(tags) do
    table.insert(paths, Context.format(tag.path))
  end
  return table.concat(paths, ", ")
end

return Context
