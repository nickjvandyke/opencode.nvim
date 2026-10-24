local live_context = vim.g.opencode_opts and vim.g.opencode_opts.live_context

local function start(opts)
  local ok, result = require("opencode").start_live_context(opts)
  if ok then
    vim.notify("OpenCode live context started on port " .. result, vim.log.levels.INFO, { title = "OpenCode" })
  else
    vim.notify("Failed to start live context: " .. result, vim.log.levels.ERROR, { title = "OpenCode" })
  end
end

vim.api.nvim_create_user_command("OpenCodeLiveContextStart", function()
  start()
end, { desc = "Start OpenCode live context WebSocket server" })

vim.api.nvim_create_user_command("OpenCodeLiveContextStop", function()
  require("opencode").stop_live_context()
  vim.notify("OpenCode live context stopped", vim.log.levels.INFO, { title = "OpenCode" })
end, { desc = "Stop OpenCode live context WebSocket server" })

vim.api.nvim_create_user_command("OpenCodeAttach", function(opts)
  require("opencode").attach_context(opts.range > 0 and opts.line1 or nil, opts.range > 0 and opts.line2 or nil)
end, { range = true, desc = "Attach visual selection to OpenCode context (no submit)" })

if live_context and live_context.enabled then
  vim.schedule(function()
    if not require("opencode.server.websocket").is_running() then
      start(live_context)
    end
  end)
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("OpenCodeLiveContextShutdown", { clear = true }),
  callback = function()
    if require("opencode.server.websocket").is_running() then
      require("opencode").stop_live_context()
    end
  end,
  desc = "Stop OpenCode live context and remove its lockfile",
})
