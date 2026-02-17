local bufnr = vim.api.nvim_get_current_buf()
-- Supposedly it should just auto-attach after a global `vim.lsp.enable("opencode")`,
-- but maybe `snacks.input` doesn't fire the correct event or something.
vim.lsp.start(require("lsp.opencode"), {
  bufnr = bufnr,
})
