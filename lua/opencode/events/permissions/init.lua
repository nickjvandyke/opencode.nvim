---@class opencode.events.permissions.Opts
---@field enabled? boolean Whether to show permission requests.
---@field edits? opencode.events.permissions.edits.Opts

local M = {}

---@param event opencode.server.Event
---@return Promise<opencode.server.PermissionReply>
function M.request(event)
  local data = event.data
  return require("opencode.promise.ui")
    .select({ "Once", "Always", "Reject" }, {
      prompt = "Permit opencode to: " .. data.action .. " " .. table.concat(data.resources or {}, ", ") .. "?: ",
      format_item = function(item)
        return item
      end,
    })
    :next(function(choice)
      return require("opencode.promise").resolve(choice:lower())
    end)
end

return M
