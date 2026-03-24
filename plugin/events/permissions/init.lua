---@class opencode.events.permissions.Opts
---
---Whether to show permission requests.
---@field enabled? boolean
---
---Amount of user idle time before showing permission requests.
---@field idle_delay_ms? number
---
---@field edits? opencode.events.permissions.edits.Opts

local is_permission_request_open = false

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodePermissions", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked", "OpencodeEvent:permission.replied" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type number
    local port = args.data.port

    local opts = require("opencode.config").opts.events.permissions or {}
    if not opts.enabled then
      return
    end

    if event.type == "permission.asked" and not (event.properties.permission == "edit" and opts.edits.enabled) then
      local idle_delay_ms = opts.idle_delay_ms or 1000
      vim.notify(
        "`opencode` requested permission — awaiting idle…",
        vim.log.levels.INFO,
        { title = "opencode", timeout = idle_delay_ms }
      )
      require("opencode.util").on_user_idle(idle_delay_ms, function()
        is_permission_request_open = true
        vim.ui.select({ "Once", "Always", "Reject" }, {
          prompt = "Permit opencode to: " .. event.properties.permission .. " " .. table.concat(
            event.properties.patterns,
            ", "
          ) .. "?: ",
          format_item = function(item)
            return item
          end,
        }, function(choice)
          -- cat
          is_permission_request_open = false
          if choice then
            require("opencode.server").new(port):next(function(server) ---@param server opencode.server.Server
              server:permit(event.properties.id, choice:lower())
            end)
          end
        end)
      end)
    elseif event.type == "permission.replied" then
      if is_permission_request_open then
        -- Close our permission dialog, in case user responded in the TUI
        -- TODO: Hmm, we don't seem to process the event while built-in select is open...
        -- TODO: With snacks.picker open, we process the event, but this isn't the right way to close it...
        -- Or we don't process the event until after it closes (manually)
        -- vim.api.nvim_feedkeys("q", "n", true)
        -- is_permission_request_open = false
      end
    end
  end,
  desc = "Display permission requests from opencode",
})
