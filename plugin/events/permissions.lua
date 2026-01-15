---@class opencode.events.permissions.Opts
---
---Whether to show permission requests.
---@field enabled boolean
---
---Amount of user idle time before showing permission requests.
---@field idle_delay_ms number
---
---Options for permission confirmation dialog.
---@field confirm opencode.events.permissions.confirm.Opts

---@class opencode.events.permissions.confirm.Opts
---
---Whether to show the confirmation dialog for edit permissions.
---When false, uses the default `vim.ui.select` interface.
---@field enabled boolean
---
---Window configuration for the confirmation dialog.
---@field window opencode.events.permissions.confirm.window.Opts

---@class opencode.events.permissions.confirm.window.Opts
---
---Configuration for the confirmation window.
---Passed to `vim.api.nvim_open_win()` as the config parameter.
---Can be a table or a function that returns a table.
---@field config table|fun():table
---
---Window-local options to set on the confirmation window.
---Key-value pairs passed to `vim.api.nvim_set_option_value()` with scope "local".
---@field options table<string, any>
---
---Key mappings for the confirmation window.
---Keys are Vim key notation (e.g., "a", "<CR>", "q").
---Values are action names: "Once", "Always", "Reject", or "Close" (case-insensitive).
---"Close" closes the window without calling the callback.
---@field mappings table<string, string>

---@param delay_ms number
---@param callback function
local function on_user_idle(delay_ms, callback)
  local idle_timer = vim.uv.new_timer()
  local key_listener_id = nil

  local function on_idle()
    idle_timer:stop()
    idle_timer:close()
    vim.on_key(nil, key_listener_id)

    callback()
  end

  local function reset_idle_timer()
    idle_timer:stop()
    idle_timer:start(delay_ms, 0, vim.schedule_wrap(on_idle))
  end

  key_listener_id = vim.on_key(function()
    reset_idle_timer()
  end)

  -- Start the initial timer
  reset_idle_timer()
end

local is_permission_request_open = false

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodePermissions", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked", "OpencodeEvent:permission.replied" },
  callback = function(args)
    ---@type opencode.cli.client.Event
    local event = args.data.event
    ---@type number
    local port = args.data.port

    local opts = require("opencode.config").opts.events.permissions or {}
    if not opts.enabled then
      return
    end

    if event.type == "permission.asked" then
      local idle_delay_ms = opts.idle_delay_ms
      vim.notify(
        "`opencode` requested permission — awaiting idle…",
        vim.log.levels.INFO,
        { title = "opencode", timeout = idle_delay_ms }
      )
      on_user_idle(idle_delay_ms, function()
        is_permission_request_open = true
        if opts.confirm.enabled and event.properties.permission == "edit" then
          return require("opencode.ui.confirm").confirm(event, function(choice)
            is_permission_request_open = false
            if choice then
              require("opencode.cli.client").permit(port, event.properties.id, choice:lower())
            end
          end)
        end
        vim.ui.select({ "Once", "Always", "Reject" }, {
          prompt = "Permit opencode to: " .. event.properties.permission .. " " .. table.concat(
            event.properties.patterns,
            ", "
          ) .. "?: ",
          format_item = function(item)
            return item
          end,
        }, function(choice)
          is_permission_request_open = false
          if choice then
            require("opencode.cli.client").permit(port, event.properties.id, choice:lower())
          end
        end)
      end)
    elseif event.type == "permission.replied" and is_permission_request_open then
      -- Close our permission dialog, in case user responded in the TUI
      -- TODO: Hmm, we don't seem to process the event while built-in select is open...
      -- TODO: With snacks.picker open, we process the event, but this isn't the right way to close it...
      -- Or we don't process the event until after it closes (manually)
      -- vim.api.nvim_feedkeys("q", "n", true)
      -- is_permission_request_open = false
    end
  end,
  desc = "Display permission requests from opencode",
})
