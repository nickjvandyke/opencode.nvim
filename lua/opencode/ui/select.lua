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
---Whether to show the provider section.
---Always `false` if no provider is available.
---@field provider? boolean
---
---@field server? boolean Whether to show server controls.

---Select from all `opencode.nvim` functionality.
---
---@param opts? opencode.select.Opts Override configured options for this call.
---@return Promise
function M.select(opts)
  opts = vim.tbl_deep_extend("force", require("opencode.config").opts.select or {}, opts or {})
  if not require("opencode.config").provider then
    opts.sections.provider = false
  end

  -- TODO: Should merge with prompts' optional contexts
  local context = require("opencode.context").new()
  local Promise = require("opencode.promise")

  return require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      if opts.sections.commands then
        return Promise.new(function(resolve)
          require("opencode.cli.client").get_commands(server.port, function(custom_commands)
            resolve({ server = server, custom_commands = custom_commands })
          end)
        end)
      else
        return { server = server }
      end
    end)
    :next(
      function(result) ---@param result { server: opencode.cli.server.Server, custom_commands: opencode.cli.client.Command[]}
        local prompts = require("opencode.config").opts.prompts or {}
        local commands = require("opencode.config").opts.select.sections.commands or {}
        for _, command in ipairs(result.custom_commands) do
          commands[command.name] = command.description
        end

        ---@class opencode.select.Item : snacks.picker.finder.Item, { __type: "prompt" | "command" | "provider", ask?: boolean, submit?: boolean }

        ---@type opencode.select.Item[]
        local items = {}

        -- Prompts section
        if opts.sections.prompts then
          table.insert(items, { __group = true, name = "PROMPT", preview = { text = "" } })
          local prompt_items = {}
          for name, prompt in pairs(prompts) do
            local rendered = context:render(prompt.prompt, result.server.subagents)
            ---@type snacks.picker.finder.Item
            local item = {
              __type = "prompt",
              name = name,
              text = prompt.prompt .. (prompt.ask and "…" or ""),
              highlights = rendered.input, -- `snacks.picker`'s `select` seems to ignore this, so we incorporate it ourselves in `format_item`
              preview = {
                text = context.plaintext(rendered.output),
                extmarks = context.extmarks(rendered.output),
              },
              ask = prompt.ask,
              submit = prompt.submit,
            }
            table.insert(prompt_items, item)
          end
          -- Sort: ask=true, submit=false, name
          table.sort(prompt_items, function(a, b)
            if a.ask and not b.ask then
              return true
            elseif not a.ask and b.ask then
              return false
            elseif not a.submit and b.submit then
              return true
            elseif a.submit and not b.submit then
              return false
            else
              return a.name < b.name
            end
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

        -- Provider section
        if opts.sections.provider then
          table.insert(items, { __group = true, name = "PROVIDER", preview = { text = "" } })
          table.insert(items, {
            __type = "provider",
            name = "toggle",
            text = "Toggle opencode",
            highlights = { { "Toggle opencode", "Comment" } },
            preview = { text = "" },
          })
          table.insert(items, {
            __type = "provider",
            name = "start",
            text = "Start opencode",
            highlights = { { "Start opencode", "Comment" } },
            preview = { text = "" },
          })
          table.insert(items, {
            __type = "provider",
            name = "stop",
            text = "Stop opencode",
            highlights = { { "Stop opencode", "Comment" } },
            preview = { text = "" },
          })
        end

        -- Server section
        if opts.sections.server then
          table.insert(items, { __group = true, name = "SERVER", preview = { text = "" } })
          table.insert(items, {
            __type = "server",
            name = "select",
            text = "Select server",
            highlights = { { "Select server", "Comment" } },
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
              if item.ask then
                table.insert(formatted, { "…", "Keyword" })
              end
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
      end
    )
    :next(function(choice) ---@param choice opencode.select.Item
      if choice.__type == "prompt" then
        ---@type opencode.Prompt
        local prompt = require("opencode.config").opts.prompts[choice.name]
        prompt.context = context
        if prompt.ask then
          return require("opencode").ask(prompt.prompt, prompt)
        else
          return require("opencode").prompt(prompt.prompt, prompt)
        end
      elseif choice.__type == "command" then
        if choice.name == "session.select" then
          return require("opencode").select_session()
        else
          return require("opencode").command(choice.name)
        end
      elseif choice.__type == "provider" then
        if choice.name == "toggle" then
          require("opencode").toggle()
        elseif choice.name == "start" then
          require("opencode").start()
        elseif choice.name == "stop" then
          require("opencode").stop()
        end
      elseif choice.__type == "server" then
        if choice.name == "select" then
          return require("opencode").select_server()
        end
      end
    end)
    :catch(function(err)
      context:resume()
      return Promise.reject(err)
    end)
end

return M
