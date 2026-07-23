vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodePermissions", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type string
    local url = args.data.url

    local opts = require("opencode.config").opts.events.permissions or {}
    if
      not opts.enabled
      or event.type ~= "permission.asked"
      or (opts.edits.enabled and event.properties.permission == "edit")
    then
      return
    end

    require("opencode.server")
      .new(url)
      :next(function(server)
        return require("opencode.events.permissions").request(event):next(function(choice)
          return server:permit(event.properties.id, choice)
        end)
      end)
      :catch(function(err)
        vim.notify("OpenCode permission request error: " .. err, vim.log.levels.ERROR, { title = "opencode" })
      end)

    -- TODO: Would like to close our permission dialog on `permission.replied`, in case user responded in the TUI.
    -- But we don't seem to process the event while built-in select is open...
    -- With snacks.picker open, we process the event, but this isn't the right way to close it...
    -- Or we don't process the event until after it closes (manually)
  end,
  desc = "Display and respond to permission requests from OpenCode",
})
