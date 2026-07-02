local M = {}

---@return Promise<number[]>
local function find_pids()
  return require("opencode.promise.system").system({ "pgrep", "-f", "opencode.*--port" }):next(function(pgrep_stdout)
    return require("opencode.promise").resolve(
      vim.tbl_map(tonumber, vim.split(pgrep_stdout, "\n", { trimempty = true }))
    )
  end)
end

---@param pids number[]
---@return Promise<opencode.server.discovery.process.Process[]>
local function find_ports(pids)
  return require("opencode.promise.system")
    .system({
      "lsof",
      "-Fpn", -- Output PID and network interface in a reliable (portable) format
      "-w", -- Suppress warning messages about files that can't be accessed (common with e.g. Docker FUSE mounts)
      -- Only network files with TCP state LISTEN
      "-iTCP",
      "-sTCP:LISTEN",
      -- Only these PIDS
      "-p",
      table.concat(pids, ","),
      "-a", -- AND the above conditions together
      "-P", -- Don't resolve port numbers to port names - we can't use the latter to send requests, and it's slower anyway
      "-n", -- Don't resolve port numbers to hostnames - same as above
    })
    :next(function(lsof_stdout)
      ---@type opencode.server.discovery.process.Process[]
      local processes = {}
      local pid
      for line in lsof_stdout:gmatch("[^\n]+") do
        local prefix = line:sub(1, 1)
        local value = line:sub(2)

        if prefix == "p" then
          pid = tonumber(value)
        elseif prefix == "n" then
          local port = tonumber(value:match(":(%d+)$"))
          if port then
            table.insert(
              processes,
              ---@type opencode.server.discovery.process.Process
              { pid = pid, port = port }
            )
          end
        end
      end

      return require("opencode.promise").resolve(processes)
    end)
end

---@return Promise<opencode.server.discovery.process.Process[]>
function M.get()
  return find_pids():next(function(pids)
    if #pids == 0 then
      return require("opencode.promise").resolve({})
    end
    return find_ports(pids)
  end)
end

return M
