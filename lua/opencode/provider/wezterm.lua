---Provide `opencode` in a [`wezterm`](https://wezterm.org/index.html) pane in the current window.
---@class opencode.provider.Wezterm : opencode.Provider
---
---@field opts opencode.provider.wezterm.Opts
---@field pane_id? string The `wezterm` pane ID where `opencode` is running (internal use only).
local Wezterm = {}
Wezterm.__index = Wezterm
Wezterm.name = "wezterm"

---`wezterm` options for creating the pane.
---Strictly mimics the options available in the `wezterm cli split-pane --help` command
---@class opencode.provider.wezterm.Opts
---
---Direction in which the pane that runs opencode is spawn, defaults to bottom
---@field direction? "left" | "top" | "right" | "bottom"
---
---The number of cells that the new split should have expressed as a percentage of the available
---space, default is 50%
---@field percent? number
---
---Rather than splitting the active pane, split the entire window
---@field top_level? boolean

---@param opts? opencode.provider.wezterm.Opts
---@return opencode.provider.Wezterm
function Wezterm.new(opts)
  local self = setmetatable({}, Wezterm)
  self.opts = opts or {}
  self.pane_id = nil
  return self
end

local function focus_pane(pane_id)
  vim.fn.system(string.format("wezterm cli activate-pane --pane-id %d", pane_id))
end

---Check if `wezterm` is running in current terminal.
function Wezterm.health()
  if vim.fn.executable("wezterm") ~= 1 then
    return "`wezterm` executable not found in `$PATH`.",
      {
        "Install `wezterm` and ensure it's in your `$PATH`.",
      }
  end

  if not vim.env.WEZTERM_PANE then
    return "Not running in a `wezterm` window.", {
      "Launch Neovim in a `wezterm` window.",
    }
  end

  return true
end

---Retrieve the `wezterm` pane ID associated with the running `opencode` instance.
---This establishes a direct link between the spawned `opencode` pane and its ID.
---If the `opencode` pane is closed and a new one is created manually, it cannot
---still be tracked by this ID.
---@return string|nil pane_id
function Wezterm:get_pane_id()
  local ok = self.health()
  if ok ~= true then
    error(ok)
  end

  if self.pane_id == nil then
    return nil
  end

  local result = vim.fn.system("wezterm cli list --format json 2>&1")

  if result == nil or result == "" or result:match("error") then
    self.pane_id = nil
    return nil
  end

  local success, panes = pcall(vim.json.decode, result)
  if not success or type(panes) ~= "table" then
    self.pane_id = nil
    return nil
  end

  -- Search for the pane in the list
  for _, pane in ipairs(panes) do
    if tostring(pane.pane_id) == tostring(self.pane_id) then
      return self.pane_id
    end
  end

  -- Pane was not found in the list
  self.pane_id = nil
  return nil
end

---Create or kill the `opencode` pane.
function Wezterm:toggle()
  local pane_id = self:get_pane_id()
  if pane_id then
    self:stop()
  else
    self:start()
  end
end

---Start `opencode` in pane.
function Wezterm:start()
  local pane_id = self:get_pane_id()
  if not pane_id then
    local cmd_parts = { "wezterm", "cli", "split-pane" }

    if self.opts.direction then
      table.insert(cmd_parts, "--" .. self.opts.direction)
    end

    if self.opts.percent then
      table.insert(cmd_parts, "--percent")
      table.insert(cmd_parts, tostring(self.opts.percent))
    end

    if self.opts.top_level then
      table.insert(cmd_parts, "--top-level")
    end

    table.insert(cmd_parts, "--")
    table.insert(cmd_parts, self.cmd)

    local result = vim.fn.system(table.concat(cmd_parts, " "))
    focus_pane(vim.env.WEZTERM_PANE)

    self.pane_id = result:match("^%d+")
  end
end

---Kill the `opencode` pane.
function Wezterm:stop()
  local pane_id = self:get_pane_id()
  if pane_id then
    vim.fn.system(string.format("wezterm cli kill-pane --pane-id %d", pane_id))
    self.pane_id = nil
  end
end

return Wezterm
