local M = {}

local QUICKFIX_LIST_TITLE = "OpenCode"

---Our quickfix list ID.
---I don't think we have to verify it still exists before modifying it?
---I don't see a way to possibly "delete" a quickfix list in Neovim.
---@type number?
local qf_list_id = nil

---@param event opencode.server.Event
function M.add(event)
  if event.type == "message.part.updated" then
    vim.print(event)
  end
  ---@type string?
  local file
  if event.type == "file.edited" then
    file = event.properties.file
  elseif event.type == "message.part.updated" and event.properties.part.tool == "read" then
    -- TODO: Not hitting the condition?? Maybe it's not always in a message part update? message.new or similar?
    file = event.properties.part.state.title
  else
    return
  end

  if not qf_list_id then
    vim.fn.setqflist({}, " ", { title = QUICKFIX_LIST_TITLE })
    qf_list_id = vim.fn.getqflist({ id = 0 }).id

    -- Only open qflist upon creation; otherwise let the user do their thing
    -- TODO: Allow configuration of that? It's good for discovery but might be annoying after that.
    local prev_win = vim.api.nvim_get_current_win()
    vim.cmd.copen()
    vim.api.nvim_set_current_win(prev_win)
  end

  ---@type vim.quickfix.entry[]
  local existing_items = vim.fn.getqflist({ id = qf_list_id, items = 0 }).items

  local buf = vim.fn.bufnr(file)
  ---@type vim.quickfix.entry
  local new_item = {
    filename = file,
    bufnr = buf > 0 and buf or nil,
    text = event.type,
    type = "I",
    -- Would love to have line/col... but OpenCode only includes the file
    -- TODO: Check if that holds for all events with a file?
  }

  local item_already_exists = vim.iter(existing_items):any(function(i) ---@param i vim.quickfix.entry
    return (i.filename == new_item.filename or i.bufnr == new_item.bufnr) and i.text == new_item.text
  end)
  if item_already_exists then
    return
  end

  table.insert(existing_items, new_item)
  vim.fn.setqflist({}, "u", { id = qf_list_id, items = existing_items })
end

return M

--[[
--{ "event", {
    id = "evt_f37bd5aec001No0e9Uh5sSNbz6",
    properties = {
      part = {
        callID = "call_00_6hZZRYz4hnP1gCxsfn4x6455",
        id = "prt_f37bd5a37001UsA84nGwSKi9YB",
        messageID = "msg_f37bd52c5002CmUSDU67WNFy1Z",
        sessionID = "ses_0c843539bffeyb9BfxFoaR9Gj9",
        state = {
          input = {
            filePath = "/Users/nvandyke/dev/opencode.nvim/plugin/events/reload.lua"
          },
          metadata = {
            display = {
              lineEnd = 26,
              lineStart = 1,
              path = "/Users/nvandyke/dev/opencode.nvim/plugin/events/reload.lua",
              text = "vim.api.nvim_create_autocmd(\"User\", {\n  group = vim.api.nvim_create_augroup(\"OpencodeReload\", { clear = true }),\n  pattern = \"OpencodeEvent:file.edited\",\n  callback = function()\n    if not require(\"opencode.config\").opts.events.reload then\n      return\n    end\n\n    if not vim.o.autoread then\n      -- Unfortunately `autoread` is kinda necessary, for `:checktime`.\n      -- Alternatively we could `:edit!` but that would lose any unsaved changes.\n      vim.notify(\n        \"Please set `vim.o.autoread = true` to use `opencode.nvim` auto-reload\",\n        vim.log.levels.WARN,\n        { title = \"opencode\" }\n      )\n    else\n      -- `schedule` because blocking the event loop during rapid SSE influx can drop events\n      vim.schedule(function()\n        -- `:checktime` checks all buffers - no need to check the event's file\n        vim.cmd(\"checktime\")\n      end)\n    end\n  end,\n  desc = \"Reload buffers edited by OpenCode\",\n})",
              totalLines = 26,
              truncated = false,
              type = "file"
            },
            loaded = {},
            preview = "vim.api.nvim_create_autocmd(\"User\", {\n  group = vim.api.nvim_create_augroup(\"OpencodeReload\", { clear = true }),\n  pattern = \"OpencodeEvent:file.edited\",\n  callback = function()\n    if not require(\"opencode.config\").opts.events.reload then\n      return\n    end\n\n    if not vim.o.autoread then\n      -- Unfortunately `autoread` is kinda necessary, for `:checktime`.\n      -- Alternatively we could `:edit!` but that would lose any unsaved changes.\n      vim.notify(\n        \"Please set `vim.o.autoread = true` to use `opencode.nvim` auto-reload\",\n        vim.log.levels.WARN,\n        { title = \"opencode\" }\n      )\n    else\n      -- `schedule` because blocking the event loop during rapid SSE influx can drop events\n      vim.schedule(function()\n        -- `:checktime` checks all buffers - no need to check the event's file",
            truncated = false
          },
          output = "<path>/Users/nvandyke/dev/opencode.nvim/plugin/events/reload.lua</path>\n<type>file</type>\n<content>\n1: vim.api.nvim_create_autocmd(\"User\", {\n2:   group = vim.api.nvim_create_augroup(\"OpencodeReload\", { clear = true }),\n3:   pattern = \"OpencodeEvent:file.edited\",\n4:   callback = function()\n5:     if not require(\"opencode.config\").opts.events.reload then\n6:       return\n7:     end\n8: \n9:     if not vim.o.autoread then\n10:       -- Unfortunately `autoread` is kinda necessary, for `:checktime`.\n11:       -- Alternatively we could `:edit!` but that would lose any unsaved changes.\n12:       vim.notify(\n13:         \"Please set `vim.o.autoread = true` to use `opencode.nvim` auto-reload\",\n14:         vim.log.levels.WARN,\n15:         { title = \"opencode\" }\n16:       )\n17:     else\n18:       -- `schedule` because blocking the event loop during rapid SSE influx can drop events\n19:       vim.schedule(function()\n20:         -- `:checktime` checks all buffers - no need to check the event's file\n21:         vim.cmd(\"checktime\")\n22:       end)\n23:     end\n24:   end,\n25:   desc = \"Reload buffers edited by OpenCode\",\n26: })\n\n(End of file - total 26 lines)\n</content>",
          status = "completed",
          time = {
            ["end"] = 1783346584300,
            start = 1783346584295
          },
          title = "plugin/events/reload.lua"
        },
        tool = "read",
        type = "tool"
      },
      sessionID = "ses_0c843539bffeyb9BfxFoaR9Gj9",
      time = 1783346584300
    },
    type = "message.part.updated"
  } }
--]]
