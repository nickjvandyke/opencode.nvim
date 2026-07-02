vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    ---@type opencode.server.Event
    local event = args.data.event
    require("opencode.events.quickfix").add(event)
  end,
  desc = "Add files edited by OpenCode to a quickfix list",
})
