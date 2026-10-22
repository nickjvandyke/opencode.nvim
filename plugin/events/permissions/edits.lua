vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeEdits", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked", "OpencodeEvent:permission.replied" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event

    local opts = require("opencode.config").opts.events.permissions or {}
    if not opts.enabled or not opts.edits.enabled then
      return
    end

    local server = require("opencode.server").connected
    if not server then
      return
    end

    require("opencode.events.permissions.edits")
      .diff(event)
      :next(function(reply)
        if reply and event.type == "permission.asked" then
          return server:permit(event.data.sessionID, event.data.id, reply)
        end
      end)
      :catch(function(err)
        if err then
          vim.notify("OpenCode edit request error: " .. err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end)
  end,
  desc = "Diff proposed edits from OpenCode",
})
