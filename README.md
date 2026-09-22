# opencode.nvim

Neovim plugin that integrates with [OpenCode](https://opencode.ai/) to keep you in the flow that you already know.

https://github.com/user-attachments/assets/e85e021c-fa8f-466e-830c-c667b28f611e

## ⭐ Motivation

AI works best at small, focused scopes — as a pair programmer with the human driving. You stay in control, craft the code that matters, and keep your skills sharp. opencode.nvim just provides the context and connection to make that pairing seamless.

Rather than introduce yet another interaction model, opencode.nvim leverages OpenCode's existing TUI and API via standard Neovim interfaces. You keep your environment, your config, your flow.

For me, the best tools are the ones that "just work." opencode.nvim is designed to be one of them.

## ✨ Features

- Connect to _any_ OpenCode server, or start an integrated instance
- Inject editor context (cursor, selection, buffer, etc.)
- Input prompts with completions and highlights
- Select from built-in and custom prompts
- Execute OpenCode commands
- Accept/reject and reload OpenCode edits
- Handle OpenCode events as autocmds
- Simple, sensible, Vim-y defaults and interfaces

## 📦 Setup

[vim.pack](https://neovim.io/doc/user/pack/#vim.pack) (recommended)

```lua
vim.pack.add({
  {
    src = "https://github.com/nickjvandyke/opencode.nvim",
    version = vim.version.range("*"), -- Latest stable release
  },
})

---@type opencode.Opts
vim.g.opencode_opts = {
  -- Your configuration, if any; goto definition on the type for details
}

-- Recommended/example keymaps
vim.keymap.set({ "n", "x" }, "<C-a>",   function() require("opencode").ask("@this: ") end,                    { desc = "Ask OpenCode…" })
vim.keymap.set({ "n", "x" }, "<C-x>",   function() require("opencode").select() end,                          { desc = "Select OpenCode…" })
vim.keymap.set({ "n", "x" }, "go",      function() return require("opencode").operator("@this") end,         { desc = "Send range to OpenCode", expr = true })
vim.keymap.set({ "n" },      "goo",     function() return require("opencode").operator("@this") .. "_" end,  { desc = "Send line to OpenCode", expr = true })
```

<details>
<summary><a href="https://github.com/folke/lazy.nvim">lazy.nvim</a></summary>

```lua
{
  "nickjvandyke/opencode.nvim",
  version = "*", -- Latest stable release
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      -- Your configuration, if any; goto definition on the type for details
    }

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<C-a>",   function() require("opencode").ask("@this: ") end,                    { desc = "Ask OpenCode…" })
    vim.keymap.set({ "n", "x" }, "<C-x>",   function() require("opencode").select() end,                          { desc = "Select OpenCode…" })
    vim.keymap.set({ "n", "x" }, "go",      function() return require("opencode").operator("@this") end,         { desc = "Send range to OpenCode", expr = true })
    vim.keymap.set({ "n" },      "goo",     function() return require("opencode").operator("@this") .. "_" end,  { desc = "Send line to OpenCode", expr = true })
  end,
}
```

</details>

<details>
<summary><a href="https://github.com/nix-community/nixvim">nixvim</a></summary>

```nix
programs.nixvim = {
  extraPlugins = [
    pkgs.vimPlugins.opencode-nvim
  ];
};
```

</details>

### Integrations

The below examples are specific, but generalize to other plugins.

<details>
<summary><a href="https://github.com/folke/snacks.nvim/blob/main/docs/input.md">snacks.input</a> (Ask)</summary>

```lua
require("snacks").setup({
  input = {
    enabled = true, -- Enhances Ask
  },
})
```

</details>

<details>
<summary><a href="https://github.com/folke/snacks.nvim/blob/main/docs/picker.md">snacks.picker</a> (Select)</summary>

```lua
require("snacks").setup({
  picker = {
    enabled = true, -- Enhances Select
    win = {
      input = {
        keys = {
          ["<a-o>"] = { "opencode_send", mode = { "n", "i" } },
        },
      },
    },
    actions = {
      opencode_send = function(picker) ---@param picker snacks.Picker
        local items = vim.tbl_map(function(item) ---@param item snacks.picker.Item
          return item.file
            and require("opencode").format({ path = item.file, from = item.pos, to = item.end_pos })
            or item.text
        end, picker:selected({ fallback = true }))

        require("opencode").prompt(table.concat(items, ", ") .. " ")
      end,
    },
  },
})
```

</details>

<details>
<summary><a href="https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md">snacks.terminal</a> (Server)</summary>

```lua
local opencode_cmd = 'opencode'
---@type snacks.terminal.Opts
local snacks_terminal_opts = {
  win = {
    position = 'right',
    enter = false,
  },
}

---@type opencode.Opts
vim.g.opencode_opts = {
  server = {
    start = function()
      require('snacks.terminal').open(opencode_cmd, snacks_terminal_opts)
    end,
  },
}

-- Can also leverage toggle functionality.
-- If you use <leader> here, remove 't' — otherwise Neovim will add input delay to your <leader> when typing in the terminal to watch for the mapping.
vim.keymap.set({ 'n', 't' }, '<C-.>', function()
  require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
end, { desc = 'Toggle OpenCode' })

-- Optionally show the terminal when OpenCode starts executing
vim.api.nvim_create_autocmd('User', {
  pattern = { 'OpencodeEvent:session.execution.started' },
  callback = function()
    local win = require('snacks.terminal').get(opencode_cmd, { create = false })
    if win then
      win:show()
    end
  end,
})
```

</details>

<details>
<summary><a href="https://github.com/saghen/blink.cmp">blink.cmp</a> (Completion)</summary>

```lua
-- Configure blink.cmp to show completions in Ask from opencode.nvim's in-process LSP.
-- Only applicable when using snacks.input.
require("blink.cmp").setup({
  sources = {
    -- Either enable LSP (and optionally buffer) source globally
    default = { 'lsp', 'buffer' },
    -- Or only for Ask
    per_filetype = {
      opencode_ask = { 'lsp', 'buffer' },
    },
    -- Display buffer completions (if included above) when no LSP completions are available
    providers = { lsp = { fallbacks = {} } },
  },
})
```

</details>

<details>
<summary><a href="https://github.com/nvim-lualine/lualine.nvim">lualine.nvim</a> (Statusline)</summary>

```lua
require("lualine").setup({
  sections = {
    lualine_z = {
      {
        -- Show the currently connected server and its status
        require("opencode").statusline,
      },
    },
  },
})
```

</details>

> [!TIP]
> Run `:checkhealth opencode` after setup.

## ⚙️ Configuration

opencode.nvim provides a rich and reliable default experience — see all available options and their defaults [here](./lua/opencode/config.lua).

### Contexts

opencode.nvim replaces placeholders in prompts with the corresponding context:

| Placeholder    | Context                                                                      |
| -------------- | ---------------------------------------------------------------------------- |
| `@this`        | Range or selection if any, else cursor position                              |
| `@buffer`      | Current buffer                                                               |
| `@buffers`     | Open buffers                                                                 |
| `@diagnostics` | Diagnostics within the range or selection if any, else in the current buffer |
| `@marks`       | Global marks                                                                 |
| `@quickfix`    | Quickfix list                                                                |
| `@visible`     | Visible text                                                                 |

> [!TIP]
> OpenCode reads referenced files from disk — save your changes!

### Prompts

Select prompts to review, explain, and improve your code:

| Name          | Prompt                                           |
| ------------- | ------------------------------------------------ |
| `diagnostics` | Explain `@diagnostics`                           |
| `document`    | Add comments documenting `@this`                 |
| `explain`     | Explain `@this` and its context                  |
| `fix`         | Fix `@diagnostics`                               |
| `implement`   | Implement `@this`                                |
| `optimize`    | Optimize `@this` for performance and readability |
| `review`      | Review `@this` for correctness and readability   |
| `test`        | Add tests for `@this`                            |

### Server

Run `opencode` and opencode.nvim will automatically find its daemon server! Or point `vim.g.opencode_opts.server.url` to a specific server, including remotes.

If opencode.nvim can't find a running service, it starts one via `vim.g.opencode_opts.server.start`, defaulting to opening `opencode` in a terminal. See [Integrations > snacks.terminal (Server)](#integrations) for a custom start example.

opencode.nvim prioritizes focused pairing with a single OpenCode instance. As such, it connects to an OpenCode server before interacting with it, listening for events and targeting it for future interactions. Consider disabling `vim.g.opencode_opts.server.connect` if you don't care for disruptive synchronous events like permission requests.

## 🚀 Usage

### Ask — `require("opencode").ask()`

Input a prompt for OpenCode.

- Passes the text to Prompt.
- Press `<Up>` to browse recent asks.
- Highlights and completes contexts.
  - Press `<Tab>` to trigger built-in completion.
  - Provided by in-process LSP when using [snacks.input](https://github.com/folke/snacks.nvim/blob/main/docs/input.md).

### Select — `require("opencode").select()`

Select from all opencode.nvim functionality.

Highlights and previews items when using [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md).

### Prompt — `require("opencode").prompt()`

Prompt OpenCode.

Targets the most recently updated session for Neovim's directory.
Injects configured contexts.
Trailing "..." opens in `ask()`.

### Operator — `require("opencode").operator()`

Wraps Prompt as an operator, supporting ranges and dot-repeat.

### Command — `require("opencode").command()`

Run a registered OpenCode [command](https://opencode.ai/v2/docs/commands/).

Targets the most recently updated session for Neovim's directory.

## 👀 Events

opencode.nvim forwards the connected OpenCode's Server-Sent-Events as an `OpencodeEvent` autocmd:

```lua
-- Handle OpenCode events
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*", -- Optionally filter event types
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type string
    local url = args.data.url

    -- See the available event types and their data
    vim.notify(vim.inspect(event))
    -- Do something useful
    if event.type == "session.status" then
      vim.notify("OpenCode status updated: " .. event.data.status.type)
    end
  end,
})
```

> [!NOTE]
> Event payloads are passed through from the OpenCode as-is and follow its schema. They may change with OpenCode releases, so treat them as best-effort rather than a stable API contract.

### Edits

When the connected OpenCode edits a file, opencode.nvim reloads the corresponding buffer in real-time. `vim.o.autoread = true` is set automatically to enable this unless you've explicitly configured it.

### Permissions

When the connected OpenCode requests a permission, opencode.nvim asks you to approve or deny it.

#### Edits

When the connected Opencode requests an edit, opencode.nvim opens the target file in a new tab and uses Neovim's `:diffpatch` to display the proposed changes side-by-side. See `:h 'diffopt'` for customization.

| Keymap  | Function                                                                      |
| ------- | ----------------------------------------------------------------------------- |
| `da`    | Accept the entire edit request                                                |
| `dr`    | Reject the entire edit request                                                |
| `]c/[c` | Next/prev change                                                              |
| `dp`    | Natively accept _only_ the hunk under the cursor, and reject the edit request |
| `do`    | Natively reject _only_ the hunk under the cursor, and reject the edit request |
| `q`     | Close the diff                                                                |
