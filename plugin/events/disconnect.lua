vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeDisconnect", { clear = true }),
  pattern = "OpencodeEvent:server.instance.disposed",
  callback = function()
    require("opencode.events").disconnect()
  end,
  desc = "Shut down SSE subscription when server disposes",
})
