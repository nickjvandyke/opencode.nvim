---@class opencode.lsp.Opts
---
---Whether to enable the `opencode` LSP.
---@field enabled boolean
---
---Filetypes to attach to.
---`nil` means all filetypes.
---@field filetypes? string[]

---@type table<vim.lsp.protocol.Method, fun(params: table, callback:fun(err: lsp.ResponseError?, result: any))>
local handlers = {}
local ms = vim.lsp.protocol.Methods

---@param params lsp.InitializeParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.InitializeResult)
handlers[ms.initialize] = function(params, callback)
  callback(nil, {
    capabilities = {
      codeActionProvider = true,
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
