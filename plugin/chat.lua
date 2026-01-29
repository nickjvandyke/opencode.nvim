-- Setup global keymaps for chat functionality
local config = require("opencode.config").opts.chat or {}

-- Only setup global keymap if chat is enabled and keymap is configured
if config.enabled and config.keymaps and config.keymaps.open then
  local open_keys = config.keymaps.open

  -- Helper function to set keymaps that might be arrays
  local function set_keymap(keys)
    if type(keys) == "string" then
      vim.keymap.set("n", keys, function()
        require("opencode").chat()
      end, { desc = "Open OpenCode Chat", silent = true })
    elseif type(keys) == "table" then
      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, function()
          require("opencode").chat()
        end, { desc = "Open OpenCode Chat", silent = true })
      end
    end
  end

  set_keymap(open_keys)
end
