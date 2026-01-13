---Provide `opencode` in a `kitty` terminal instance.
---Requires [kitty remote control](https://sw.kovidgoyal.net/kitty/remote-control/#remote-control-via-a-socket) to be enabled.
---@class opencode.provider.Kitty : opencode.Provider
---
---@field opts opencode.provider.kitty.Opts
---
---The `kitty` window ID where `opencode` is running (internal use only).
---@field window_id? number
local Kitty = {}
Kitty.__index = Kitty
Kitty.name = "kitty"

---@class opencode.provider.kitty.Opts
---
---Location where `opencode` instance should be opened.
---Possible values:
--- * https://sw.kovidgoyal.net/kitty/launch/#cmdoption-launch-location
--- * `tab`
--- * `os-window`
---@field location? "after" | "before" | "default" | "first" | "hsplit" | "last" | "neighbor" | "split" | "vsplit" | "tab" | "os-window"
---
---Optional password for `kitty` remote control.
---https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitten-password
---@field password? string
---
---@param opts? opencode.provider.kitty.Opts
---@return opencode.provider.Kitty
function Kitty.new(opts)
  local self = setmetatable({}, Kitty)
  self.opts = opts or {}
  self.window_id = nil
  return self
end

---Check if `kitty` remote control is available.
function Kitty.health()
  if vim.env.KITTY_LISTEN_ON and #vim.env.KITTY_LISTEN_ON > 0 then
    return true
  else
    return "KITTY_LISTEN_ON environment variable is not set.", "Enable remote control in `kitty`."
  end
end

---Execute a `kitty` remote control command.
---@param args string[] Arguments to pass to kitty @
---@return string|nil output, number|nil code
function Kitty:kitty_exec(args)
  local ok, err = self:health()
  if ok ~= true then
    error(err, 0)
  end

  local cmd = { "kitty", "@" }

  -- Add password if configured
  local password = self.opts.password or ""
  if #password > 0 then
    table.insert(cmd, "--password")
    table.insert(cmd, password)
  end

  -- Add the actual command arguments
  for _, arg in ipairs(args) do
    table.insert(cmd, arg)
  end

  local output = vim.fn.system(cmd)
  local code = vim.v.shell_error

  return output, code
end

---Get the `kitty` window ID where we started `opencode`, if it still exists.
---@return number|nil window_id
function Kitty:get_window_id()
  if self.window_id then
    -- Confirm it still exists
    local _, code = self:kitty_exec({ "ls", "--match", "id:" .. self.window_id })
    if code ~= 0 then
      -- Window no longer exists
      self.window_id = nil
    end
  end

  return self.window_id
end

---Toggle `opencode` in window.
function Kitty:toggle()
  local window_id = self:get_window_id()
  if not window_id then
    self:start()
  else
    self:stop()
  end
end

---Start `opencode` in window.
function Kitty:start()
  local window_id = self:get_window_id()
  if window_id then
    return
  end

  local location = self.opts.location
  local launch_cmd = { "launch", "--cwd=current", "--hold", "--dont-take-focus" }

  -- Input validation for `location` option
  local VALID_LOCATIONS = {
    "after",
    "before",
    "default",
    "first",
    "hsplit",
    "last",
    "neighbor",
    "split",
    "vsplit",
    "tab",
    "os-window",
  }

  if not vim.tbl_contains(VALID_LOCATIONS, location) then
    error(string.format("Invalid location '%s' specified", location), 0)
  end

  -- Use `--location` for splits and `--type` for tab and os-window
  if location == "tab" or location == "os-window" then
    table.insert(launch_cmd, "--type=" .. location)
  else
    table.insert(launch_cmd, "--location=" .. location)
  end

  -- Split cmd string into separate arguments for kitty launch
  for arg in self.cmd:gmatch("%S+") do
    table.insert(launch_cmd, arg)
  end

  local stdout, code = self:kitty_exec(launch_cmd)

  if code == 0 then
    -- The window ID is returned directly in stdout
    self.window_id = tonumber(stdout)
  end
end

---Stop `opencode` window.
function Kitty:stop()
  local window_id = self:get_window_id()
  if window_id then
    local _, code = self:kitty_exec({ "close-window", "--match", "id:" .. window_id })
    if code == 0 then
      self.window_id = nil
    end
  end
end

return Kitty
