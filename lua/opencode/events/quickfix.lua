local M = {}

local QUICKFIX_LIST_TITLE = "OpenCode"
local qf_list_id

function M.add(event)
  ---@type string
  local file = event.properties.file

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
  local existing = vim.fn.getqflist({ id = qf_list_id, items = 0 })

  -- TODO: Would love to have line/col... but event only includes the file
  local new_item = { filename = file, bufnr = vim.fn.bufnr(file), type = "I" }
  local item_already_exists = vim.iter(existing.items):any(function(i)
    return i.filename == new_item.filename or i.bufnr == new_item.bufnr
  end)

  if not item_already_exists then
    table.insert(existing.items, new_item)
    -- TODO: Needs to use `nr` to modify specific list? Need to fetch from id first.
    vim.fn.setqflist({}, "u", { id = qf_list_id, items = existing.items })
  end

  local prev_win = vim.api.nvim_get_current_win()
  vim.cmd.copen()
  vim.api.nvim_set_current_win(prev_win)
end

return M
