---@module 'snacks.picker'

---@class opencode.select.Opts : snacks.picker.ui_select.Opts
---@field prompts? table<string, string> | false Prompts to display. Passed to `prompt()`.
---@field commands? table<opencode.server.Command | string, string> | false Commands to display and their descriptions.
---@field server? table<opencode.select.server.Items, string> | false Server controls to display and their descriptions.

---@alias opencode.select.server.Items
---| 'server.select'
---| 'server.start'

local M = {}

---@param context opencode.context.Context
---@param opts? opencode.select.Opts Override configured options for this call.
---@return Promise<any>
function M.select(context, opts)
  opts = vim.tbl_deep_extend("force", require("opencode.config").opts.select or {}, opts or {})
  local config = require("opencode.config")

  local Promise = require("opencode.promise")

  ---@class opencode.select.Item : snacks.picker.finder.Item, { __type: "prompt" | "command" | "server" }
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

  -- Commands section
  if opts.commands then
    table.insert(items, { __group = true, name = "COMMANDS", preview = { text = "" } })
    local command_items = {}
    for name, description in pairs(opts.commands) do
      table.insert(command_items, {
        __type = "command",
        name = name,
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

  -- Server section
  if opts.server then
    table.insert(items, { __group = true, name = "SERVER", preview = { text = "" } })
    if opts.server["server.select"] then
      table.insert(items, {
        __type = "server",
        name = "server.select",
        text = "Select server",
        highlights = { { "Select server", "Comment" } },
        preview = { text = "" },
      })
    end
    if opts.server["server.start"] and config.opts.server.start then
      table.insert(items, {
        __type = "server",
        name = "server.start",
        text = "Start server",
        highlights = { { "Start configured server", "Comment" } },
        preview = { text = "" },
      })
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

  return require("opencode.promise.ui")
    .select(items, select_opts)
    :next(function(choice)
      if choice.__type == "prompt" then
        return require("opencode.api.prompt").prompt(choice.text, context)
      elseif choice.__type == "command" then
        if choice.name == "session.select" then
          return require("opencode.ui.select_session").select_session(context.server):next(function(session)
            return context.server:select_session(session.id)
          end)
        else
          return require("opencode.api.command").command(choice.name, context.server)
        end
      elseif choice.__type == "server" then
        if choice.name == "server.select" then
          return require("opencode.server.discovery")
            .locally()
            :next(function(servers)
              local configured = require("opencode.server.discovery").configured()
              if configured then
                return configured:next(function(configured_server)
                  if
                    not vim.tbl_contains(servers, function(local_server)
                      return local_server.url == configured_server.url
                    end, { predicate = true })
                  then
                    table.insert(servers, 1, configured_server)
                  end
                  return Promise.resolve(servers)
                end)
              else
                return Promise.resolve(servers)
              end
            end)
            :next(function(servers)
              return require("opencode.ui.select_server").select_server(servers)
            end)
            :next(function(new_server)
              return new_server:connect()
            end)
        elseif choice.name == "server.start" then
          return config.opts.server.start()
        end
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
