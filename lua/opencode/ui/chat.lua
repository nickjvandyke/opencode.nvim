---Custom chat frontend for opencode.nvim
local M = {}

---@class opencode.ui.chat.State
---@field bufnr number
---@field winid number
---@field session_id string|nil
---@field messages table[]
---@field port number|nil
---@field streaming_message_index number|nil
---@field provider_id string
---@field model_id string

---@type opencode.ui.chat.State|nil
M.state = nil

---Create a new chat window
---@param opts? { width?: number, height?: number, provider_id?: string, model_id?: string }
---@return opencode.ui.chat.State
function M.open(opts)
  opts = opts or {}

  -- Close existing chat window if open
  if M.state then
    M.close()
  end

  -- Get config
  local config = require("opencode.config").opts.chat or {}

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "opencode_chat", { buf = bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })

  -- Create floating window
  -- Support both fractional (0-1) and absolute pixel values
  local width
  if opts.width ~= nil then
    if opts.width > 0 and opts.width < 1 then
      width = math.floor(vim.o.columns * opts.width)
    else
      width = opts.width
    end
  else
    width = math.floor(vim.o.columns * (config.width or 0.6))
  end

  local height
  if opts.height ~= nil then
    if opts.height > 0 and opts.height < 1 then
      height = math.floor(vim.o.lines * opts.height)
    else
      height = opts.height
    end
  else
    height = math.floor(vim.o.lines * (config.height or 0.7))
  end

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " OpenCode Chat ",
    title_pos = "center",
  })

  -- Set window options
  vim.api.nvim_set_option_value("wrap", true, { win = winid })
  vim.api.nvim_set_option_value("linebreak", true, { win = winid })
  vim.api.nvim_set_option_value("cursorline", true, { win = winid })

  M.state = {
    bufnr = bufnr,
    winid = winid,
    session_id = nil,
    messages = {},
    port = nil,
    streaming_message_index = nil,
    provider_id = opts.provider_id or config.provider_id or "anthropic",
    model_id = opts.model_id or config.model_id or "claude-3-5-sonnet-20241022",
  }

  -- Setup keymaps
  M.setup_keymaps(bufnr)

  return M.state
end

---Setup buffer keymaps
---@param bufnr number
function M.setup_keymaps(bufnr)
  local config = require("opencode.config").opts.chat or {}
  local keymaps = config.keymaps or {}
  local opts = { noremap = true, silent = true, buffer = bufnr }

  -- Helper function to set keymaps that might be arrays
  local function set_keymap(keys, callback, desc)
    if type(keys) == "string" then
      vim.keymap.set("n", keys, callback, vim.tbl_extend("force", opts, { desc = desc }))
    elseif type(keys) == "table" then
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, callback, vim.tbl_extend("force", opts, { desc = desc }))
      end
    end
  end

  -- Close window
  set_keymap(keymaps.close or { "q", "<Esc>" }, function()
    M.close()
  end, "Close chat")

  -- Send prompt
  set_keymap(keymaps.send or { "i", "a" }, function()
    M.prompt_input()
  end, "Send message")

  -- Copy message
  set_keymap(keymaps.yank or "yy", function()
    M.yank_current_message()
  end, "Yank current message")

  -- New session
  set_keymap(keymaps.new_session or "n", function()
    M.new_session()
  end, "New session")

  -- Interrupt
  set_keymap(keymaps.interrupt or "<C-c>", function()
    M.interrupt()
  end, "Interrupt")
end

---Close chat window
function M.close()
  if M.state then
    if vim.api.nvim_win_is_valid(M.state.winid) then
      vim.api.nvim_win_close(M.state.winid, true)
    end
    if vim.api.nvim_buf_is_valid(M.state.bufnr) then
      vim.api.nvim_buf_delete(M.state.bufnr, { force = true })
    end
    M.state = nil
  end
end

