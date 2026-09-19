vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodePermissions", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event

    local opts = require("opencode.config").opts.events.permissions or {}
    if
      not opts.enabled
      or event.type ~= "permission.asked"
      -- Defer to the edit-diff handler only when it can actually show a preview.
      or (opts.edits.enabled and require("opencode.events.permissions.edits").preview(event) ~= nil)
    then
      return
    end

    local server = require("opencode.server").connected
    if not server then
      return
    end

    require("opencode.events.permissions")
      .request(event)
      :next(function(choice)
        return server:permit(event.data.sessionID, event.data.id, choice)
      end)
      :catch(function(err)
        if err then
          vim.notify("OpenCode permission request error: " .. err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end)

    -- TODO: Would like to close our permission dialog on `permission.replied`, in case user responded in the TUI.
    -- But we don't seem to process the event while built-in select is open...
    -- With snacks.picker open, we process the event, but this isn't the right way to close it...
    -- Or we don't process the event until after it closes (manually)
  end,
  desc = "Display and respond to permission requests from OpenCode",
})
