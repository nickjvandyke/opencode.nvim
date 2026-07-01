---Non-intrusive floating-window permission prompt for opencode.nvim.
---
---Replaces the built-in vim.ui.select permission prompt with a floating window
---that has selectable buttons. The window does NOT steal focus — you keep typing
---in your buffer. When ready, C-w w into it, use h/l to navigate options,
---Enter to confirm, Esc/q to hide.
---
---Edit permissions still show the normal diff UI (da/dr keymaps).
---
---Enable via `vim.g.opencode_opts = { events = { permissions = { floating = true } } }`.

local M = {}

-- ──────────────────────────────────────────────
-- State
-- ──────────────────────────────────────────────

---@type {server: opencode.server.Server, queue: {event: table, id: number}[], queue_index: integer, win: integer|nil, buf: integer, width: integer, visible: boolean}|nil
local state = nil

local OPTIONS = { "Once", "Always", "Reject" }

---@type integer
local selected = 1

local NS = vim.api.nvim_create_namespace("opencode_perm")

-- ──────────────────────────────────────────────
-- Layout helpers
-- ──────────────────────────────────────────────

---Wrap text into lines that fit within `max_width` (in display cells).
---`strcharpart` uses character positions (not bytes), so `n_chars` is a
---character count. `strdisplaywidth` accounts for wide/ambiguous characters.
---@param text string
---@param max_width integer
---@return string[]
local function wrap_text(text, max_width)
  if max_width < 1 then
    return { text }
  end

  local lines = {}
  local remaining = text
  while vim.fn.strdisplaywidth(remaining) > max_width do
    local n_chars = math.min(max_width, vim.fn.strchars(remaining))
    local chunk = vim.fn.strcharpart(remaining, 0, n_chars)
    while vim.fn.strdisplaywidth(chunk) > max_width and n_chars > 0 do
      n_chars = n_chars - 1
      chunk = vim.fn.strcharpart(remaining, 0, n_chars)
    end
    if n_chars <= 0 then
      chunk = vim.fn.strcharpart(remaining, 0, 1)
      remaining = vim.fn.strcharpart(remaining, 1)
      table.insert(lines, chunk)
    else
      remaining = vim.fn.strcharpart(remaining, n_chars)
      table.insert(lines, chunk)
    end
  end
  if vim.fn.strchars(remaining) > 0 then
    table.insert(lines, remaining)
  end
  return lines
end

