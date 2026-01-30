-- Apply buffer-local keymaps to opencode terminal buffers.
-- This handles the snacks provider (and any other provider using `opencode_terminal` filetype).
vim.api.nvim_create_autocmd("FileType", {
  pattern = "opencode_terminal",
  callback = function(ev)
    require("opencode.keymaps").apply(ev.buf)
  end,
})
