vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    --[[
      {
        id = "evt_e54f03994001ig2dC1jXjQV6zL",
        properties = {
          file = "/Users/nvandyke/dev/opencode.nvim/plugin/events/quickfix.lua"
        },
        type = "file.edited"
      }
    ]]
    ---@type opencode.server.event.FileEdited
    local event = args.data.event
    local file = event.properties.file
  end,
  desc = "Add files edited by opencode to the quickfix list",
})
