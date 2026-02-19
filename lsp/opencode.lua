---@class opencode.lsp.Opts
---
---Whether to enable the `opencode` LSP.
---**WARNING**: This feature is experimental.
---@field enabled? boolean
---
---Filetypes to attach to.
---`nil` means all filetypes.
---@field filetypes? string[]
---
---@field handlers? opencode.lsp.Handlers

---Customize the LSP's handlers. These are the core of the integration, defining how the LSP responds to various requests from the editor.
---@class opencode.lsp.Handlers
---
---@field hover? opencode.lsp.handlers.hover.Opts
---
---@field code_action? opencode.lsp.handlers.code_action.Opts

---@class opencode.lsp.handlers.code_action.Opts
---
---@field enabled? boolean

---@class opencode.lsp.handlers.hover.Opts
---
---@field enabled? boolean
---
---[Model](https://opencode.ai/docs/models/) to use in the format of provider/model, e.g. "github-copilot/gpt-4.1".
---If not specified, the default model configured in `opencode` will be used.
---Recommend a fast model here.
---@field model? string

---@type table<vim.lsp.protocol.Method, fun(params: table, callback:fun(err: lsp.ResponseError?, result: any))>
local handlers = {}
local ms = vim.lsp.protocol.Methods

---@param params lsp.InitializeParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.InitializeResult)
handlers[ms.initialize] = function(params, callback)
  local config = require("opencode.config").opts
  callback(nil, {
    capabilities = {
      hoverProvider = config.lsp.handlers.hover.enabled,
      codeActionProvider = config.lsp.handlers.code_action.enabled,
      executeCommandProvider = {
        commands = { "opencode.fix" },
      },
    },
    serverInfo = {
      name = "opencode",
    },
  })
end

---@param params lsp.CodeActionParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.CodeAction[])
handlers[ms.textDocument_codeAction] = function(params, callback)
  -- Would prefer `params.context.diagnostics`, but it's empty?
  local diagnostics = vim.diagnostic.get(0, { lnum = params.range.start.line })
  ---@type lsp.CodeAction[]
  local fix_commands = vim.tbl_map(function(diagnostic) ---@param diagnostic vim.Diagnostic
    ---@type lsp.CodeAction
    return {
      title = "Ask opencode to fix: " .. diagnostic.message,
      kind = "quickfix",
      command = {
        title = "opencode.fix",
        command = "opencode.fix",
        arguments = { diagnostic },
      },
      tags = { 1 }, -- 1 = LLM Generated (not sure what effect that has though)
      -- diagnostics = ...,
    }
  end, diagnostics or {})

  callback(nil, fix_commands)
end

---@param params lsp.ExecuteCommandParams
---@param callback fun(err?: lsp.ResponseError, result: any)
handlers[ms.workspace_executeCommand] = function(params, callback)
  if params.command == "opencode.fix" then
    local diagnostic = params.arguments[1]
    ---@cast diagnostic vim.Diagnostic
    local filepath = require("opencode.context").format({ buf = diagnostic.bufnr })
    local prompt = "Fix diagnostic: " .. filepath .. require("opencode.context").format_diagnostic(diagnostic)

    require("opencode")
      .prompt(prompt, { submit = true })
      :next(function()
        callback(nil, nil) -- Indicate success
      end)
      :catch(function(err)
        callback({ code = -32000, message = "Failed to fix: " .. err })
      end)
  else
    callback({ code = -32601, message = "Unknown command: " .. params.command })
  end
end

handlers[ms.shutdown] = function(params, callback)
  -- I'd expect the client (Neovim) to handle this,
  -- but `vim.lsp.enable("opencode", false)` seems to have no effect without it?
  -- FIX: It's still in the active clients though? This only detaches it.
  -- for _, client in ipairs(vim.lsp.get_clients({ name = "opencode" })) do
  --   for bufnr, _ in pairs(client.attached_buffers) do
  --     vim.lsp.buf_detach_client(bufnr, client.id)
  --   end
  -- end

  callback(nil, nil)
