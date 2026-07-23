---@class opencode.events.permissions.Opts
---@field enabled? boolean Whether to show permission requests.
---@field edits? opencode.events.permissions.edits.Opts

local M = {}

---@param event opencode.server.Event | { type: "permission.asked" }
---@return Promise<opencode.server.PermissionReply>
function M.request(event)
  return require("opencode.promise.ui")
    .select({ "Once", "Always", "Reject" }, {
      prompt = "Permit opencode to: " .. event.properties.permission .. " " .. table.concat(
        event.properties.patterns,
        ", "
      ) .. "?: ",
      format_item = function(item)
        return item
      end,
    })
    :next(function(choice)
      return require("opencode.promise").resolve(choice)
    end)
end

return M