---Pad every line to `width` so the border doesn't collapse.
---@param lines string[]
---@param width integer
local function pad_lines(lines, width)
  for i, line in ipairs(lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w < width then
      lines[i] = line .. string.rep(" ", width - w)
    end
  end
end

local function calc_height(n_wrap)
  return n_wrap + 6
end

---Return the display prefix for a permission type.
local PERMISSION_LABELS = {
  bash = "$ ",
  external_directory = "Access directory ",
  read = "Read ",
  write = "Write ",
  tool = "Run ",
}
local function cmd_prefix(permission)
  if PERMISSION_LABELS[permission] then
    return PERMISSION_LABELS[permission]
  end
  return (permission or "?") .. " "
end

---Split multi-line command on `\n` and wrap each segment independently.
---@return string[] wrapped
---@return integer n_wrap
local function split_and_wrap(cmd, inner)
  local segments = vim.split(cmd, "\n")
  local all_wrapped = {}
  local n = 0
  for _, segment in ipairs(segments) do
    local wrapped = wrap_text(segment, inner)
    n = n + #wrapped
    for _, wl in ipairs(wrapped) do
      table.insert(all_wrapped, wl)
    end
  end
  return all_wrapped, n
end

-- ──────────────────────────────────────────────
-- Render
-- ──────────────────────────────────────────────

---@param lines string[]
local function render(lines)
  if not state or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local w = state.width
  pad_lines(lines, w)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)

  for line_idx, line in ipairs(lines) do
    local col = 1
    for opt_idx, opt in ipairs(OPTIONS) do
      local marker = (opt_idx == selected) and ">" or " "
      local btn = "[" .. marker .. " " .. opt .. "]"
      local s, _ = line:find(vim.pesc(btn), col)
      if s then
        if opt_idx == selected then
          vim.api.nvim_buf_set_extmark(
            state.buf,
            NS,
            line_idx - 1,
            s - 1,
            { hl_group = "OpencodePermSelected", end_col = s - 1 + #btn }
          )
        end
        col = s + #btn
      end
    end
  end
end

---Build the lines to render.
local function build_lines()
  local ev = state and state.queue[state.queue_index] and state.queue[state.queue_index].event
  local cmd = (ev and cmd_prefix(ev.properties.permission) or "? ")
    .. (
      ev and ev.properties.patterns and #ev.properties.patterns > 0 and table.concat(ev.properties.patterns, ", ")
      or ""
    )
  local inner = state and state.width - 4 or 60

  local wrapped = split_and_wrap(cmd, inner)

  local lines = {}
  table.insert(lines, "")

  if state and #state.queue > 1 then
    table.insert(lines, "  Request " .. state.queue_index .. "/" .. #state.queue)
  end

  for _, wline in ipairs(wrapped) do
    table.insert(lines, "  " .. wline)
  end

  table.insert(lines, "")

  local parts = {}
  for i, opt in ipairs(OPTIONS) do
    local marker = (i == selected) and ">" or " "
    parts[i] = "[" .. marker .. " " .. opt .. "]"
  end
  table.insert(lines, "  " .. table.concat(parts, "  "))

  table.insert(lines, "")
  table.insert(lines, "  h/l: option  n/p: request  Enter: confirm  Esc/q: hide")

  return lines
end

-- ──────────────────────────────────────────────
-- Keymaps
-- ──────────────────────────────────────────────

local function setup_keymaps(buf)
  local function map(lhs, callback, desc)
    vim.keymap.set("n", lhs, callback, {
      buffer = buf,
      nowait = true,
      desc = desc,
    })
  end

  map("l", function()
    selected = math.min(selected + 1, #OPTIONS)
    render(build_lines())
  end, "Next option")

  map("h", function()
    selected = math.max(selected - 1, 1)
    render(build_lines())
  end, "Prev option")

  map("<Right>", function()
    selected = math.min(selected + 1, #OPTIONS)
    render(build_lines())
  end, "Next option")

  map("<Left>", function()
    selected = math.max(selected - 1, 1)
    render(build_lines())
  end, "Prev option")

  map("<CR>", M.confirm, "Confirm permission")

  map("<C-n>", M.next_permission, "Next queued request")
  map("<C-p>", M.prev_permission, "Prev queued request")

  map("n", M.next_permission, "Next queued request")
  map("p", M.prev_permission, "Prev queued request")

  map("<Esc>", M.hide, "Hide")
  map("q", M.hide, "Hide")
end

-- ──────────────────────────────────────────────
-- Window helpers
-- ──────────────────────────────────────────────

local function setup_win_closed(win)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      M.hide()
    end,
  })
end

-- ──────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────

---@param event opencode.server.Event
---@param server opencode.server.Server
function M.request(event, server)
  if not event or not server then
    return
  end

  if event.type == "permission.replied" and state then
    local replied = event.properties.requestID
    for i, q in ipairs(state.queue) do
      if q.id == replied then
        table.remove(state.queue, i)
        state.queue_index = math.min(state.queue_index, #state.queue)
        if #state.queue == 0 then
          OPTIONS = { "Once", "Always", "Reject" }
          selected = 1
          M.dismiss()
        else
          if #state.queue == 1 then
            OPTIONS = { "Once", "Always", "Reject" }
          end
          if state.visible then
            render(build_lines())
          end
        end
        break
      end
    end
    return
  end

  if event.type ~= "permission.asked" then
    return
  end

  if event.properties.permission == "edit" then
    return
  end

  if state then
    table.insert(state.queue, { event = event, id = event.properties.id })
    OPTIONS = { "Once", "Always", "Reject All", "Allow All" }
    selected = 1
    if state.visible then
      render(build_lines())
    end
    return
  end

  selected = 1

  local w = math.min(78, vim.o.columns - 4)
  local inner = w - 4

  local cmd = cmd_prefix(event.properties.permission)
    .. (
      event.properties.patterns and #event.properties.patterns > 0 and table.concat(event.properties.patterns, ", ")
      or ""
    )
  local _, n_wrap = split_and_wrap(cmd, inner)
  local h = calc_height(n_wrap)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "opencode_permission"

  local row = math.max(0, vim.o.lines - h - 3)
  local col = math.floor((vim.o.columns - w) / 2)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = w,
    height = h,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " OpenCode Permission ",
    title_pos = "center",
    focusable = true,
  })

  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = "FloatBorder:OpencodePermBorderNormal"

  state = {
    server = server,
    queue = { { event = event, id = event.properties.id } },
    queue_index = 1,
    win = win,
    buf = buf,
    width = w,
    visible = true,
  }

  setup_keymaps(buf)
  setup_win_closed(win)

  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = buf,
    callback = function()
      if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.wo[state.win].winhighlight = "FloatBorder:OpencodePermBorderFocus"
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      if state and state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.wo[state.win].winhighlight = "FloatBorder:OpencodePermBorderNormal"
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      M.dismiss()
    end,
  })

  local lines = build_lines()
  render(lines)
