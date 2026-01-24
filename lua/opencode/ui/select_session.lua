local M = {}

function M.select_session()
  require("opencode.cli.server")
    .get_port()
    :next(function(port)
      return require("opencode.promise").new(function(resolve)
        require("opencode.cli.client").get_sessions(port, function(sessions)
          resolve({ sessions = sessions, port = port })
        end)
      end)
    end)
    :next(function(session_data)
      local sessions = {}
      for _, session in ipairs(session_data.sessions) do
        ---@type opencode.cli.client.Session
        local item = {
          id = session.id,
          title = session.title,
          time = {
            created = session.time.created,
            updated = session.time.updated,
          },
        }
        table.insert(sessions, item)
      end

      table.sort(sessions, function(a, b)
        return a.time.updated > b.time.updated
      end)

      vim.ui.select(sessions, {
        prompt = "Select session (recently updated first):",
        format_item = function(item)
          local title_length = 60
          local updated = os.date("%b %d, %Y %H:%M:%S", item.time.updated / 1000)
          local title = M.ellipsize(item.title, title_length)
          return ("%s%s%s"):format(title, string.rep(" ", title_length - #title), updated)
        end,
      }, function(choice)
        if choice then
          require("opencode.cli.client").select_session(session_data.port, choice.id)
        end
      end)
    end)
    :catch(function(err)
      vim.notify(err, vim.log.levels.ERROR)
    end)
end

function M.ellipsize(s, max_len)
  if vim.fn.strdisplaywidth(s) <= max_len then
    return s
  end
  local truncated = vim.fn.strcharpart(s, 0, max_len - 3)
  truncated = truncated:gsub("%s+%S*$", "")

  return truncated .. "..."
end

return M
