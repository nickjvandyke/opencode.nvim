---Main entry point for custom chat frontend
local M = {}

---Start a new chat session with custom UI
---@param opts? { width?: number, height?: number }
function M.start_chat(opts)
  -- Get or start opencode server
  require("opencode.cli.server")
    .get_port(true)
    :next(function(port)
      -- Open chat window
      local chat = require("opencode.ui.chat")
      local state = chat.open(opts)

      -- Store port
      state.port = port

      -- Subscribe to events first
      require("opencode.ui.chat_events").subscribe(port)

      -- Create new session via TUI command
      local client = require("opencode.cli.client")
      client.tui_execute_command("session.new", port, function()
        -- Session will be set via SSE event
      end)

      -- Show welcome message
      vim.schedule(function()
        if chat.get_state() then
          local config = require("opencode.config").opts.chat or {}
          local keymaps = config.keymaps or {}

          -- Format keymaps for display
          local function format_keys(keys)
            if type(keys) == "string" then
              return keys
            elseif type(keys) == "table" then
              return table.concat(keys, "/")
            end
            return "?"
          end

          local send_keys = format_keys(keymaps.send or { "i", "a" })
          local new_session_key = format_keys(keymaps.new_session or "n")
          local close_keys = format_keys(keymaps.close or { "q", "<Esc>" })
          local yank_key = format_keys(keymaps.yank or "yy")
          local interrupt_key = format_keys(keymaps.interrupt or "<C-c>")

          chat.add_message({
            role = "assistant",
            text = string.format(
              "Chat session starting... Type '%s' to send a message.\n\nKeybindings:\n  %s - Send message\n  %s - New session\n  %s - Close\n  %s - Yank message\n  %s - Interrupt",
              send_keys,
              send_keys,
              new_session_key,
              close_keys,
              yank_key,
              interrupt_key
            ),
            streaming = false,
            complete = true,
          })
        end
      end)
    end)
    :catch(function(err)
      vim.notify("Failed to start opencode: " .. err, vim.log.levels.ERROR, { title = "opencode" })
    end)
end

return M
