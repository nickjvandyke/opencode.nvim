local QUICKFIX_LIST_TITLE = "OpenCode edits"
local qf_list_nr

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeQuickfix", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function(args)
    if not require("opencode.config").opts.events.quickfix then
      return
    end

    ---@type opencode.server.event.FileEdited
    local event = args.data.event
    local file = event.properties.file

    if qf_list_nr then
      local existing = vim.fn.getqflist({ nr = qf_list_nr, items = 0 })
      if existing.nr ~= qf_list_nr then
        qf_list_nr = nil
      end
    end

    if not qf_list_nr then
      vim.fn.setqflist({}, " ", { title = QUICKFIX_LIST_TITLE })
      qf_list_nr = vim.fn.getqflist({ nr = 0 }).nr
    end

    local new_item = { filename = file, bufnr = vim.fn.bufnr(file), type = "I" }
    local existing = vim.fn.getqflist({ nr = qf_list_nr, items = 0 })
    local item_already_exists = vim.iter(existing.items):any(function(i)
      return i.filename == new_item.filename or i.bufnr == new_item.bufnr
    end)

    if not item_already_exists then
      -- TODO: Need to focus/set to this list
      vim.fn.setqflist({ new_item }, "a")
    end

    vim.cmd.copen()
  end,
  desc = "Add files edited by OpenCode to a quickfix list",
})
