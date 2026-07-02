---The context a prompt is being made in.
---Particularly useful when inputting or selecting a prompt, which changes the active mode, window, etc.
---So this stores state prior to that.
---@class opencode.context.Context
---@field buf integer
---@field win integer
---@field cursor integer[] The cursor positon. { row, col } (1,0-based).
---@field server opencode.server.Server The OpenCode server we're communicating with.
---@field range? opencode.context.Range The operator range or visual selection range.
local Context = {}
Context.__index = Context

---@class opencode.context.Range
---@field from integer[] { line, col } (1,0-based)
---@field to integer[] { line, col } (1,0-based)
---@field kind "char" | "line" | "block"

local NS_ID = vim.api.nvim_create_namespace("OpencodeContext")

---@param buf integer
---@return opencode.context.Range?
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
---@type opencode.context.Context?
Context.current = nil

---@param server opencode.server.Server
---@param range? opencode.context.Range The range of the operator or visual selection. Defaults to current visual selection, if any.
function Context.new(server, range)
  local self = setmetatable({}, Context)
  self.win = vim.api.nvim_get_current_win()
  self.buf = vim.api.nvim_win_get_buf(self.win)
  self.cursor = vim.api.nvim_win_get_cursor(self.win)
  self.server = server
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

---Render `vim.g.opencode_opts.contexts` in `prompt`.
---@param prompt string
---@return { input: opencode.context.rendered.Rendered, output: opencode.context.rendered.Rendered }
function Context:render(prompt)
  local contexts = require("opencode.config").opts.contexts or {}

  local context_placeholders = vim.tbl_keys(contexts)
  local agent_placeholders = vim.tbl_map(function(agent)
    return "@" .. agent.name
  end, self.server.subagents)

  ---@type table<string, { input: (fun(): opencode.context.rendered.Text), output: (fun(): opencode.context.rendered.Text) }>
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

  local Rendered = require("opencode.context.rendered")

  return {
    input = setmetatable(input, Rendered),
    output = setmetatable(output, Rendered),
  }
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

---Format a location for OpenCode.
---
---@param opts { path?: string, buf?: integer, from?: integer[], to?: integer[], rel?: string } One of `path` or `buf` is required. `from` and `to` are 1-based `{ line, col? }` tuples. `rel` is an optional path to format relative to, otherwise absolute.
---@return string? formatted Location if backed by a file (e.g. `opencode.lua:L21:C10-L65:C11`) so OpenCode can gather context, else literal text of the range or buffer. `nil` if invalid file or buffer.
function Context.format(opts)
  assert(opts.path or opts.buf, "One of `opts.path` or `opts.buf` is required.")
  local filepath = opts.path or (opts.buf and vim.api.nvim_buf_get_name(opts.buf)) or nil
  if not filepath or filepath == "" then
    return nil
  end

  local from = opts.from
  local to = opts.to
  local start_line = from and from[1]
  local start_col = from and from[2]
  local end_line = to and to[1]
  local end_col = to and to[2]

  -- Normalize start/end (for reversed visual selections)
  if start_line and end_line and start_line > end_line then
    start_line, end_line = end_line, start_line
    if start_col and end_col then
      start_col, end_col = end_col, start_col
    end
  end

  -- For buffers not backed by a real file, return inline text
  if opts.buf then
    local filestat = vim.uv.fs_stat(filepath)
    if not filestat or filestat.type ~= "file" then
      return get_buffer_range_text(
        opts.buf,
        start_line or 1,
        start_col,
        end_line or vim.api.nvim_buf_line_count(opts.buf),
        end_col
      )
    end
  end

  local result = vim.fn.fnamemodify(filepath, ":p")
  if opts.rel then
    local prefix = opts.rel:match("/$") and opts.rel or opts.rel .. "/"
    if result:find(prefix, 1, true) == 1 then
      result = result:sub(#prefix + 1)
    end
  end
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

return Context
