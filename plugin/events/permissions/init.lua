vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodePermissions", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked", "OpencodeEvent:permission.replied" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type string
    local url = args.data.url

    local opts = require("opencode.config").opts.events.permissions or {}
    if not opts.enabled then
      return
    end

    require("opencode.server")
      .new(url)
      :next(function(server) ---@param server opencode.server.Server
        require("opencode.events.permissions").request(event, server)
      end)
      :catch(function(err)
        if err then
          vim.notify(
            "Failed to display `opencode` permission request: " .. err,
            vim.log.levels.ERROR,
            { title = "opencode" }
          )
        end
      end)
  end,
  desc = "Display permission requests from opencode",
})
