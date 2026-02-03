---@module 'snacks.picker'

---The context a prompt is being made in.
---Particularly useful when inputting or selecting a prompt
---because that changes the active mode, window, etc.
---So this stores state prior to that.
---@class opencode.Context
---@field win integer
---@field buf integer
---@field cursor integer[] The cursor positon. { row, col } (1,0-based).
---@field range? opencode.context.Range The operator range or visual selection range.
---@field agents? opencode.cli.client.Agent[] Subagents available in `opencode`.
local Context = {}
Context.__index = Context

local ns_id = vim.api.nvim_create_namespace("OpencodeContext")

local function is_buf_valid(buf)
  return vim.api.nvim_get_option_value("buftype", { buf = buf }) == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function last_used_valid_win()
  local last_used_win = 0
  local latest_last_used = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_buf_valid(buf) then
      local last_used = vim.fn.getbufinfo(buf)[1].lastused or 0
      if last_used > latest_last_used then
        latest_last_used = last_used
        last_used_win = win
      end
    end
  end
  return last_used_win
end

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

  return {
    from = { from[1], from[2] },
    to = { to[1], to[2] },
    kind = kind,
  }
end

---@param buf integer
---@param range opencode.context.Range
local function highlight(buf, range)
  local end_row = range.to[1] - (range.kind == "line" and 0 or 1)
  local end_col = nil
  if range.kind ~= "line" then
    local line = vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1] or ""
    end_col = math.min(range.to[2] + 1, #line)
  end
  vim.api.nvim_buf_set_extmark(buf, ns_id, range.from[1] - 1, range.from[2], {
    end_row = end_row,
    end_col = end_col,
    hl_group = "Visual",
  })
end

---@param range? opencode.context.Range The range of the operator or visual selection. Defaults to current visual selection, if any.
function Context.new(range)
  local self = setmetatable({}, Context)
  self.win = last_used_valid_win()
  self.buf = vim.api.nvim_win_get_buf(self.win)
  self.cursor = vim.api.nvim_win_get_cursor(self.win)
  self.range = range or selection(self.buf)
  if self.range then
    highlight(self.buf, self.range)
  end
  return self
end

function Context:clear()
  vim.api.nvim_buf_clear_namespace(self.buf, ns_id, 0, -1)
end

function Context:resume()
  self:clear()
  if self.range ~= nil then
    vim.cmd("normal! gv")
  end
end

---Render `opts.contexts` in `prompt`.
---@param prompt string
---@return { input: snacks.picker.Text[], output: snacks.picker.Text[] }
function Context:render(prompt)
  local contexts = require("opencode.config").opts.contexts or {}
  local agents = self.agents or {}
  local context_placeholders = vim.tbl_keys(contexts)
  table.sort(context_placeholders, function(a, b)
    return #a > #b -- longest first, in case some overlap
  end)

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
  for _, agent in ipairs(agents) do
    local agent_placeholder = "@" .. agent.name
    placeholders[agent_placeholder] = {
      input = function()
        return { agent_placeholder, "OpencodeAgent" }
      end,
      output = function()
        return { agent_placeholder, "OpencodeAgent" }
      end,
    }
  end

  local input, output = {}, {}
  local i = 1
  while i <= #prompt do
    -- Find the next placeholder and its position
    local next_pos, next_placeholder = #prompt + 1, nil
    for placeholder in pairs(placeholders) do
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

---Format a location for `opencode`.
---e.g. `@opencode.lua L21:C10-L65:C11`
---@param args { buf?: integer, path?: string, start_line?: integer, start_col?: integer, end_line?: integer, end_col?: integer }
function Context.format(args)
  local result = ""
  if (args.buf and is_buf_valid(args.buf)) or args.path then
    local rel_path = vim.fn.fnamemodify(args.path or vim.api.nvim_buf_get_name(args.buf), ":.")
    -- Must be preceeded by @ and followed by space for `opencode` to parse as a file reference
    -- TODO: Actually it regressed and doesn't do that anymore.
    -- And in the meantime, the prefixed `@` seems to confuse it.
    result = rel_path .. " "
  end
  if args.start_line and args.end_line and args.start_line > args.end_line then
    args.start_line, args.end_line = args.end_line, args.start_line
    if args.start_col and args.end_col then
      args.start_col, args.end_col = args.end_col, args.start_col
    end
  end
  if args.start_line then
    result = result .. string.format("L%d", args.start_line)
    if args.start_col then
      result = result .. string.format(":C%d", args.start_col)
    end
    if args.end_line then
      result = result .. string.format("-L%d", args.end_line)
      if args.end_col then
        result = result .. string.format(":C%d", args.end_col)
      end
    end
  end
  return result
end

-- TODO: May be a better organization for these built-in `context.Fn`'s

---Range if present, else cursor position.
function Context:this()
  if self.range then
    return Context.format({
      buf = self.buf,
      start_line = self.range.from[1],
      start_col = (self.range.kind ~= "line") and self.range.from[2] or nil,
      end_line = self.range.to[1],
      end_col = (self.range.kind ~= "line") and self.range.to[2] or nil,
    })
  else
    return Context.format({
      buf = self.buf,
      start_line = self.cursor[1],
      start_col = self.cursor[2] + 1,
    })
  end
end

---The current buffer.
function Context:buffer()
  return Context.format({
    buf = self.buf,
  })
end

---All open buffers.
function Context:buffers()
  local file_list = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local path = Context.format({ buf = buf })
    if path then
      table.insert(file_list, path)
    end
  end
  if #file_list == 0 then
    return nil
  end
  return table.concat(file_list, " ")
end

---The visible lines in all open windows.
function Context:visible_text()
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if is_buf_valid(buf) then
      local start_line = vim.fn.line("w0", win)
      local end_line = vim.fn.line("w$", win)
      table.insert(
        visible,
        Context.format({
          buf = buf,
          start_line = start_line,
          end_line = end_line,
        })
      )
    end
  end
  if #visible == 0 then
    return nil
  end
  return table.concat(visible, " ")
end

---Diagnostics for the current buffer.
function Context:diagnostics()
  local diagnostics = vim.diagnostic.get(self.buf)
  if #diagnostics == 0 then
    return nil
  end

  local file_ref = Context.format({ buf = self.buf })

  local diagnostic_strings = {}
  for _, diagnostic in ipairs(diagnostics) do
    local location = Context.format({
      start_line = diagnostic.lnum + 1,
      start_col = diagnostic.col + 1,
      end_line = diagnostic.end_lnum + 1,
      end_col = diagnostic.end_col + 1,
    })

    table.insert(
      diagnostic_strings,
      string.format(
        "- %s (%s): %s",
        location,
        diagnostic.source or "unknown source",
        diagnostic.message:gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
      )
    )
  end

  return #diagnostics .. " diagnostics in " .. file_ref .. "\n" .. table.concat(diagnostic_strings, "\n")
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
        Context.format({
          buf = entry.bufnr,
          start_line = entry.lnum,
          start_col = entry.col,
        })
      )
    end
  end
  return table.concat(lines, " ")
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
        Context.format({
          buf = mark.pos[1],
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
    table.insert(paths, Context.format({ path = tag.path }))
  end
  return table.concat(paths, " ")
end

return Context
