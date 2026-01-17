local M = {}

local Output = require("opencode.ui.output")
local formatter = require("opencode.ui.formatter")
local output_window = require("opencode.ui.output_window")
local util = require("opencode.util")

---Format diff content with proper syntax highlighting
---@param content string The diff content
---@param file_type string The file type for syntax highlighting
---@return Output
local function format_diff_content(content, file_type)
  local output = Output.new()

  -- Format the diff with proper syntax highlighting
  formatter._format_diff(output, content, file_type)

  return output
end

---Render formatted data to a buffer
---@param bufid integer Buffer ID
---@param output Output
local function render_to_buffer(bufid, output)
  -- Set lines
  output_window.set_lines(bufid, output.lines, 0, -1)

  -- Apply extmarks for syntax highlighting
  local extmarks = output.extmarks
  if extmarks then
    output_window.set_extmarks(bufid, extmarks, 0)
  end
end

---@param event table
---@param on_choice? fun(choice?: string)
function M.confirm(event, on_choice)
  local title = "Permit opencode to: "
    .. event.properties.permission
    .. " "
    .. table.concat(event.properties.patterns, ", ")
    .. "?"
  local content = event.properties.metadata.diff
  local file_type = util.get_markdown_filetype(event.properties.metadata.filepath or event.properties.patterns[1])
  content = format_diff_content(content, file_type)
  M._confirm(title, content, file_type, on_choice)
end

---@param title string
---@param content string|Output
---@param file_type string
---@param on_choice? fun(choice?: string)
function M._confirm(title, content, file_type, on_choice)
  -- Format the diff content with syntax highlighting

  local output = content
  if type(content) == "string" then
    output = Output.new()
    output:add_line("`````" .. file_type)
    output:add_lines(vim.split(content, "\n", { plain = true }))
    output:add_line("`````")
  end

  local win_config = require("opencode.config").opts.events.permissions.confirm.window.config
  if type(win_config) == "function" then
    win_config = win_config()
  end
  local win_options = require("opencode.config").opts.events.permissions.confirm.window.options

  -- Build dynamic footer from mappings
  local mappings = require("opencode.config").opts.events.permissions.confirm.window.mappings
  local footer = {}
  local seen_actions = {}
  for key, action in pairs(mappings) do
    if type(action) == "string" and action ~= "close" then
      local action_lower = action:lower()
      if not seen_actions[action_lower] then
        seen_actions[action_lower] = {}
        table.insert(seen_actions[action_lower], key)
      else
        table.insert(seen_actions[action_lower], key)
      end
    end
  end

  -- Sort actions in desired order and build footer
  local action_order = { "once", "always", "reject" }
  for _, action in ipairs(action_order) do
    if seen_actions[action] then
      -- Sort keys to ensure consistent display order
      table.sort(seen_actions[action])
      local keys = table.concat(seen_actions[action], "/")
      table.insert(footer, { " " .. keys .. " ", "Title" })
      table.insert(footer, { "- " .. action:sub(1, 1):upper() .. action:sub(2) .. "  ", "Comment" })
    end
  end

  local bufid, winid = util.create_scratch_floatwin(
    title,
    vim.tbl_deep_extend("force", {
      footer = footer,
      footer_pos = "center",
    }, win_config)
  )

  ---@cast output Output
  render_to_buffer(bufid, output)

  vim.bo.modifiable = false
  -- Set filetype to enable syntax highlighting
  vim.bo.filetype = "markdown"

  for option, value in pairs(win_options) do
    vim.api.nvim_set_option_value(option, value, { scope = "local", win = winid })
  end

  local done = false

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufid,
    callback = function()
      if not done then
        if on_choice then
          on_choice()
        end
      end
    end,
  })

  local function finish(choice)
    if on_choice then
      on_choice(choice)
    end
    done = true
    vim.api.nvim_win_close(winid, false)
  end

  local function close_window()
    done = true
    vim.api.nvim_win_close(winid, false)
  end

  for key, action in pairs(mappings) do
    if type(action) == "string" then
      local action_lower = action:lower()
      if action_lower == "close" then
        -- Close window without calling callback
        vim.keymap.set("n", key, close_window, { buffer = bufid, remap = false, nowait = true })
      else
        -- Pass the action (once/always/reject) to the callback
        vim.keymap.set("n", key, function()
          finish(action_lower)
        end, { buffer = bufid, remap = false, nowait = true })
      end
    end
  end
end

return M
