---@class opencode.events.permissions.Opts
---@field enabled? boolean Whether to show permission requests.
---@field edits? opencode.events.permissions.edits.Opts

local M = {}

local is_permission_request_open = false

---@param event opencode.server.Event
---@param server opencode.server.Server
function M.request(event, server)
  local opts = require("opencode.config").opts.events.permissions or {}

  if event.type == "permission.asked" and not (event.properties.permission == "edit" and opts.edits.enabled) then
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
      is_permission_request_open = false
      if choice then
        server:permit(event.properties.id, choice:lower()):catch(function(msg)
          vim.notify(msg, vim.log.levels.ERROR, { title = "opencode" })
        end)
      end
    end)
  elseif event.type == "permission.replied" then
    if is_permission_request_open then
      -- Close our permission dialog, in case user responded in the TUI
      -- FIX: Hmm, we don't seem to process the event while built-in select is open...
      -- With snacks.picker open, we process the event, but this isn't the right way to close it...
      -- Or we don't process the event until after it closes (manually)
      -- vim.api.nvim_feedkeys("q", "n", true)
      -- is_permission_request_open = false
    end
  end
end

return M
