---@module 'snacks'

local M = {}

---Your `opencode.nvim` configuration.
---Passed via global variable for [simpler UX and faster startup](https://mrcjkb.dev/posts/2023-08-22-setup.html).
---
---`snacks.nvim` note: Neovim does not yet support metatables or mixed integer and string keys in `vim.g` variables, affecting some options.
---In that case you may modify `require("opencode.config").opts` directly.
---See [opencode.nvim #36](https://github.com/nickjvandyke/opencode.nvim/issues/36) and [neovim #12544](https://github.com/neovim/neovim/issues/12544#issuecomment-1116794687).
---@type opencode.Opts|nil
vim.g.opencode_opts = vim.g.opencode_opts

---@class opencode.Opts
---
---Connect to a specific `opencode` server, and optionally manage one.
---@field server? opencode.server.Opts
---
---Contexts to inject into prompts, keyed by their placeholder.
---@field contexts? table<string, fun(context: opencode.context.Context): string|nil>
---
---Options for `ask()`.
---Supports [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field ask? opencode.ask.Opts
---
---Options and items for `select()`.
---Supports [`snacks.picker`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---@field select? opencode.select.Opts
---
---Options for handling `opencode` events.
---@field events? opencode.events.Opts
---@type opencode.Opts
local defaults = {
  server = {
    url = nil,
    username = vim.env.OPENCODE_SERVER_USERNAME or "opencode", -- Same env vars and defaults as `opencode`
    password = vim.env.OPENCODE_SERVER_PASSWORD,
    start = function()
      vim.cmd("vsplit term://opencode --port | wincmd p")
    end,
  },
  -- stylua: ignore
  contexts = {
    ["@this"] = require("opencode.context.builtins").this,
    ["@buffer"] = require("opencode.context.builtins").buffer,
    ["@buffers"] = require("opencode.context.builtins").buffers,
    ["@visible"] = require("opencode.context.builtins").visible_text,
    ["@diagnostics"] = require("opencode.context.builtins").diagnostics,
    ["@quickfix"] = require("opencode.context.builtins").quickfix,
    ["@diff"] = require("opencode.context.builtins").git_diff,
    ["@marks"] = require("opencode.context.builtins").marks,
  },
  ask = {
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
        },
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
  },
  select = {
    prompt = "opencode: ",
    prompts = {
      ask = "...",
      diagnostics = "Explain @diagnostics",
      diff = "Review the following git diff for correctness and readability: @diff",
      document = "Add comments documenting @this",
      explain = "Explain @this and its context",
      fix = "Fix @diagnostics",
      implement = "Implement @this",
      optimize = "Optimize @this for performance and readability",
      review = "Review @this for correctness and readability",
      test = "Add tests for @this",
    },
    commands = {
      ["agent.cycle"] = "Cycle selected agent",
      ["prompt.clear"] = "Clear current prompt",
      ["prompt.submit"] = "Submit current prompt",
      ["session.compact"] = "Compact current session",
      ["session.interrupt"] = "Interrupt current session",
      ["session.new"] = "Start new session",
      ["session.redo"] = "Redo last undone action in current session",
      ["session.select"] = "Select session",
      ["session.undo"] = "Undo last action in current session",
    },
    server = true,
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
      edits = {
        enabled = true,
      },
    },
  },
}

---Plugin options, lazily merged from `defaults` and `vim.g.opencode_opts`.
---@type opencode.Opts
M.opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), vim.g.opencode_opts or {})

local snacks_ok, snacks = pcall(require, "snacks")
---@cast snacks Snacks
if not snacks_ok or not snacks.config.get("input", {}).enabled then
  -- Even though it has no effect, passing these opts to the native `vim.ui.input` will error because
  -- they mix string and integer keys which Neovim doesn't support in `vim.g` (see comment on `vim.g.opencode_opts`),
  -- and Neovim's native `vim.ui.select` implementation apparently uses those.
  M.opts.ask.snacks = {}
end

-- Nest `snacks.input` options under `opts.ask.snacks` for consistency with other `snacks`-exclusive config, and to keep its fields optional.
-- But then merge it here for what `snacks.input` expects.
M.opts.ask = vim.tbl_deep_extend("force", M.opts.ask, M.opts.ask.snacks)

return M
