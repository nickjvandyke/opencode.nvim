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
        kind = "markdown",
        value = "```" .. agent.description or "Agent" .. "```",
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
  local context = require("opencode.context").current
  if not item.documentation and context then
    -- Agents can be empty here - they already have documentation attached
    local rendered = context:render(item.label, {})
    -- Highlights won't match other locations, but there's no general way to control them.
    -- Would have to support each completion plugin separately.
    -- Markdown code blocks to preserve formatting.
    -- `blink.cmp` at least seems to render the doc window as markdown even when the kind is plaintext,
    -- and then things like `~` in consecutive filepaths become strikethroughs.
    -- Or matching `[]` disappears because it's interpreted as a markdown link with an empty URL.
    item.documentation = {
      kind = "markdown",
      value = "```" .. context.plaintext(rendered.output) .. "```",
    }
  end

  callback(nil, item)
end

---An in-process LSP that provides completions for context placeholders and agents.
---@type vim.lsp.Config
return {
  name = "opencode_ask_cmp",
  -- Note the filetype has no effect because `snacks.input` buftype is `prompt`.
  -- https://github.com/neovim/neovim/issues/36775
  -- Instead, we manually start the LSP in a callback.
  -- To that end, we also locate this file under `lua/` - not the usual `lsp/` - so Neovim's module resolution can find it.
  filetypes = { "opencode_ask" },
  cmd = function(dispatchers, config)
    return {
      request = function(method, params, callback)
        if handlers[method] then
          handlers[method](params, callback)
        end
      end,
      notify = function() end,
      is_closing = function()
        return false
      end,
      terminate = function() end,
    }
  end,
}
