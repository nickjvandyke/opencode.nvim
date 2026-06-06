---@module 'snacks'

local M = {}

---Send the selected or current `snacks.picker` items to `opencode`,
---Formats items' file and position if possible, otherwise falls back to their text content.
---@param picker snacks.Picker
function M.send(picker)
  local selected = picker:selected({ fallback = true })
  if #selected > 0 then
    require("opencode.server.discovery")
      .get()
      :next(function(server) ---@param server opencode.server.Server
        local items = vim.tbl_map(function(item)
          return item.file
              -- Prefer just the location if possible, so `opencode` can also fetch context
              and require("opencode.context").format(item.file, {
                start_line = item.pos and item.pos[1] or nil,
                start_col = item.pos and item.pos[2] or nil,
                end_line = item.end_pos and item.end_pos[1] or nil,
                end_col = item.end_pos and item.end_pos[2] or nil,
              }, server)
            or item.text
        end, selected)

        return require("opencode.api.prompt").prompt(table.concat(items, "\n"), server)
      end)
      :catch(function(err)
        if err then
          vim.notify(err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end)
  end
end

return M
