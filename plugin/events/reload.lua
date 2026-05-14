vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeReload", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function()
    if require("opencode.config").opts.events.reload then
      if not vim.o.autoread then
        -- Unfortunately `autoread` is kinda necessary, for `:checktime`.
        -- Alternatively we could `:edit!` but that would lose any unsaved changes.
        vim.notify(
          "Please set `vim.o.autoread = true` to use `opencode.nvim` auto-reload",
          vim.log.levels.WARN,
          { title = "opencode" }
        )
      else
        -- `schedule` because blocking the event loop during rapid SSE influx can drop events
        vim.schedule(function()
          -- `:checktime` checks all buffers - no need to check the event's file
          vim.cmd("checktime")
        end)
      end
    end
  end,
  desc = "Reload buffers edited by opencode",
})