end

---@type table<string, string>
local memoized_hover_results = {}

---@param params lsp.HoverParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.Hover)
handlers[ms.textDocument_hover] = function(params, callback)
  local symbol = vim.fn.expand("<cword>")
  -- local lines = vim.fn.readfile(params.textDocument.uri:gsub("^file://", ""))
  -- local text = table.concat(lines, "\n")
  local location = require("opencode.context").format({
    path = params.textDocument.uri:gsub("^file://", ""),
    start_line = params.position.line + 1,
    start_col = params.position.character + 1,
  })

  -- TODO: Would be nice to get cache hits for the same symbol.
  -- But hard without semantic information.
  -- e.g. could be the same name, in a different scope.
  if memoized_hover_results[location] then
    callback(nil, {
      contents = {
        kind = "markdown",
        value = memoized_hover_results[location],
      },
    })
    return
  end

  callback(nil, {
    contents = {
      kind = "markdown",
      value = "Asking `opencode`...",
    },
  })

  local prompt = {
    "The user has requested an LSP hover at " .. location,
    "The symbol under the cursor is: " .. symbol,
    "It is part of the larger phrase: " .. vim.fn.expand("<cWORD>"),
    -- Sending text vs location doesn't seem to make a big difference in speed...
    -- "Here is the full text of the file:",
    -- "```",
    -- text,
    -- "```",
    "Explain the symbol.",
    "Use the surrounding code as clues to its specific purpose in this code.",
    "Keep your response concise.",
    "Your response will be used directly as the LSP hover documentation.",
    "DO NOT restate the code or symbol name or location.",
    "DO NOT explain your thought process.",
    "ONLY provide the explanation.",
  }

  local cmd = {
    "opencode",
    "run",
  }
  local configured_model = require("opencode.config").opts.lsp.handlers.hover.model
  if configured_model then
    table.insert(cmd, "--model")
    table.insert(cmd, configured_model)
  end
  table.insert(cmd, table.concat(prompt, "\n"))

  local job = vim.system(cmd, nil, function(obj)
    if obj.signal == 15 then
      -- Terminated by user moving away from the hover; do nothing
      return
    end

    local output = obj.stdout or obj.stderr or "unknown error"
    if obj.code ~= 0 then
      vim.schedule(function()
        callback({ code = -32000, message = "Failed to hover: " .. output }, {
          contents = {
            kind = "markdown",
            value = "Hovering failed: " .. output .. "\n\n" .. location,
          },
        })
      end)
    else
      memoized_hover_results[location] = output
      -- Re-trigger hover to show the result; LSP doesn't support progressive hover results
      vim.schedule(function()
        -- Move the cursor to close the original hover; otherwise it just focuses it
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes(params.position.character > 0 and "<Left>" or "<Right>", true, false, true),
          "n",
          true
        )
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes(params.position.character > 0 and "<Right>" or "<Left>", true, false, true),
          "n",
          true
        )

        vim.lsp.buf.hover()
      end)
    end
  end)
  -- Don't re-trigger hover with completed results if the user has moved the cursor; would be confusing.
  local key_listener_id
  key_listener_id = vim.on_key(function()
    job:kill(15)
    vim.on_key(nil, key_listener_id)
  end)
end

---An in-process LSP that interacts with `opencode`.
--- - Code actions: ask `opencode` to fix diagnostics under the cursor.
---@type vim.lsp.Config
return {
  name = "opencode",
  filetypes = require("opencode.config").opts.lsp.filetypes,
  cmd = function(dispatchers, config)
    local closing = false
    local request_id = 0

    return {
      request = function(method, params, callback, notify_reply_callback)
        if handlers[method] then
          handlers[method](params, callback)
        end
        request_id = request_id + 1
        if notify_reply_callback then
          notify_reply_callback(request_id)
        end
        return true, request_id
      end,
      notify = function() end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        closing = true
      end,
    }
  end,
}
