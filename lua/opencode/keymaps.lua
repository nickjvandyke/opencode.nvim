local M = {}

---Apply buffer-local keymaps to the given buffer.
---@param bufnr integer The buffer number to apply keymaps to.
function M.apply(bufnr)
  local opts = { buffer = bufnr }

  vim.keymap.set("n", "<C-u>", function()
    require("opencode.api.command").command("session.half.page.up")
  end, vim.tbl_extend("force", opts, { desc = "Scroll up half page" }))

  vim.keymap.set("n", "<C-d>", function()
    require("opencode.api.command").command("session.half.page.down")
  end, vim.tbl_extend("force", opts, { desc = "Scroll down half page" }))

  vim.keymap.set("n", "gg", function()
    require("opencode.api.command").command("session.first")
  end, vim.tbl_extend("force", opts, { desc = "Go to first message" }))

  vim.keymap.set("n", "G", function()
    require("opencode.api.command").command("session.last")
  end, vim.tbl_extend("force", opts, { desc = "Go to last message" }))

  vim.keymap.set("n", "<Esc>", function()
    require("opencode.api.command").command("session.interrupt")
  end, vim.tbl_extend("force", opts, { desc = "Interrupt current session (esc)" }))
end

return M
