local M = {}

local function ellipsize(s, max_len)
  if vim.fn.strdisplaywidth(s) <= max_len then
    return s
  end
  local truncated = vim.fn.strcharpart(s, 0, max_len - 3)
  truncated = truncated:gsub("%s+%S*$", "")

  return truncated .. "..."
end

---@param server opencode.server.Server
---@return Promise<opencode.server.Session>
function M.select_session(server)
  return server:get_sessions():next(function(sessions)
    table.sort(sessions, function(a, b)
      return a.time.updated > b.time.updated
    end)

    return require("opencode.promise.ui").select(sessions, {
      prompt = "Select session: ",
      format_item = function(item)
        local title_length = 60
        local updated = os.date("%b %d, %Y %H:%M:%S", item.time.updated / 1000)
        local title = ellipsize(item.title, title_length)
        return ("%s%s%s"):format(title, string.rep(" ", title_length - #title), updated)
      end,
    })
  end)
end

return M
