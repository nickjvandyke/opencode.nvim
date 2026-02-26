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
---Where to look for an `opencode` server, and optionally how to manage one.
---@field server? opencode.cli.server.Opts
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
---Options for the in-process LSP that interacts with `opencode`.
---@field lsp? opencode.lsp.Opts
---
---Options for `opencode` event handling.
---@field events? opencode.events.Opts

---@class opencode.Prompt : opencode.api.prompt.Opts
---@field prompt string The prompt to send to `opencode`.
---@field ask? boolean Call `ask(prompt)` instead of `prompt(prompt)`. Useful for prompts that expect additional user input.

---@type opencode.Opts
local defaults = {
  server = {
    port = nil,
    start = function()
      require("opencode.terminal").start("opencode --port")
    end,
    stop = function()
      require("opencode.terminal").stop()
    end,
    toggle = function()
      require("opencode.terminal").toggle("opencode --port")
    end,
  },
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
    ask = { prompt = "", ask = true, submit = true },
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
    capture = "input",
    prompt = "Ask opencode: ",
    completion = "customlist,v:lua.opencode_completion",
    snacks = {
      icon = "󰚩 ",
      win = {
        title_pos = "left",
        relative = "cursor",
        row = -3, -- Row above the cursor
        col = 0, -- Align with the cursor
        keys = {
          i_cr = {
            desc = "submit",
          },
          i_s_cr = {
            "<S-CR>",
            function(win)
              -- Append `\n` to leverage `ask()`'s auto-append behavior in that case
              local text = win:text() .. "\\n"
              vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, { text })
              win:execute("confirm")
            end,
            mode = "i",
            desc = "append",
          },
        },
        footer_keys = { "<CR>", "<S-CR>" },
        b = {
          completion = true,
        },
        bo = {
          filetype = "opencode_ask",
        },
        on_buf = function(win)
          -- Make sure your completion plugin has the LSP source enabled,
          -- either by default or for the `opencode_ask` filetype!
          vim.lsp.start(require("opencode.ui.ask.cmp"), {
            bufnr = win.buf,
          })
        end,
      },
    },
    buffer = {
      width_ratio = 0.7,
      height_ratio = 0.3,
      min_width = 60,
      min_height = 8,
      border = "rounded",
      title_pos = "center",
      linewrap = false,
      submit_on_write = false,
      start_insert = true,
      submit_keys = {
        n = { "<C-s>" },
        i = { "<C-s>" },
      },
      cancel_keys = {
        n = { "q", "<Esc>" },
        i = { "<C-c>" },
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
      server = true,
    },
    snacks = {
      preview = "preview",
      layout = {
        preset = "vscode",
        hidden = {}, -- preview is hidden by default in `vim.ui.select`
      },
    },
  },
  lsp = {
    enabled = false,
    filetypes = nil,
    handlers = {
      hover = {
        enabled = true,
        model = nil,
      },
      code_action = { enabled = true },
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
}

---Plugin options, lazily merged from `defaults` and `vim.g.opencode_opts`.
---@type opencode.Opts
M.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.g.opencode_opts or {})

---@diagnostic disable-next-line: undefined-field
if M.opts.provider then
  -- TODO: Remove later
  vim.notify(
    "The `provider` option has been removed for maintenance reasons. Please use the simpler `server` option instead, and/or manage your `opencode` how you do other programs. See `README.md#server` for details. Sorry for the inconvenience!",
    vim.log.levels.WARN,
    { title = "opencode" }
  )
end

local snacks_ok, snacks = pcall(require, "snacks")
---@cast snacks Snacks
if not snacks_ok or not snacks.config.get("input", {}).enabled then
  -- Even though it has no effect, passing these opts to the native `vim.ui.input` will error because
  -- they mix string and integer keys which Neovim doesn't support in `vim.g` (see comment on `vim.g.opencode_opts`),
  -- and Neovim's native `vim.ui.select` implementation apparently uses those.
  M.opts.ask.snacks = {}
end

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

return M
