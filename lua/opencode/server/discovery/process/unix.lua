local M = {}

---@param pids number[]
---@return opencode.server.discovery.process.Process[]
local function get_processes_with_ports(pids)
  assert(#pids > 0, "`get_processes` should only be called with a non-empty list of PIDs to filter by")

  local lsof = vim
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
    }, { text = true })
    :wait()
  require("opencode.util").check_system_call(lsof, "lsof")

  ---@type opencode.server.discovery.process.Process[]
  local processes = {}
  local pid
  for line in lsof.stdout:gmatch("[^\n]+") do
    local prefix = line:sub(1, 1)
    local value = line:sub(2)

    if prefix == "p" then
      -- PID line
      pid = tonumber(value)
    elseif prefix == "n" then
      -- Network interface line - look for ":PORT" at the end of the string.
      -- Emit one process entry per (PID, port) since a single PID may listen on multiple ports.
      local port = tonumber(value:match(":(%d+)$"))
      if port then
        processes[#processes + 1] = { pid = pid, port = port }
      end
    end
  end

  return processes
end

---@return opencode.server.discovery.process.Process[]
function M.get()
  assert(
    vim.fn.has("unix") == 1,
    "`opencode.server.discovery.process.unix.get` should only be called on Unix-like systems"
  )

  -- Find PIDs by command line pattern.
  -- Filter by `--port` because it's required to expose the server.
  -- We can aaaalmost skip this and just use "-c opencode" with `lsof`,
  -- but that misses servers started by "bun" or "node" (or who knows what else) :(
  -- Also we should consider that on Nix binary can be called "opencode-wrapped"
  -- (so we cannot do "opencode .*--port").
  local pgrep = vim.system({ "pgrep", "-f", "opencode.*--port" }, { text = true }):wait()
  require("opencode.util").check_system_call(pgrep, "pgrep")
  local pids = vim.tbl_map(function(line)
    return tonumber(line)
  end, vim.split(pgrep.stdout, "\n", { trimempty = true }))

  if #pids == 0 then
    return {}
  end

  return get_processes_with_ports(pids)
end

return M
