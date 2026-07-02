local M = {}

local QUICKFIX_LIST_TITLE = "OpenCode"
local qf_list_id

---Add `event.properties.file` (if it exists) and `event.type` to an "OpenCode" quickfix list.
---
---@param event opencode.server.Event
function M.add(event)
  ---@type string?
  local file = event.properties.file
  if not file then
    return
  end

  -- TODO: Probably some way to simplify this
  if qf_list_id then
    local existing = vim.fn.getqflist({ id = qf_list_id, items = 0 })
    if existing.id ~= qf_list_id then
      qf_list_id = nil
    end
  end
  if not qf_list_id then
    vim.fn.setqflist({}, " ", { title = QUICKFIX_LIST_TITLE })
    qf_list_id = vim.fn.getqflist({ id = 0 }).id
  end

  local existing_items = vim.fn.getqflist({ id = qf_list_id, items = 0 })

  local buf = vim.fn.bufnr(file)
  ---@type vim.quickfix.entry
  local new_item = {
    filename = file,
    bufnr = buf > 0 and buf or nil,
    text = event.type,
    type = "I",
    -- Would love to have line/col... but OpenCode only includes the file
  }

  local item_already_exists = vim.iter(existing_items.items):any(function(i) ---@param i vim.quickfix.entry
    return (i.filename == new_item.filename or i.bufnr == new_item.bufnr) and i.text == new_item.text
  end)
  if item_already_exists then
    return
  end

  table.insert(existing_items.items, new_item)
  vim.fn.setqflist({}, "u", { id = qf_list_id, items = existing_items.items })

  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd.copen()
  vim.api.nvim_set_current_win(prev_win)
end

return M
