---@module 'snacks.terminal'

---Provide an integrated `opencode`.
---`start`/`stop`/`toggle` should only operate on provider-managed instances.
---`find_server` may attach to any existing instance for connection purposes.
---@class opencode.Provider
---
---The name of the provider.
---@field name? string
---
---The command to start `opencode`.
---The `--port` flag _must_ be present to expose the server for `opencode.nvim` to connect to.
---`opencode.nvim` will set `--port <opts.port>` if present.
---See all available flags [here](https://opencode.ai/docs/cli/#flags).
---@field cmd? string
---
---@field new? fun(opts: table): opencode.Provider
---
---Toggle `opencode`.
---@field toggle? fun(self: opencode.Provider)
---
---Start `opencode`.
---Called when attempting to interact with `opencode` but none was found.
---`opencode.nvim` then polls for a couple seconds waiting for one to appear.
---Should not steal focus by default, if possible.
---@field start? fun(self: opencode.Provider)
---
---Stop the previously started `opencode`.
---Called when Neovim is exiting.
---@field stop? fun(self: opencode.Provider)
---
---Health check for the provider.
---Should return `true` if the provider is available,
---else a reason string and optional advice (for `vim.health.warn`).
---@field health? fun(): boolean|string, ...string|string[]
---
---Find an existing `opencode` server via provider-specific discovery.
---Unlike other methods, may return servers not started by the provider.
---Called as a fallback when CWD-based discovery fails.
---@field find_server? fun(self: opencode.Provider): opencode.cli.server.Server|nil

---Configure and enable built-in providers.
---@class opencode.provider.Opts
---
---The built-in provider to use, or `false` for none.
---Default order:
---  - `"snacks"` if `snacks.terminal` is available and enabled
---  - `"kitty"` if in a `kitty` session with remote control enabled
---  - `"wezterm"` if in a `wezterm` window
---  - `"tmux"` if in a `tmux` session
---  - `"terminal"` as a fallback
---@field enabled? "terminal"|"snacks"|"kitty"|"wezterm"|"tmux"|false
---
---@field terminal? opencode.provider.terminal.Opts
---@field snacks? opencode.provider.snacks.Opts
---@field kitty? opencode.provider.kitty.Opts
---@field wezterm? opencode.provider.wezterm.Opts
---@field tmux? opencode.provider.tmux.Opts

local M = {}

---Get all providers.
---@return opencode.Provider[]
function M.list()
  return {
    require("opencode.provider.snacks"),
    require("opencode.provider.kitty"),
    require("opencode.provider.wezterm"),
    require("opencode.provider.tmux"),
    require("opencode.provider.terminal"),
  }
end

---Toggle `opencode` via the configured provider.
function M.toggle()
  local provider = require("opencode.config").provider
  if provider and provider.toggle then
    provider:toggle()
    require("opencode.events").subscribe()
  else
    error("`provider.toggle` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

---Start `opencode` via the configured provider.
function M.start()
  local provider = require("opencode.config").provider
  if provider and provider.start then
    provider:start()
    require("opencode.events").subscribe()
  else
    error("`provider.start` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

---Stop `opencode` via the configured provider.
function M.stop()
  local provider = require("opencode.config").provider
  if provider and provider.stop then
    provider:stop()
    require("opencode.events").unsubscribe()
  else
    error("`provider.stop` unavailable — run `:checkhealth opencode` for details", 0)
  end
end

return M
