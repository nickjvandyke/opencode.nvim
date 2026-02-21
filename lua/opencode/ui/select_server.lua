local M = {}

---@param path1 string
---@param path2 string
---@return integer
local function common_prefix_score(path1, path2)
  -- Normalize and split paths
  local function split(path)
    local out = {}
    for seg in string.gmatch(path, "[^/]+") do
      table.insert(out, seg)
    end
    return out
  end

  local segments1 = split(path1)
  local segments2 = split(path2)
  local score = 0
  for i = 1, math.min(#segments1, #segments2) do
    if segments1[i] == segments2[i] then
      score = score + 1
    else
      break
    end
  end
  return score
end

---Select an `opencode` server from a given list.
---
---@param servers opencode.cli.server.Server[]
---@return Promise<opencode.cli.server.Server>
function M.select_server(servers)
  local nvim_cwd = vim.fn.getcwd()

  -- Sort servers by common prefix overlap with Neovim's CWD
  table.sort(servers, function(a, b)
    local score_a = common_prefix_score(nvim_cwd, a.cwd)
    local score_b = common_prefix_score(nvim_cwd, b.cwd)
    if score_a == score_b then
      return a.cwd < b.cwd -- fallback: alphabetical
    end
    return score_a > score_b
  end)

  local picker_opts = {
    prompt = "Select an `opencode` server:",
    format_item = function(server) ---@param server opencode.cli.server.Server
      return string.format("%s | %s | %d", server.title or "<No sessions>", server.cwd, server.port)
    end,
    snacks = {
      layout = {
        hidden = { "preview" },
      },
    },
  }
  picker_opts = vim.tbl_deep_extend("keep", picker_opts, require("opencode.config").opts.select or {})

  return require("opencode.promise").select(servers, picker_opts)
end

return M
