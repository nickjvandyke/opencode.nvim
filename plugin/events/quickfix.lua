vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    ---@type opencode.server.event.FileEdited
    local event = args.data.event
    local file = event.properties.file

    vim.fn.setqflist({
      { filename = file, text = "Edited by OpenCode", type = "I" },
    }, "a")
  end,
  desc = "Add files edited by opencode to the quickfix list",
})
