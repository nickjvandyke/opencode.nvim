---opencode.nvim public API.
local M = {}

---@param err? string
local function on_error(err)
  if err then
    vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
  end
end

---Input a prompt for OpenCode.
---
--- - Passes the text to `prompt()`.
--- - Press `<Up>` to browse recent asks.
--- - Highlights and completes contexts and OpenCode subagents.
---   - Press `<Tab>` to trigger built-in completion.
---   - Provided by in-process LSP when using [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---
---@param default? string Text to pre-fill the input with.
function M.ask(default)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.ask").ask(default, context):next(function(input)
        return require("opencode.api.prompt").prompt(input, context)
      end)
    end)
    :catch(on_error)
end

---Select from all opencode.nvim functionality.
---
--- - Prompts
--- - Commands
--- - Servers
---
--- Highlights and previews items when using [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.ui.select").select(context, opts)
    end)
    :catch(on_error)
end

M.statusline = require("opencode.events.status").statusline

---Prompt OpenCode.
---
--- - Injects configured contexts.
--- - Trailing space appends; trailing "..." opens in `ask()`.
--- - OpenCode will interpret references to files or subagents.
---
---@param prompt string
function M.prompt(prompt)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      local context = require("opencode.context").new(server)
      return require("opencode.api.prompt").prompt(prompt, context)
    end)
    :catch(on_error)
end

---Command OpenCode.
---
---@param command opencode.server.Command | string
function M.command(command)
  require("opencode.server.discovery")
    .get()
    :next(function(server)
      return require("opencode.api.command").command(command, server)
    end)
    :catch(on_error)
end

---Wraps `prompt` as an operator, supporting ranges and dot-repeat.
---
---@param prompt string
function M.operator(prompt)
  _G.opencode_prompt_operator = function(kind) ---@param kind "char" | "line" | "block"
    local start_pos = vim.api.nvim_buf_get_mark(0, "[")
    local end_pos = vim.api.nvim_buf_get_mark(0, "]")
    if start_pos[1] > end_pos[1] or (start_pos[1] == end_pos[1] and start_pos[2] > end_pos[2]) then
      start_pos, end_pos = end_pos, start_pos
    end

    require("opencode.server.discovery")
      .get()
      :next(function(server)
        local context = require("opencode.context").new(server, {
          from = { start_pos[1], start_pos[2] },
          to = { end_pos[1], end_pos[2] },
          kind = kind,
        })

        return require("opencode.api.prompt").prompt(prompt, context)
      end)
      :catch(on_error)
  end

  vim.o.operatorfunc = "v:lua.opencode_prompt_operator"
  return "g@"
end

M.format = require("opencode.context").format

M.editor = {
  server = require("opencode.server.websocket"),
  selection = require("opencode.editor.selection"),
  lockfile = require("opencode.editor.lockfile"),
}

function M.start_live_context(opts)
  opts = vim.tbl_deep_extend("force", {}, require("opencode.config").opts.live_context or {}, opts or {})
  local port = opts.port or 0
  local auth_token = opts.auth_token

  if M.editor.server.is_running() then
    return true, M.editor.server.get_port()
  end

  if auth_token == true then
    local token_err
    auth_token, token_err = M.editor.lockfile.generate_auth_token()
    if not auth_token then
      return false, "Failed to generate authentication token: " .. (token_err or "unknown error")
    end
  elseif auth_token ~= nil and type(auth_token) ~= "string" then
    return false, "Authentication token must be a string or true"
  end

  M.editor.lockfile.clean_all()

  local server_ok, server_result = M.editor.server.start(port, auth_token)
  if not server_ok then
    return false, server_result
  end

  local actual_port = server_result

  local lock_ok, lock_result = M.editor.lockfile.create(actual_port, auth_token)
  if not lock_ok then
    M.editor.server.stop()
    return false, lock_result
  end

  M.editor.selection.enable()

  return true, actual_port
end

function M.stop_live_context()
  local port = M.editor.server.get_port()

  M.editor.selection.disable()
  M.editor.server.stop()

  if port then
    M.editor.lockfile.remove(port)
  end
end

function M.attach_context(line_start, line_end)
  local selection = require("opencode.editor.selection")
  local ok, err

  if line_start and line_end then
    ok, err = selection.send_range_as_mention(line_start, line_end)
  else
    ok, err = selection.send_visual_selection_as_mention()
  end

  if not ok then
    vim.notify(err or "Failed to attach context", vim.log.levels.WARN, { title = "OpenCode" })
  end

  return ok, err
end

return M
