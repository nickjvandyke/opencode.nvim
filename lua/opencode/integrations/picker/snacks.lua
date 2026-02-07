---@module 'snacks'

---Snacks picker integration for opencode.
---@class opencode.integrations.picker.snacks
local M = {}

---Send selected picker items to opencode prompt.
---@param picker snacks.Picker
function M.opencode_send(picker)
  local Context = require("opencode.context")
  local entries = {}
  for _, item in ipairs(picker:selected({ fallback = true })) do
    entries[#entries + 1] = Context.format({
      path = item.text,
      start_line = item.pos and item.pos[1] or nil,
      start_col = item.pos and item.pos[2] or nil,
      end_line = item.end_pos and item.end_pos[1] or nil,
      end_col = item.end_pos and item.end_pos[2] or nil,
    })
  end
  if #entries == 0 then
    return
  end
  require("opencode").prompt(table.concat(entries, "\n"))
end

return M
