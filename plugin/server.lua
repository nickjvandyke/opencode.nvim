vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    local stop = require("opencode.config").opts.server.stop
    if stop then
      stop()
    end
  end,
})
