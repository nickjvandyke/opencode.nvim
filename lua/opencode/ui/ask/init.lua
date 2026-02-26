---@module 'snacks.input'

local M = {}

---@class opencode.ask.Opts
---
---Text of the prompt.
---@field prompt? string
---
---Where to capture ask input.
---`"input"` uses `vim.ui.input`.
---`"buffer"` uses a centered floating multi-line buffer.
---@field capture? "input"|"buffer"
---
---Options for buffer capture mode.
---@field buffer? opencode.ask.BufferOpts
---
---Options for [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field snacks? snacks.input.Opts

---@class opencode.ask.BufferOpts
---@field width_ratio? number
---@field height_ratio? number
---@field min_width? number
---@field min_height? number
---@field border? string
---@field title_pos? "left"|"center"|"right"
---@field linewrap? boolean
---@field submit_on_write? boolean
---@field start_insert? boolean
---@field submit_keys? table<string, string[]|string>
---@field cancel_keys? table<string, string[]|string>

---@param keys string|string[]|nil
---@return string[]
local function normalize_keys(keys)
  if type(keys) == "string" then
    return { keys }
  end
  if vim.islist(keys) then
    return keys
  end
  return {}
end

---@param buf number
---@param mode_keys table<string, string[]|string>|nil
---@param callback function
local function set_mode_keymaps(buf, mode_keys, callback)
  if not mode_keys then
    return
  end
  for mode, keys in pairs(mode_keys) do
    for _, lhs in ipairs(normalize_keys(keys)) do
      vim.keymap.set(mode, lhs, callback, { buffer = buf, nowait = true, silent = true })
    end
  end
end

---@param buf number
---@param context opencode.Context
---@param ns number
---@param agents opencode.cli.client.Agent[]
local function highlight_buffer(buf, context, ns, agents)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local rendered = context:render(text, agents)
  local extmarks = context.extmarks(rendered.input)

  for _, extmark in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(buf, ns, (extmark.row or 1) - 1, extmark.col, {
      end_col = extmark.end_col,
      hl_group = extmark.hl_group,
    })
  end
end

---@param default? string
---@param context opencode.Context
---@param ask_opts opencode.ask.Opts
---@param server opencode.cli.server.Server
---@return Promise<string>
local function buffer_input(default, context, ask_opts, server)
  local Promise = require("opencode.promise")
  local buffer_opts = ask_opts.buffer or {}

  return Promise.new(function(resolve, reject)
    local width = math.max(buffer_opts.min_width or 60, math.floor(vim.o.columns * (buffer_opts.width_ratio or 0.7)))
    local height = math.max(buffer_opts.min_height or 8, math.floor(vim.o.lines * (buffer_opts.height_ratio or 0.3)))
    local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    local submit_on_write = buffer_opts.submit_on_write == true
    local temp_file = submit_on_write and vim.fn.tempname() or nil

    local buf = vim.api.nvim_create_buf(false, not submit_on_write)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = buffer_opts.border or "rounded",
      title = " " .. (ask_opts.prompt or "Ask opencode: ") .. " ",
      title_pos = buffer_opts.title_pos or "center",
    })

    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "opencode_ask"
    vim.bo[buf].buftype = ""
    vim.bo[buf].swapfile = false

    if temp_file then
      vim.api.nvim_buf_set_name(buf, temp_file)
    end
    vim.wo[win].wrap = buffer_opts.linewrap == true
    vim.wo[win].linebreak = buffer_opts.linewrap == true

    if buffer_opts.linewrap == true then
      vim.keymap.set("n", "j", "gj", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "k", "gk", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "0", "g0", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "^", "g^", { buffer = buf, nowait = true, silent = true })
      vim.keymap.set("n", "$", "g$", { buffer = buf, nowait = true, silent = true })
    end

    local initial = default and vim.split(default, "\n", { plain = true, trimempty = false }) or { "" }
    if #initial == 0 then
      initial = { "" }
    end
    if default and default ~= "" and initial[#initial] ~= "" then
      table.insert(initial, "")
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)
    vim.api.nvim_win_set_cursor(win, { #initial, 0 })

    local ns = vim.api.nvim_create_namespace("opencode_ask_highlight")
    highlight_buffer(buf, context, ns, server.subagents)

    local done = false
    local function finish_submit()
      if done then
        return
      end
      done = true
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local value = table.concat(lines, "\n")
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if temp_file then
        pcall(vim.fn.delete, temp_file)
      end
      if value == "" then
        reject()
      else
        resolve(value)
      end
    end
    local function finish_cancel()
      if done then
        return
      end
      done = true
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if temp_file then
        pcall(vim.fn.delete, temp_file)
      end
      reject()
    end

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = buf,
      callback = function()
        highlight_buffer(buf, context, ns, server.subagents)
      end,
    })

    vim.api.nvim_create_autocmd("WinClosed", {
      once = true,
      pattern = tostring(win),
      callback = finish_cancel,
    })

    if submit_on_write then
      vim.api.nvim_create_autocmd("BufWritePost", {
        buffer = buf,
        callback = finish_submit,
      })
    end

    set_mode_keymaps(buf, buffer_opts.submit_keys or { n = { "<C-s>" }, i = { "<C-s>" } }, finish_submit)
    set_mode_keymaps(buf, buffer_opts.cancel_keys or { n = { "q", "<Esc>" } }, finish_cancel)

    vim.lsp.start(require("opencode.ui.ask.cmp"), {
      bufnr = buf,
    })

    if buffer_opts.start_insert ~= false then
      vim.cmd("startinsert")
    end
  end)
