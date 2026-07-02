---A rendered prompt with placeholders resolved.
---Segments are tuples of (text, highlight_group?).
---Exposes methods to transform to different formats.
---@class opencode.context.rendered.Rendered : opencode.context.rendered.Text[]
local Rendered = {}
Rendered.__index = Rendered

---@class opencode.context.rendered.Text
---@field [1] string Text.
---@field [2]? string Highlight group.

---@class opencode.context.rendered.Extmark vim.api.keyset.set_extmark : { col?: number, row?: number, field?: string }

---@return string
function Rendered:plaintext()
  return table.concat(vim.tbl_map(
    ---@param part opencode.context.rendered.Text
    function(part)
      return part[1]
    end,
    self
  ))
end

---@return opencode.context.rendered.Extmark[]
function Rendered:extmarks()
  local row = 1
  local col = 1
  local extmarks = {}
  for _, part in ipairs(self) do
    local part_text = part[1]
    local part_hl = part[2]
    local segments = vim.split(part_text, "\n", { plain = true })
    for i, segment in ipairs(segments) do
      if i > 1 then
        row = row + 1
        col = 1
      end
      if part_hl then
        table.insert(extmarks, {
          row = row,
          col = col - 1,
          end_col = col + #segment - 1,
          hl_group = part_hl,
        })
      end
      col = col + #segment
    end
  end
  return extmarks
end

---Transforms to `:help input()-highlight` format.
---@return { [1]: integer, [2]: integer, [3]: string }[]
function Rendered:input_highlight()
  return vim.tbl_map(function(extmark)
    return { extmark.col, extmark.end_col, extmark.hl_group }
  end, self:extmarks())
end

return Rendered
