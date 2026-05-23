local QUICKFIX_LIST_TITLE = "OpenCode edits"

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

    local qf_lists = vim.fn.getqflist({ all = 1 })
    local target_qf_list_nr
    if type(qf_lists.nr) == "table" then
      for _, nr in ipairs(qf_lists.nr) do
        if vim.fn.getqflist({ nr = nr, title = 0 }).title == QUICKFIX_LIST_TITLE then
          target_qf_list_nr = nr
          break
        end
      end
    end

    local new_item = { filename = file, type = "I" }
    if target_qf_list_nr then
      local existing_qf_list = vim.fn.getqflist({ nr = target_qf_list_nr, items = 0 })
      local item_already_exists = vim.iter(existing_qf_list.items):any(function(i)
        return i.filename == new_item.filename
      end)
      if not item_already_exists then
        table.insert(existing_qf_list.items, new_item)
        vim.fn.setqflist({}, " ", { nr = target_qf_list_nr, items = existing_qf_list.items })
      end
    else
      vim.fn.setqflist({}, " ", { title = QUICKFIX_LIST_TITLE, items = { new_item } })
    end

    vim.cmd.copen()
  end,
  desc = "Track files edited by OpenCode in a quickfix list",
})