end

---Prompt for input with `vim.ui.input`, with context- and server-aware completion.
---
---@param default? string Text to pre-fill the input with.
---@param context opencode.Context
---@return Promise<string> input
function M.ask(default, context)
  local Promise = require("opencode.promise")

  return require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      local ask_opts = require("opencode.config").opts.ask or {}
      if ask_opts.capture == "buffer" then
        return buffer_input(default, context, ask_opts, server)
      end

      ---@type snacks.input.Opts
      local input_opts = {
        default = default,
        highlight = function(text)
          local rendered = context:render(text, server.subagents)
          return context.input_highlight(rendered.input)
        end,
      }

      local input_ask_opts = vim.deepcopy(ask_opts)
      input_ask_opts.capture = nil
      input_ask_opts.buffer = nil

      -- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config,
      -- and to keep its fields optional. Double-merge is kinda ugly but seems like the lesser evil.
      input_opts = vim.tbl_deep_extend("force", input_opts, input_ask_opts)
      input_opts = vim.tbl_deep_extend("force", input_opts, ask_opts.snacks or {})

      return Promise.input(input_opts)
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

-- FIX: Overridden by blink.cmp cmdline completion if enabled, and that won't have the below items.
-- Can we wire up the below as a blink.cmp cmdline source?

---Completion function for context placeholders and `opencode` subagents.
---Must be a global variable for use with `vim.ui.select`.
---
---@param ArgLead string The text being completed.
---@param CmdLine string The entire current input line.
---@param CursorPos number The cursor position in the input line.
---@return table<string> items A list of filtered completion items.
_G.opencode_completion = function(ArgLead, CmdLine, CursorPos)
  -- Not sure if it's me or vim, but ArgLead = CmdLine... so we have to parse and complete the entire line, not just the last word.
  local start_idx, end_idx = CmdLine:find("([^%s]+)$")
  local latest_word = start_idx and CmdLine:sub(start_idx, end_idx) or nil

  local completions = {}
  for placeholder, _ in pairs(require("opencode.config").opts.contexts) do
    table.insert(completions, placeholder)
  end
  local server = require("opencode.events").connected_server
  local agents = server and server.subagents or {}
  for _, agent in ipairs(agents) do
    table.insert(completions, "@" .. agent.name)
  end

  local items = {}
  for _, completion in pairs(completions) do
    if not latest_word then
      local new_cmd = CmdLine .. completion
      table.insert(items, new_cmd)
    elseif completion:find(latest_word, 1, true) == 1 then
      local new_cmd = CmdLine:sub(1, start_idx - 1) .. completion .. CmdLine:sub(end_idx + 1)
      table.insert(items, new_cmd)
    end
  end
  return items
end

return M
