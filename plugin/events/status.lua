vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeStatus", { clear = true }),
  pattern = {
    "OpencodeEvent:server.connected",
    "OpencodeEvent:session.status",
    "OpencodeEvent:server.instance.disposed",
  },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type string
    local url = args.data.url
    require("opencode.status").update(event, url)
  end,
  desc = "Update opencode status",
})
