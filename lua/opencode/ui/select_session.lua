local M = {}

local function ellipsize(s, max_len)
  if vim.fn.strdisplaywidth(s) <= max_len then
    return s
  end
  local truncated = vim.fn.strcharpart(s, 0, max_len - 3)
  truncated = truncated:gsub("%s+%S*$", "")

  return truncated .. "..."
end

function M.select_session()
  require("opencode.cli.server")
    .get()
    :next(function(server) ---@param server opencode.cli.server.Server
      return server.port
    end)
    :next(function(port) ---@param port number
      return require("opencode.promise").new(function(resolve)
        require("opencode.cli.client").get_sessions(port, function(sessions)
          resolve({ sessions = sessions, port = port })
        end)
      end)
    end)
    :next(function(session_data) ---@param session_data {sessions: opencode.cli.client.Session[], port: number}
      local sessions = session_data.sessions
      table.sort(sessions, function(a, b)
        return a.time.updated > b.time.updated
      end)

      vim.ui.select(sessions, {
        prompt = "Select session (recently updated first):",
        format_item = function(item)
          local title_length = 60
          local updated = os.date("%b %d, %Y %H:%M:%S", item.time.updated / 1000)
          local title = ellipsize(item.title, title_length)
          return ("%s%s%s"):format(title, string.rep(" ", title_length - #title), updated)
        end,
      }, function(choice) ---@param choice? opencode.cli.client.Session
        if choice then
          require("opencode.cli.client").select_session(session_data.port, choice.id)
        end
      end)
    end)
    :catch(function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
end

return M
