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

---Select from all `opencode.nvim` functionality.
---
--- - Prompts
--- - Commands
---   - Fetches custom commands from `opencode`
--- - Provider controls
---
--- Highlights and previews items when using `snacks.picker`.
---
---@param opts? opencode.select.Opts Override configured options for this call.
function M.select(opts)
  opts = vim.tbl_deep_extend("force", require("opencode.config").opts.select or {}, opts or {})
  if not require("opencode.config").provider then
    opts.sections.provider = false
  end

  -- TODO: Should merge with prompts' optional contexts
  local context = require("opencode.context").new()

  require("opencode.cli.server")
    .get_port()
    :next(function(port)
      if opts.sections.prompts then
        return require("opencode.promise").new(function(resolve)
          require("opencode.cli.client").get_agents(port, function(agents)
            context.agents = vim.tbl_filter(function(agent)
              return agent.mode == "subagent"
            end, agents)

            resolve(port)
          end)
        end)
      else
        return port
      end
    end)
    :next(function(port)
      if opts.sections.commands then
        return require("opencode.promise").new(function(resolve)
          require("opencode.cli.client").get_commands(port, function(custom_commands)
            resolve(custom_commands)
          end)
        end)
      else
        return {}
      end
    end)
    :next(function(custom_commands)
      local prompts = require("opencode.config").opts.prompts or {}
      local commands = require("opencode.config").opts.select.sections.commands or {}
      for _, command in ipairs(custom_commands) do
        commands[command.name] = command.description
      end

      ---@type snacks.picker.finder.Item[]
      local items = {}

      -- Prompts section
      if opts.sections.prompts then
        table.insert(items, { __group = true, name = "PROMPT", preview = { text = "" } })
        local prompt_items = {}
        for name, prompt in pairs(prompts) do
          local rendered = context:render(prompt.prompt)
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
            local formatted = vim.deepcopy(item.highlights)
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

      vim.ui.select(items, select_opts, function(choice)
        if not choice then
          context:resume()
          return
        else
          context:clear()
        end

        if choice.__type == "prompt" then
          ---@type opencode.Prompt
          local prompt = require("opencode.config").opts.prompts[choice.name]
          prompt.context = context
          if prompt.ask then
            require("opencode").ask(prompt.prompt, prompt)
          else
            require("opencode").prompt(prompt.prompt, prompt)
          end
        elseif choice.__type == "command" then
          if choice.name == "session.select" then
            require("opencode").select_session()
          else
            require("opencode").command(choice.name)
          end
        elseif choice.__type == "provider" then
          if choice.name == "toggle" then
            require("opencode").toggle()
          elseif choice.name == "start" then
            require("opencode").start()
          elseif choice.name == "stop" then
            require("opencode").stop()
          end
        end
      end)
    end)
    :catch(function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
end

return M
