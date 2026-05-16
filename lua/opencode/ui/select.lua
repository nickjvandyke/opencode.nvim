---@module 'snacks.picker'

local M = {}

---@class opencode.select.Opts : snacks.picker.ui_select.Opts
---
---Configure the displayed sections.
---@field sections? opencode.select.sections.Opts

---@class opencode.select.sections.Opts
---
---Whether to show the prompts section.
---@field prompts? boolean
---
---Commands to display, and their descriptions.
---Or `false` to hide the commands section.
---@field commands? table<opencode.Command|string, string>|false
---
---@field server? boolean Whether to show server controls.

---Select from all `opencode.nvim` functionality.
---
---@param opts? opencode.select.Opts Override configured options for this call.
---@return Promise
function M.select(opts)
  opts = vim.tbl_deep_extend("force", require("opencode.config").opts.select or {}, opts or {})

  local context = require("opencode.context").new()
  local Promise = require("opencode.promise")

  return require("opencode.server")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      ---@class opencode.select.Item : snacks.picker.finder.Item, { __type: "prompt" | "command" | "server" }
      local items = {}

      -- Prompts section
      if opts.sections.prompts then
        table.insert(items, { __group = true, name = "PROMPT", preview = { text = "" } })
        local prompt_items = {}
        for name, prompt in pairs(prompts) do
          local rendered = context:render(prompt, server.subagents)
          ---@type snacks.picker.finder.Item
          local item = {
            __type = "prompt",
            name = name,
            text = prompt,
            highlights = rendered.input, -- `snacks.picker`'s `select` seems to ignore this, so we incorporate it ourselves in `format_item`
            preview = {
              text = context.plaintext(rendered.output),
              extmarks = context.extmarks(rendered.output),
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
      if type(opts.sections.commands) == "table" then
        table.insert(items, { __group = true, name = "COMMAND", preview = { text = "" } })
        local command_items = {}
        for name, description in pairs(commands) do
          table.insert(command_items, {
            __type = "command",
            name = name, -- TODO: Truncate if it'd run into `text`
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
      if opts.sections.server then
        table.insert(items, { __group = true, name = "SERVER", preview = { text = "" } })
        table.insert(items, {
          __type = "server",
          name = "server.select",
          text = "Select server",
          highlights = { { "Select server", "Comment" } },
          preview = { text = "" },
        })
        table.insert(items, {
          __type = "server",
          name = "server.start",
          text = "Start server",
          highlights = { { "Start server", "Comment" } },
          preview = { text = "" },
        })
        table.insert(items, {
          __type = "server",
          name = "server.stop",
          text = "Stop server",
          highlights = { { "Stop server", "Comment" } },
          preview = { text = "" },
        })
        table.insert(items, {
          __type = "server",
          name = "server.toggle",
          text = "Toggle server",
          highlights = { { "Toggle server", "Comment" } },
          preview = { text = "" },
        })
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

      return Promise.select(items, select_opts)
    end)
    :next(function(choice) ---@param choice opencode.select.Item
      if choice.__type == "prompt" then
        ---@type string
        local prompt = require("opencode.config").opts.prompts[choice.name]
        local ask = prompt:match("%.%.%.$")
        if ask then
          return require("opencode").ask(prompt:gsub("%.%.%.$", ""), { context = context })
        else
          local submit = not prompt:match(" $")
          return require("opencode").prompt(prompt, { context = context, submit = submit })
        end
      elseif choice.__type == "command" then
        if choice.name == "session.select" then
          return require("opencode.ui.select_session").select_session()
        else
          return require("opencode").command(choice.name)
        end
      elseif choice.__type == "server" then
        if choice.name == "server.select" then
          return require("opencode.server")
            .get_all()
            :next(function(servers) ---@param servers opencode.server.Server[]
              return require("opencode.ui.select_server").select_server(servers)
            end)
            :next(function(server) ---@param server opencode.server.Server
              require("opencode.events").connect(server)
              return server
            end)
        elseif choice.name == "server.start" then
          return require("opencode").start()
        elseif choice.name == "server.stop" then
          return require("opencode").stop()
        elseif choice.name == "server.toggle" then
          return require("opencode").toggle()
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
