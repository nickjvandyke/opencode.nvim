-- Debug helper: Add this to your Neovim config temporarily to see ALL opencode events

vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*",
  callback = function(args)
    local event = args.data.event
    vim.notify(
      string.format("[EVENT] %s\nProperties: %s", event.type, vim.inspect(event.properties or {})),
      vim.log.levels.INFO,
      { title = "opencode.debug" }
    )
  end,
  desc = "Debug all opencode events",
})
