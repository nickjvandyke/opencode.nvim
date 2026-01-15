local Output = {}
Output.__index = Output

---@alias OutputExtmarkType vim.api.keyset.set_extmark & {start_col:0}
---@alias OutputExtmark OutputExtmarkType|fun():OutputExtmarkType

---@class OutputAction
---@field text string Action text
---@field type 'diff_revert_all'|'diff_revert_selected_file'|'diff_open'|'diff_restore_snapshot_file'|'diff_restore_snapshot_all'|'select_child_session' Type of action
---@field args? string[] Optional arguments for the command
---@field key string keybinding for the action
---@field display_line number Line number to display the action
---@field range? { from: number, to: number } Optional range for the action

---@class Output
---@field lines string[]
---@field extmarks table<number, OutputExtmark[]>
---@field actions OutputAction[]
---@field add_line fun(self: Output, line: string, fit?: boolean): number
---@field get_line fun(self: Output, idx: number): string?
---@field merge_line fun(self: Output, idx: number, text: string)
---@field add_lines fun(self: Output, lines: string[], prefix?: string)
---@field add_empty_line fun(self: Output): number?
---@field clear fun(self: Output)
---@field get_line_count fun(self: Output): number
---@field get_lines fun(self: Output): string[]
---@field add_extmark fun(self: Output, idx: number, extmark: OutputExtmark|fun(): OutputExtmark)
---@field get_extmarks fun(self: Output): table<number, table[]>
---@field add_actions fun(self: Output, actions: OutputAction[])
---@field add_action fun(self: Output, action: OutputAction)
---@field get_actions_for_line fun(self: Output, line: number): OutputAction[]?
---@return self Output
function Output.new()
  local self = setmetatable({}, Output)
  self.lines = {}
  self.extmarks = {}
  self.actions = {}
  return self
end

---Add a new line
---@param line string
---@return number index The index of the added line
function Output:add_line(line)
  table.insert(self.lines, line)
  return #self.lines
end

---Get line by index
---@param idx number
---@return string?
function Output:get_line(idx)
  return self.lines[idx]
end

---Merge text into an existing line
---@param idx number
---@param text string
function Output:merge_line(idx, text)
  if self.lines[idx] then
    self.lines[idx] = self.lines[idx] .. text
  end
end

---Add multiple lines
---@param lines string[]
---@param prefix? string Optional prefix for each line
function Output:add_lines(lines, prefix)
  for _, line in ipairs(lines) do
    if line == "" then
      table.insert(self.lines, "")
    else
      prefix = prefix or ""
      table.insert(self.lines, prefix .. line)
    end
  end
end

---Add an empty line if the last line is not empty
---@return number? index The index of the added line, or nil if no line was added
function Output:add_empty_line()
  local line_count = #self.lines
  if line_count == 0 or self.lines[line_count] ~= "" then
    table.insert(self.lines, "")
    return line_count + 1
  end
  return nil
end

---Clear all lines, extmarks, and actions
function Output:clear()
  self.lines = {}
  self.extmarks = {}
  self.actions = {}
end

---Get the number of lines
---@return number
function Output:get_line_count()
  return #self.lines
end

---Get all lines as a table
---@return string[]
function Output:get_lines()
  return vim.deepcopy(self.lines)
end

---Add an extmark for a specific line
---@param idx number The line index
---@param extmark OutputExtmark|fun(): OutputExtmark  The extmark data or a function returning it
function Output:add_extmark(idx, extmark)
  if not self.extmarks[idx] then
    self.extmarks[idx] = {}
  end
  table.insert(self.extmarks[idx], extmark)
end

---Get all extmarks
---@return table<number, table[]>
function Output:get_extmarks()
  return vim.deepcopy(self.extmarks)
end

---Add contextual actions
---@param actions OutputAction[] The actions to add
function Output:add_actions(actions)
  for _, action in ipairs(actions) do
    table.insert(self.actions, action)
  end
end

---Add contextual action
---@param action OutputAction The actions to add
function Output:add_action(action)
  if not action.display_line then
    action.display_line = #self.lines - 1
  end
  if not action.range then
    action.range = { from = #self.lines, to = #self.lines }
  end
  table.insert(self.actions, action)
end

---Get actions for a line matching a range
---@param line number The line index to check
---@return OutputAction[]|nil
function Output:get_actions_for_line(line)
  local actions = {}
  for _, action in pairs(self.actions) do
    if not action.range then
      if line == action.display_line then
        table.insert(actions, vim.deepcopy(action))
      end
    elseif action.range then
      if line >= action.range.from and line <= action.range.to then
        table.insert(actions, vim.deepcopy(action))
      end
    end
  end
  return #actions > 0 and actions or nil
end

return Output
