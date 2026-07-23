vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeReload", { clear = true }),
  pattern = "OpencodeEvent:file.edited",
  callback = function()
    if require("opencode.config").opts.events.reload then
      -- `schedule` because blocking the event loop during rapid SSE influx can drop events
      vim.schedule(function()
        vim.cmd("checktime")
      end)
    end
  end,
  desc = "Reload buffers edited by OpenCode",
})