---Render messages to buffer
function M.render()
  if not M.state or not vim.api.nvim_buf_is_valid(M.state.bufnr) then
    return
  end

  local lines = {}
  local highlights = {}

  -- Get window width for dynamic separator
  local win_width = vim.api.nvim_win_is_valid(M.state.winid) and vim.api.nvim_win_get_width(M.state.winid) or 80

  for i, msg in ipairs(M.state.messages) do
    -- Add separator
    if i > 1 then
      table.insert(lines, "")
      table.insert(lines, string.rep("─", win_width))
      table.insert(lines, "")
    end

    -- Add role header with proper role handling
    local role_label
    if msg.role == "user" then
      role_label = "You"
    elseif msg.role == "system" then
      role_label = "System"
    else
      -- Default to Assistant for assistant role or nil
      role_label = "Assistant"
    end
    local header = string.format("### %s", role_label)
    local header_line = #lines
    table.insert(lines, header)
    table.insert(lines, "")

    -- Add highlight for header
    local hl_group
    if msg.role == "user" then
      hl_group = "Title"
    elseif msg.role == "system" then
      hl_group = "Comment"
    else
      hl_group = "Special"
    end
    table.insert(highlights, {
      line = header_line,
      col_start = 0,
      col_end = #header,
      hl_group = hl_group,
    })

    -- Add message content
    if msg.text then
      local content_lines = vim.split(msg.text, "\n")
      for _, line in ipairs(content_lines) do
        table.insert(lines, line)
      end
    end

    -- Show typing indicator for streaming messages
    if msg.streaming and not msg.complete then
      table.insert(lines, "")
      table.insert(lines, "▋") -- Typing indicator
    end
  end

  -- Update buffer
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.state.bufnr })
  vim.api.nvim_buf_set_lines(M.state.bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.state.bufnr })

  -- Apply highlights
  local ns_id = vim.api.nvim_create_namespace("opencode_chat")
  vim.api.nvim_buf_clear_namespace(M.state.bufnr, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M.state.bufnr, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
  end

  -- Scroll to bottom
  if vim.api.nvim_win_is_valid(M.state.winid) and #lines > 0 then
    vim.api.nvim_win_set_cursor(M.state.winid, { #lines, 0 })
  end
end

---Prompt for user input
function M.prompt_input()
  if not M.state or not M.state.port or not M.state.session_id then
    vim.notify("No active session", vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  vim.ui.input({ prompt = "Message: " }, function(input)
    if input and input ~= "" then
      M.send_message(input)
    end
  end)
end

---Send a message
---@param text string
function M.send_message(text)
  if not M.state or not M.state.port or not M.state.session_id then
    vim.notify("No active session", vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  -- Add user message to UI immediately
  table.insert(M.state.messages, {
    role = "user",
    text = text,
  })
  M.render()

  -- Add placeholder for assistant response
  table.insert(M.state.messages, {
    role = "assistant",
    text = "",
    streaming = true,
    complete = false,
  })
  M.state.streaming_message_index = #M.state.messages
  M.render()

  -- Send to backend
  local client = require("opencode.cli.client")

  client.send_message(text, M.state.session_id, M.state.port, M.state.provider_id, M.state.model_id, function()
    -- Response will come via SSE events
  end)
end

---Add or update a message
---@param message table
function M.add_message(message)
  if not M.state then
    return
  end

  -- Validate message has required fields
  if not message or not message.role then
    vim.notify("Invalid message: missing role", vim.log.levels.WARN, { title = "opencode" })
    return
  end

  -- Update last assistant message if streaming
  if message.role == "assistant" and M.state.streaming_message_index then
    -- Verify index is within bounds
    if M.state.streaming_message_index <= #M.state.messages then
      local last = M.state.messages[M.state.streaming_message_index]
      if last and last.role == "assistant" and last.streaming then
        last.text = message.text or last.text or ""
        if message.complete then
          last.complete = true
          last.streaming = false
          M.state.streaming_message_index = nil
        end
        M.render()
        return
      end
    end
  end

  -- Otherwise add new message
  table.insert(M.state.messages, message)
  M.render()
end

---Yank the current message under cursor
function M.yank_current_message()
  if not M.state then
    return
  end

  -- Find which message the cursor is on
  local cursor_line = vim.api.nvim_win_get_cursor(M.state.winid)[1]
  local current_line = 0

  for _, msg in ipairs(M.state.messages) do
    -- Account for separator and header
    if current_line > 0 then
      current_line = current_line + 3 -- blank, separator, blank
    end
    current_line = current_line + 2 -- header + blank

    local content_lines = vim.split(msg.text or "", "\n")
    local msg_end = current_line + #content_lines

    if cursor_line >= current_line and cursor_line <= msg_end then
      -- Found the message, yank it
      vim.fn.setreg('"', msg.text or "")
      vim.notify("Message yanked to clipboard", vim.log.levels.INFO, { title = "opencode" })
      return
    end

    current_line = msg_end
  end
end

---Start a new session
function M.new_session()
  if not M.state or not M.state.port then
    vim.notify("No connection to opencode", vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  -- Clear messages
  M.state.messages = {}
  M.state.session_id = nil
  M.state.streaming_message_index = nil
  M.render()

  -- Create new session
  local client = require("opencode.cli.client")
  client.tui_execute_command("session.new", M.state.port, function()
    -- Session ID will be set via SSE event
    vim.notify("New session started", vim.log.levels.INFO, { title = "opencode" })
  end)
end

---Interrupt the current session
function M.interrupt()
  if not M.state or not M.state.port then
    vim.notify("No connection to opencode", vim.log.levels.ERROR, { title = "opencode" })
    return
  end

  local client = require("opencode.cli.client")
  client.tui_execute_command("session.interrupt", M.state.port, function()
    if M.state and M.state.streaming_message_index then
      -- Verify index is within bounds
      if M.state.streaming_message_index <= #M.state.messages then
        local msg = M.state.messages[M.state.streaming_message_index]
        if msg then
          msg.complete = true
          msg.streaming = false
        end
      end
      M.state.streaming_message_index = nil
      M.render()
    end
    vim.notify("Session interrupted", vim.log.levels.INFO, { title = "opencode" })
  end)
end

---Set the session ID
---@param session_id string
function M.set_session_id(session_id)
  if M.state then
    M.state.session_id = session_id
  end
end

---Get the current state
---@return opencode.ui.chat.State|nil
function M.get_state()
  return M.state
end

return M
