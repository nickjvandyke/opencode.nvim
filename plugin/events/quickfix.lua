vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:*", -- TODO: Should we narrow this? I like the general solution to check properties.file though.
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    ---@type opencode.server.Event
    local event = args.data.event
    require("opencode.events.quickfix").add(event)
  end,
  desc = "Add files used by OpenCode to a quickfix list",
})
