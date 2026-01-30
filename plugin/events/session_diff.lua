vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeSessionDiff", { clear = true }),
  pattern = "OpencodeEvent:message.updated",
  callback = function(args)
    ---@type opencode.cli.client.Event
    local event = args.data.event

    local opts = require("opencode.config").opts.events.session_diff or {}
    if not opts.enabled then
      return
    end

    -- Only show review for assistant messages that have diffs
    local message = event.properties.info
    if message and message.role == "user" and message.summary and message.summary.diffs then
      require("opencode.diff").show_message_diff(message, opts)
    end
  end,
  desc = "Display session diff review from opencode",
})
