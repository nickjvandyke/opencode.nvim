local M = {}

---@param pids number[]
---@return table<number, number>
local function get_ports(pids)
  local pids_to_ports = {}
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

  local pid
  for line in lsof.stdout:gmatch("[^\n]+") do
    local prefix = line:sub(1, 1)
    local value = line:sub(2)

    if prefix == "p" then
      -- PID line
      pid = tonumber(value)
    elseif prefix == "n" then
      -- Network interface line - look for ":PORT" at the end of the string
      local port = tonumber(value:match(":(%d+)$"))
      -- Associate the port with the most recently seen PID (they're always in this order)
      pids_to_ports[pid] = port
    end
  end

  return pids_to_ports
end

---@return opencode.cli.process.Process[]
function M.get()
  assert(vim.fn.has("unix") == 1, "`opencode.cli.process.unix.get` should only be called on Unix-like systems")

  -- Find PIDs by command line pattern.
  -- Filter by `--port` because it's required to expose the server.
  -- We can aaaalmost skip this and just use "-c opencode" with `lsof`,
  -- but that misses servers started by "bun" or "node" (or who knows what else) :(
  local pgrep = vim.system({ "pgrep", "-f", "opencode .*--port" }, { text = true }):wait()
  require("opencode.util").check_system_call(pgrep, "pgrep")

  local pids = vim.tbl_map(function(line)
    return tonumber(line)
  end, vim.split(pgrep.stdout, "\n", { trimempty = true }))
  local pids_to_ports = get_ports(pids)

  return vim.tbl_map(function(pid)
    ---@type opencode.cli.process.Process
    return {
      pid = pid,
      port = pids_to_ports[pid],
    }
  end, pids)
end

return M
