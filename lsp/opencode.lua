local handlers = require("opencode.lsp")
local closing = false
local request_id = 0

---@type vim.lsp.Config
return {
  name = "opencode",
  filetypes = require("opencode.config").opts.lsp.filetypes,
  cmd = function(dispatchers, config)
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
        -- FIX: Stopping/disabling the LSP has no effect
        -- https://github.com/neovim/neovim/pull/24338#issuecomment-3929276145
        closing = true
      end,
    }
  end,
}
