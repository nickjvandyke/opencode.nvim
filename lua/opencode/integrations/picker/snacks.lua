---@module 'snacks'

---Snacks picker integration for opencode.
---@class opencode.integrations.picker.snacks
local M = {}

---Send selected picker items to opencode prompt.
---@param picker snacks.Picker
function M.opencode_send(picker)
  local entries = {}
  for _, item in ipairs(picker:selected({ fallback = true })) do
    local entry = ""
    if item.text and item.text ~= "" then -- Includes file reference
      entry = item.text
    end
    -- Append line numbers if available
    if item.file and item.pos then
      local line_ref = ("L%d"):format(item.pos[1])
      if item.end_pos and item.end_pos[1] ~= item.pos[1] then
        line_ref = line_ref .. ("-L%d"):format(item.end_pos[1])
      end
      entry = entry .. " " .. line_ref
    end
    if entry ~= "" then
      entries[#entries + 1] = entry
    end
  end
  require("opencode").prompt(table.concat(entries, "\n") .. "\n")
end

return M
