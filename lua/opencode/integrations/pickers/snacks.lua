---@module 'snacks'

local M = {}

---Send the selected or current `snacks.picker` items to `opencode`,
---Formats items' file and position if possible, otherwise falls back to their text content.
---@param picker snacks.Picker
function M.send(picker)
  local items = vim.tbl_map(function(item)
    return item.file
        -- Prefer just the location if possible, so the LLM can also fetch context
        and require("opencode.context").format({
          path = item.file,
          start_line = item.pos and item.pos[1] or nil,
          start_col = item.pos and item.pos[2] or nil,
          end_line = item.end_pos and item.end_pos[1] or nil,
          end_col = item.end_pos and item.end_pos[2] or nil,
        })
      or item.text
  end, picker:selected({ fallback = true }))

  if #items > 0 then
    require("opencode").prompt(table.concat(items, "\n"))
  end
end

return M
