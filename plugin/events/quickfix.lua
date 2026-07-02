vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:*", -- TODO: Should we narrow this? I like the general solution to check properties.file though.
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    ---@type opencode.server.Event
    local event = args.data.event
    require("opencode.events.quickfix").add(event)
  end,
  desc = "Add files used by OpenCode to a quickfix list",
})

-- TODO: Actually test with OpenCode
-- TODO: Remove
vim.api.nvim_create_user_command("OpencodeEdited1", function()
  ---@type opencode.server.Event
  local event = {
    type = "file.edited",
    properties = {
      file = "lua/opencode.lua",
    },
  }
  vim.api.nvim_exec_autocmds("User", {
    pattern = "OpencodeEvent:" .. event.type,
    data = {
      event = event,
    },
  })
end, {})

vim.api.nvim_create_user_command("OpencodeEdited2", function()
  ---@type opencode.server.Event
  local event = {
    type = "file.edited",
    properties = {
      file = "lua/opencode/config.lua",
    },
  }
  vim.api.nvim_exec_autocmds("User", {
    pattern = "OpencodeEvent:" .. event.type,
    data = {
      event = event,
    },
  })
end, {})

vim.api.nvim_create_user_command("OpencodeRead1", function()
  ---@type opencode.server.Event
  local event = {
    type = "file.read",
    properties = {
      file = "lua/opencode.lua",
    },
  }
  vim.api.nvim_exec_autocmds("User", {
    pattern = "OpencodeEvent:" .. event.type,
    data = {
      event = event,
    },
  })
end, {})

vim.api.nvim_create_user_command("OpencodeRead2", function()
  ---@type opencode.server.Event
  local event = {
    type = "file.read",
    properties = {
      file = "lua/opencode/config.lua",
    },
  }
  vim.api.nvim_exec_autocmds("User", {
    pattern = "OpencodeEvent:" .. event.type,
    data = {
      event = event,
    },
  })
end, {})
