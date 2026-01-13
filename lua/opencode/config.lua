---@module 'snacks'

local M = {}

---Your `opencode.nvim` configuration.
---Passed via global variable for [simpler UX and faster startup](https://mrcjkb.dev/posts/2023-08-22-setup.html).
---
---Note that Neovim does not yet support metatables or mixed integer and string keys in `vim.g`, affecting some `snacks.nvim` options.
---In that case you may modify `require("opencode.config").opts` directly.
---See [opencode.nvim #36](https://github.com/NickvanDyke/opencode.nvim/issues/36) and [neovim #12544](https://github.com/neovim/neovim/issues/12544#issuecomment-1116794687).
---@type opencode.Opts|nil
vim.g.opencode_opts = vim.g.opencode_opts

---@class opencode.Opts
---
---The port `opencode` is running on.
---If `nil`, searches for an `opencode` process inside Neovim's CWD.
---If set, `opencode.nvim` will append `--port <port>` to `provider.cmd`.
---@field port? number
---
---Contexts to inject into prompts, keyed by their placeholder.
---@field contexts? table<string, fun(context: opencode.Context): string|nil>
---
---Prompts to reference or select from.
---@field prompts? table<string, opencode.Prompt>
---
---Options for `ask()`.
---Supports [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field ask? opencode.ask.Opts
---
---Options for `select()`.
---Supports [`snacks.picker`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---@field select? opencode.select.Opts
---
---Options for `opencode` event handling.
---@field events? opencode.events.Opts
---
---Provide an integrated `opencode` when one is not found.
---@field provider? opencode.Provider|opencode.provider.Opts

---@class opencode.Prompt : opencode.api.prompt.Opts
---@field prompt string The prompt to send to `opencode`.
---@field ask? boolean Call `ask(prompt)` instead of `prompt(prompt)`. Useful for prompts that expect additional user input.

---@type opencode.Opts
local defaults = {
  port = nil,
  -- stylua: ignore
  contexts = {
    ["@this"] = function(context) return context:this() end,
    ["@buffer"] = function(context) return context:buffer() end,
    ["@buffers"] = function(context) return context:buffers() end,
    ["@visible"] = function(context) return context:visible_text() end,
    ["@diagnostics"] = function(context) return context:diagnostics() end,
    ["@quickfix"] = function(context) return context:quickfix() end,
    ["@diff"] = function(context) return context:git_diff() end,
    ["@marks"] = function(context) return context:marks() end,
    ["@grapple"] = function(context) return context:grapple_tags() end,
  },
  prompts = {
    ask_append = { prompt = "", ask = true }, -- Handy to insert context mid-prompt. Simpler than exposing every context as a prompt by default.
    ask_this = { prompt = "@this: ", ask = true, submit = true },
    diagnostics = { prompt = "Explain @diagnostics", submit = true },
    diff = { prompt = "Review the following git diff for correctness and readability: @diff", submit = true },
    document = { prompt = "Add comments documenting @this", submit = true },
    explain = { prompt = "Explain @this and its context", submit = true },
    fix = { prompt = "Fix @diagnostics", submit = true },
    implement = { prompt = "Implement @this", submit = true },
    optimize = { prompt = "Optimize @this for performance and readability", submit = true },
    review = { prompt = "Review @this for correctness and readability", submit = true },
    test = { prompt = "Add tests for @this", submit = true },
  },
  ask = {
    prompt = "Ask opencode: ",
    blink_cmp_sources = { "opencode", "buffer" },
    snacks = {
      icon = "󰚩 ",
      win = {
        title_pos = "left",
        relative = "cursor",
        row = -3, -- Row above the cursor
        col = 0, -- Align with the cursor
      },
    },
  },
  select = {
    prompt = "opencode: ",
    sections = {
      prompts = true,
      commands = {
        ["session.new"] = "Start a new session",
        ["session.select"] = "Select a session",
        ["session.share"] = "Share the current session",
        ["session.interrupt"] = "Interrupt the current session",
        ["session.compact"] = "Compact the current session (reduce context size)",
        ["session.undo"] = "Undo the last action in the current session",
        ["session.redo"] = "Redo the last undone action in the current session",
        ["agent.cycle"] = "Cycle the selected agent",
        ["prompt.submit"] = "Submit the current prompt",
        ["prompt.clear"] = "Clear the current prompt",
      },
      provider = true,
    },
    snacks = {
      preview = "preview",
      layout = {
        preset = "vscode",
        hidden = {}, -- preview is hidden by default in `vim.ui.select`
      },
    },
  },
  events = {
    enabled = true,
    reload = true,
    permissions = {
      enabled = true,
      idle_delay_ms = 1000,
    },
  },
  provider = {
    cmd = "opencode --port",
    enabled = vim.tbl_filter(
      ---@param provider opencode.Provider
      function(provider)
        return provider.health() == true
      end,
      require("opencode.provider").list()
    )[1].name,
    terminal = {
      split = "right",
      width = math.floor(vim.o.columns * 0.35),
    },
    snacks = {
      auto_close = true, -- Close the terminal when `opencode` exits
      win = {
        position = "right",
        enter = false, -- Stay in the editor after opening the terminal
        wo = {
          winbar = "", -- Title is unnecessary - `opencode` TUI has its own footer
        },
        bo = {
          -- Make it easier to target for customization, and prevent possibly unintended `"snacks_terminal"` targeting.
          -- e.g. the recommended edgy.nvim integration puts all `"snacks_terminal"` windows at the bottom.
          filetype = "opencode_terminal",
        },
      },
    },
    kitty = {
      -- Copy the editor's environment so `opencode` has access to e.g. Mason-installed binaries
      cmd = "--copy-env opencode --port",
      location = "default",
    },
    -- These are wezterm's internal defaults
    wezterm = {
      direction = "bottom",
      top_level = false,
      percent = 50,
    },
    tmux = {
      options = "-h", -- Open in a horizontal split
    },
  },
}

---Plugin options, lazily merged from `defaults` and `vim.g.opencode_opts`.
---@type opencode.Opts
M.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.g.opencode_opts or {})

-- Allow removing default `contexts` and `prompts` by setting them to `false` in your user config.
-- TODO: Add to type definition, and apply to `opts.select.commands`.
local user_opts = vim.g.opencode_opts or {}
for _, field in ipairs({ "contexts", "prompts" }) do
  if user_opts[field] and M.opts[field] then
    for k, v in pairs(user_opts[field]) do
      if not v then
        M.opts[field][k] = nil
      end
    end
  end
end

---The `opencode` provider resolved from `opts.provider`.
---
---Retains the base `provider.cmd` if not overridden.
---Sets `--port <port>` in `provider.cmd` if `opts.port` is set.
---@type opencode.Provider|nil
M.provider = (function()
  local provider
  local provider_or_opts = M.opts.provider

  if provider_or_opts and (provider_or_opts.toggle or provider_or_opts.start or provider_or_opts.stop) then
    -- An implementation was passed.
    -- Beware: `provider.enabled` may still exist from merging with defaults.
    ---@cast provider_or_opts opencode.Provider
    provider = provider_or_opts
  elseif provider_or_opts and provider_or_opts.enabled then
    -- Resolve the built-in provider.
    ---@type boolean, opencode.Provider
    local ok, resolved_provider = pcall(require, "opencode.provider." .. provider_or_opts.enabled)
    if not ok then
      vim.notify(
        "Failed to load `opencode` provider '" .. provider_or_opts.enabled .. "': " .. resolved_provider,
        vim.log.levels.ERROR,
        { title = "opencode" }
      )
      return nil
    end

    local resolved_provider_opts = provider_or_opts[provider_or_opts.enabled]
    provider = resolved_provider.new(resolved_provider_opts)

    provider.cmd = provider.cmd or provider_or_opts.cmd
  end

  local port = M.opts.port
  if port and provider and provider.cmd then
    -- Remove any existing `--port` argument to avoid duplicates
    provider.cmd = provider.cmd:gsub("--port ?", "") .. " --port " .. tostring(port)
  end

  return provider
end)()

return M
