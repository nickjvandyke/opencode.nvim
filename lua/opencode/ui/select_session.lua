local M = {}

local function ellipsize(s, max_len)
  if vim.fn.strdisplaywidth(s) <= max_len then
    return s
  end
  local truncated = vim.fn.strcharpart(s, 0, max_len - 3)
  truncated = truncated:gsub("%s+%S*$", "")

  return truncated .. "..."
end

---@return Promise<{ session: opencode.server.Session, server: opencode.server.Server }>
function M.select_session()
  return require("opencode.server.discovery")
    .get()
    :next(function(server) ---@param server opencode.server.Server
      return require("opencode.promise").new(function(resolve)
        server:get_sessions(function(sessions)
          resolve({ sessions = sessions, server = server })
        end)
      end)
    end)
    :next(
      function(session_data) ---@param session_data {sessions: opencode.server.Session[], server: opencode.server.Server }
        local sessions = session_data.sessions
        table.sort(sessions, function(a, b)
          return a.time.updated > b.time.updated
        end)

        return require("opencode.promise")
          .select(sessions, {
            prompt = "Select session (recently updated first):",
            format_item = function(item)
              local title_length = 60
              local updated = os.date("%b %d, %Y %H:%M:%S", item.time.updated / 1000)
              local title = ellipsize(item.title, title_length)
              return ("%s%s%s"):format(title, string.rep(" ", title_length - #title), updated)
            end,
          })
          :next(function(choice)
            return { session = choice, server = session_data.server }
          end)
      end
    )
end

return M