end

---Dismiss the floating window and reject all pending items.
function M.dismiss()
  if not state then
    return
  end
  for _, q in ipairs(state.queue) do
    state.server:permit(q.id, "reject"):catch(function(msg)
      vim.notify(msg, vim.log.levels.ERROR, { title = "opencode" })
    end)
  end
  OPTIONS = { "Once", "Always", "Reject" }
  selected = 1
  local win, buf = state.win, state.buf
  state = nil
  vim.schedule(function()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)
end

---Hide the floating window without dismissing the queue.
function M.hide()
  if not state or not state.win then
    return
  end
  local win = state.win
  state.win = nil
  state.visible = false
  vim.schedule(function()
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end)
end

---Recreate the floating window from hidden state.
function M.show()
  if not state or state.visible then
    return
  end
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    state = nil
    return
  end

  local w = state.width
  local ev = state.queue[state.queue_index].event
  local cmd = cmd_prefix(ev.properties.permission)
    .. (ev.properties.patterns and #ev.properties.patterns > 0 and table.concat(ev.properties.patterns, ", ") or "")
  local inner = w - 4
  local _, n_wrap = split_and_wrap(cmd, inner)
  local h = calc_height(n_wrap)

  local row = math.max(0, vim.o.lines - h - 3)
  local col = math.floor((vim.o.columns - w) / 2)

  local win = vim.api.nvim_open_win(state.buf, false, {
    relative = "editor",
    width = w,
    height = h,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " OpenCode Permission ",
    title_pos = "center",
    focusable = true,
  })

  vim.wo[win].cursorline = false
  vim.wo[win].winhighlight = "FloatBorder:OpencodePermBorderNormal"
  state.win = win
  state.visible = true
  setup_win_closed(win)

  render(build_lines())
end

---Toggle the floating window between visible and hidden.
function M.toggle()
  if not state then
    return
  end
  if state.visible then
    M.hide()
  else
    M.show()
  end
end

---Move selection left. Safe to call from any buffer (remote-control).
function M.move_left()
  if not state or not state.visible then
    return
  end
  selected = math.max(selected - 1, 1)
  render(build_lines())
end

---Move selection right. Safe to call from any buffer (remote-control).
function M.move_right()
  if not state or not state.visible then
    return
  end
  selected = math.min(selected + 1, #OPTIONS)
  render(build_lines())
end

---Move to the next queued request. Safe to call from any buffer.
function M.next_permission()
  if not state or not state.visible or #state.queue <= 1 then
    return
  end
  state.queue_index = math.min(state.queue_index + 1, #state.queue)
  render(build_lines())
end

---Move to the previous queued request. Safe to call from any buffer.
function M.prev_permission()
  if not state or not state.visible or #state.queue <= 1 then
    return
  end
  state.queue_index = math.max(state.queue_index - 1, 1)
  render(build_lines())
end

---Confirm the current selection. Safe to call from any buffer.
function M.confirm()
  if not state or not state.visible or #state.queue == 0 then
    return
  end

  local item = state.queue[state.queue_index]
  local choice = OPTIONS[selected]

  if choice == "Allow All" then
    local q = state.queue
    local srv = state.server
    local win, buf = state.win, state.buf
    state = nil
    OPTIONS = { "Once", "Always", "Reject" }
    selected = 1
    vim.schedule(function()
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end)
    local function approve(i)
      if i > #q then
        return
      end
      srv
        :permit(q[i].id, "once")
        :finally(function()
          approve(i + 1)
        end)
        :catch(function(msg)
          vim.notify(msg, vim.log.levels.ERROR, { title = "opencode" })
        end)
    end
    approve(1)
  elseif choice == "Reject All" then
    M.dismiss()
  else
    state.server:permit(item.id, choice:lower()):catch(function(msg)
      vim.notify(msg, vim.log.levels.ERROR, { title = "opencode" })
    end)
    table.remove(state.queue, state.queue_index)
    state.queue_index = math.min(state.queue_index, #state.queue)
    if #state.queue == 0 then
      OPTIONS = { "Once", "Always", "Reject" }
      selected = 1
      M.dismiss()
    else
      if #state.queue == 1 then
        OPTIONS = { "Once", "Always", "Reject" }
      end
      selected = 1
      render(build_lines())
    end
  end
end

return M
