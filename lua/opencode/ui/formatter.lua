local M = {}

---@param output Output
---@param code string
---@param file_type string
function M._format_diff(output, code, file_type)
  --- NOTE: use longer code fence because code could contain ```
  output:add_line("`````" .. file_type)
  local lines = vim.split(code, "\n")
  if #lines > 5 then
    lines = vim.list_slice(lines, 6)
  end

  for _, line in ipairs(lines) do
    local first_char = line:sub(1, 1)
    if first_char == "+" or first_char == "-" then
      local hl_group = first_char == "+" and "DiffAdd" or "DiffDelete"
      output:add_line(" " .. line:sub(2))
      local line_idx = output:get_line_count()
      output:add_extmark(line_idx - 1, function()
        return {
          end_col = 0,
          end_row = line_idx,
          virt_text = { { first_char, hl_group } },
          hl_group = hl_group,
          hl_eol = true,
          priority = 5000,
          right_gravity = true,
          end_right_gravity = false,
          virt_text_hide = false,
          virt_text_pos = "overlay",
          virt_text_repeat_linebreak = false,
        }
      end)
    else
      output:add_line(line)
    end
  end
  output:add_line("`````")
end

return M
