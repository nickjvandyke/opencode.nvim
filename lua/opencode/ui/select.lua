---@module 'snacks.picker'

---@class opencode.select.Opts : snacks.picker.ui_select.Opts
---@field prompts? table<string, string> | false Prompts to display. Passed to `prompt()`.
---@field commands? boolean Whether to display OpenCode's registered commands. Defaults to `true`.

local M = {}

---@param context opencode.context.Context
---@param opts? opencode.select.Opts Override configured options for this call.
---@return Promise<any>
function M.select(context, opts)
  opts = vim.tbl_deep_extend("force", require("opencode.config").opts.select or {}, opts or {})

  local Promise = require("opencode.promise")

  ---@class opencode.select.Item : snacks.picker.finder.Item, { __type: "prompt" | "command" }
  local items = {}

  -- Prompts section
  if opts.prompts then
    table.insert(items, { __group = true, name = "PROMPTS", preview = { text = "" } })
    local prompt_items = {}
    for name, prompt in pairs(opts.prompts) do
      local rendered = context:render(prompt)
      ---@type snacks.picker.finder.Item
      local item = {
        __type = "prompt",
        name = name,
        text = prompt,
        highlights = rendered.input, -- `snacks.picker`'s `select` seems to ignore this, so we incorporate it ourselves in `format_item`
        preview = {
          text = rendered.output:plaintext(),
          extmarks = rendered.output:extmarks(),
        },
      }
      table.insert(prompt_items, item)
    end
    table.sort(prompt_items, function(a, b)
      return a.name < b.name
    end)
    for _, item in ipairs(prompt_items) do
      table.insert(items, item)
    end
  end

  -- Commands section: registered on the server, so it may include user-defined commands.
  local commands = opts.commands == false and Promise.resolve({})
    or context.server:get_commands():catch(function()
      return Promise.resolve({})
    end)

  return commands
    :next(function(registered)
      if opts.commands ~= false and #registered > 0 then
        table.insert(items, { __group = true, name = "COMMANDS", preview = { text = "" } })
        local command_items = {}
        for _, command in ipairs(registered) do
          local description = command.description or ""
          table.insert(command_items, {
            __type = "command",
            name = command.name,
            text = description,
            highlights = { { description, "Comment" } },
            preview = {
              text = "",
            },
          })
        end
        table.sort(command_items, function(a, b)
          return a.name < b.name
        end)
        for _, item in ipairs(command_items) do
          table.insert(items, item)
        end
      end

      for i, item in ipairs(items) do
        item.idx = i -- Store the index for non-snacks formatting
      end

      ---@type snacks.picker.ui_select.Opts
      local select_opts = {
        ---@param item snacks.picker.finder.Item
        ---@param is_snacks boolean
        format_item = function(item, is_snacks)
          if is_snacks then
            if item.__group then
              return { { item.name, "Title" } }
            end
            local formatted = vim.deepcopy(item.highlights or {})
            table.insert(formatted, 1, { item.name, "Keyword" })
            table.insert(formatted, 2, { string.rep(" ", 18 - #item.name) })
            return formatted
          else
            local indent = #tostring(#items) - #tostring(item.idx)
            if item.__group then
              local divider = string.rep("—", (80 - #item.name) / 2)
              return string.rep(" ", indent) .. divider .. item.name .. divider
            end
            return ("%s[%s]%s%s"):format(
              string.rep(" ", indent),
              item.name,
              string.rep(" ", 18 - #item.name),
              item.text or ""
            )
          end
        end,
      }
      select_opts = vim.tbl_deep_extend("force", select_opts, opts)

      return require("opencode.promise.ui").select(items, select_opts)
    end)
    :next(function(choice)
      if choice.__type == "prompt" then
        return require("opencode.api.prompt").prompt(choice.text, context)
      elseif choice.__type == "command" then
        -- Commands may take arguments, but the API doesn't expose whether they do,
        -- so always prompt (the command runs with its default when left blank).
        return require("opencode.promise.ui")
          .input({ prompt = "Arguments for /" .. choice.name .. " (optional): ", default = "" })
          :next(function(args)
            return require("opencode.api.command").command(choice.name, args, context.server)
          end)
      else
        return Promise.reject("Unknown item: " .. choice.name)
      end
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

return M
