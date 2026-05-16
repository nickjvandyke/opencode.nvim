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
---Where to look for an `opencode` server, and optionally how to manage one.
---@field server? opencode.server.Opts
---
---Contexts to inject into prompts, keyed by their placeholder.
---@field contexts? table<string, fun(context: opencode.Context): string|nil>
---
---Prompts to select from.
---Postfix with a space to append instead of submit the prompt.
---Postfix with "..." to open the prompt in `ask()` before sending.
---@field prompts? table<string, string>
---
---Options for `ask()`.
---Supports [`snacks.input`](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).
---@field ask? opencode.ask.Opts
---
---Options and items for `select()`.
---Supports [`snacks.picker`](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).
---@field select? opencode.select.Opts
---
---Options for the in-process LSP that interacts with `opencode`.
---@field lsp? opencode.lsp.Opts
---
---Options for `opencode` event handling.
---@field events? opencode.events.Opts

---@type opencode.Opts
local defaults = {
  server = {
    port = nil,
    username = vim.env.OPENCODE_SERVER_USERNAME or "opencode", -- Same env vars and defaults as `opencode`
    password = vim.env.OPENCODE_SERVER_PASSWORD,
    start = function()
      require("opencode.terminal").open("opencode --port", {
        split = "right",
        width = math.floor(vim.o.columns * 0.35),
      })
    end,
    stop = function()
      require("opencode.terminal").close()
    end,
    toggle = function()
      require("opencode.terminal").toggle("opencode --port", {
        split = "right",
        width = math.floor(vim.o.columns * 0.35),
      })
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

return M
