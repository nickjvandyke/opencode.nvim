---@module 'blink.cmp'
---@module 'snacks'

---@type table<vim.lsp.protocol.Method, fun(params: table, callback:fun(err: lsp.ResponseError?, result: any))>
local handlers = {}
local ms = vim.lsp.protocol.Methods

---@param params lsp.InitializeParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.InitializeResult)
handlers[ms.initialize] = function(params, callback)
  local config = require("opencode.config")
  -- Parse `opts.context` to return all non-alphanumeric first characters in placeholders
  local trigger_chars = {}
  for placeholder, _ in pairs(config.opts.contexts or {}) do
    local first_char = placeholder:sub(1, 1)
    if not first_char:match("%w") and not vim.tbl_contains(trigger_chars, first_char) then
      table.insert(trigger_chars, first_char)
    end
  end

  callback(nil, {
    capabilities = {
      completionProvider = {
        resolveProvider = true,
        triggerCharacters = trigger_chars,
      },
    },
    serverInfo = {
      name = "opencode_ask_cmp",
    },
  })
end

---@param params lsp.CompletionParams
---@param callback fun(err?: lsp.ResponseError, result: lsp.CompletionItem[])
handlers[ms.textDocument_completion] = function(params, callback)
  local items = {}
  local config = require("opencode.config")

  for placeholder, _ in pairs(config.opts.contexts or {}) do
    ---@type lsp.CompletionItem
    local item = {
      label = placeholder,
      filterText = placeholder,
      insertText = placeholder,
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
      kind = vim.lsp.protocol.CompletionItemKind.Variable,
    }
    table.insert(items, item)
  end

  local connected_server = require("opencode.events").connected_server
  local agents = connected_server and connected_server.subagents or {}
  for _, agent in ipairs(agents) do
    local label = "@" .. agent.name
    ---@type lsp.CompletionItem
    local item = {
      label = label,
      filterText = label,
      insertText = label,
      insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
      kind = vim.lsp.protocol.CompletionItemKind.Property,
      documentation = {
        kind = "plaintext",
        value = agent.description or "Agent",
      },
    }
    table.insert(items, item)
  end

  callback(nil, items)
end

---@param params lsp.CompletionItem
---@param callback fun(err?: lsp.ResponseError, result: lsp.CompletionItem)
handlers[ms.completionItem_resolve] = function(params, callback)
  local item = vim.deepcopy(params)
  if not item.documentation then
    -- Agents can be empty here - they already have documentation attached
    local rendered = require("opencode.context").current:render(item.label, {})
    item.documentation = {
      kind = "plaintext",
      value = require("opencode.context").current.plaintext(rendered.output),
      ---@param opts blink.cmp.CompletionDocumentationDrawOpts
      draw = function(opts)
        -- `blink.cmp`-specific.
        -- Unsure of a general solution right now.
        local buf = opts and opts.window and opts.window.buf
        if not buf or not opts.default_implementation then
          -- Not in `blink.cmp`
          return
        end

        opts.default_implementation({
          kind = "plaintext",
          value = opts.item.documentation.value,
        })

        local extmarks = require("opencode.context").current.extmarks(rendered.output)
        local ns_id = vim.api.nvim_create_namespace("opencode_enum_highlight")
        for _, extmark in ipairs(extmarks) do
          vim.api.nvim_buf_set_extmark(buf, ns_id, (extmark.row or 1) - 1, extmark.col, {
            end_col = extmark.end_col,
            hl_group = extmark.hl_group,
          })
        end
      end,
    }
  end

  callback(nil, item)
end

-- FIX: We get "invalid server name" when attempting to `:LspStop`, and this isn't called.
-- Maybe because the server is never actually registered via `vim.lsp.enable`?
-- Just started manually.
handlers[ms.shutdown] = function(params, callback)
  -- I'd expect the client (Neovim) to handle this,
  -- but `vim.lsp.enable("opencode", false)` seems to have no effect without it?
  for _, client in ipairs(vim.lsp.get_clients({ name = "opencode_ask_cmp" })) do
    for bufnr, _ in pairs(client.attached_buffers) do
      vim.lsp.buf_detach_client(bufnr, client.id)
    end
  end

  callback(nil, nil)
end

---An in-process LSP that provides completions for context placeholders and agents.
---
---@type vim.lsp.Config
return {
  name = "opencode_ask_cmp",
  -- Note the filetype has no effect because `snacks.input` buftype is `prompt`.
  -- https://github.com/neovim/neovim/issues/36775
  -- Instead, we manually start the LSP in a callback.
  -- To that end, we also locate this file under `lua/` - not the usual `lsp/` - so Neovim's module resolution can find it.
  filetypes = { "opencode_ask" },
  cmd = function(dispatchers, config)
    local closing = false
    local request_id = 0

    return {
      request = function(method, params, callback)
        if handlers[method] then
          handlers[method](params, callback)
        end
        request_id = request_id + 1
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
