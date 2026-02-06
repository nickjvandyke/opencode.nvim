local M = {}

function M.select_server()
  return require("opencode.cli.server")
    .select()
    :next(function(server)
      require("opencode.events").subscribe(server)
      return server
    end)
    :catch(function(err)
      vim.notify("Failed to select an `opencode` server: " .. err, vim.log.levels.WARN)
    end)
end

return M
