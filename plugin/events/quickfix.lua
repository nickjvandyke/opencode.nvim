vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function()
    if not require("opencode.config").opts.events.quickfix then
      return
    end


  end,
  desc = "Add files edited by opencode to quickfix list",
})
