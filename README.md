# opencode.nvim

Integrate the [opencode](https://github.com/sst/opencode) AI assistant with Neovim — streamline editor-aware research, reviews, and requests.

<https://github.com/user-attachments/assets/077daa78-d401-4b8b-98d1-9ba9f94c2330>

## ✨ Features

- Connect to _any_ `opencode`, or provide an integrated instance
- Share editor context (buffer, selection, diagnostics, etc.)
- Input prompts with completions, highlights, and normal-mode support
- Select prompts from a library and define your own
- Execute commands
- Monitor and respond to events (edits, permissions, etc.) in real-time
- Interact with `opencode` via an in-process LSP
- _Vim-y_ — supports ranges and dot-repeat
- Simple, sensible defaults to get you started quickly

## 📦 Setup

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nickjvandyke/opencode.nvim",
  version = "*", -- Latest stable release
  dependencies = {
    {
      -- `snacks.nvim` integration is recommended, but optional
      ---@module "snacks" <- Loads `snacks.nvim` types for configuration intellisense
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {}, -- Enhances `ask()`
        picker = { -- Enhances `select()`
          actions = {
            opencode_send = function(...) return require("opencode").snacks_picker_send(...) end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
              },
            },
          },
        },
      },
    },
  },
  config = function()
    ---@type opencode.Opts
    vim.g.opencode_opts = {
      -- Your configuration, if any; goto definition on the type or field for details
    }

    vim.o.autoread = true -- Required for `opts.events.reload`

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<C-a>", function() require("opencode").ask("@this: ", { submit = true }) end, { desc = "Ask opencode…" })
    vim.keymap.set({ "n", "x" }, "<C-x>", function() require("opencode").select() end,                          { desc = "Execute opencode action…" })
    vim.keymap.set({ "n", "t" }, "<C-.>", function() require("opencode").toggle() end,                          { desc = "Toggle opencode" })

    vim.keymap.set({ "n", "x" }, "go",  function() return require("opencode").operator("@this ") end,        { desc = "Add range to opencode", expr = true })
    vim.keymap.set("n",          "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Add line to opencode", expr = true })

    vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end,   { desc = "Scroll opencode up" })
    vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll opencode down" })

    -- You may want these if you use the opinionated `<C-a>` and `<C-x>` keymaps above — otherwise consider `<leader>o…` (and remove terminal mode from the `toggle` keymap)
    vim.keymap.set("n", "+", "<C-a>", { desc = "Increment under cursor", noremap = true })
    vim.keymap.set("n", "-", "<C-x>", { desc = "Decrement under cursor", noremap = true })
  end,
}
```

### [nixvim](https://github.com/nix-community/nixvim)

```nix
programs.nixvim = {
  extraPlugins = [
    pkgs.vimPlugins.opencode-nvim
  ];
};
```

> [!TIP]
> Run `:checkhealth opencode` after setup.

## ⚙️ Configuration

`opencode.nvim` provides a rich and reliable default experience — see all available options and their defaults [here](./lua/opencode/config.lua).

### Contexts

`opencode.nvim` replaces placeholders in prompts with the corresponding context:

| Placeholder    | Context                                                         |
| -------------- | --------------------------------------------------------------- |
| `@this`        | Operator range or visual selection if any, else cursor position |
| `@buffer`      | Current buffer                                                  |
| `@buffers`     | Open buffers                                                    |
| `@visible`     | Visible text                                                    |
| `@diagnostics` | Current buffer diagnostics                                      |
| `@quickfix`    | Quickfix list                                                   |
| `@diff`        | Git diff                                                        |
| `@marks`       | Global marks                                                    |
| `@grapple`     | [grapple.nvim](https://github.com/cbochs/grapple.nvim) tags     |

### Prompts

Select or reference prompts to review, explain, and improve your code:

| Name          | Prompt                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| `diagnostics` | Explain `@diagnostics`                                                 |
| `diff`        | Review the following git diff for correctness and readability: `@diff` |
| `document`    | Add comments documenting `@this`                                       |
| `explain`     | Explain `@this` and its context                                        |
| `fix`         | Fix `@diagnostics`                                                     |
| `implement`   | Implement `@this`                                                      |
| `optimize`    | Optimize `@this` for performance and readability                       |
| `review`      | Review `@this` for correctness and readability                         |
| `test`        | Add tests for `@this`                                                  |

### Server

You can manually run `opencode`s however you like and `opencode.nvim` will find them!

> [!IMPORTANT]
> You _must_ run `opencode` with the `--port` flag to expose its server.

If `opencode.nvim` can't find an existing `opencode`, it uses the configured server to start one for you, defaulting to an embedded terminal.

#### Keymaps

`opencode.nvim` sets these normal-mode keymaps in the embedded terminal for Neovim-like message navigation:

| Keymap  | Command                  | Description           |
| ------- | ------------------------ | --------------------- |
| `<C-u>` | `session.half.page.up`   | Scroll up half page   |
| `<C-d>` | `session.half.page.down` | Scroll down half page |
| `gg`    | `session.first`          | Go to first message   |
| `G`     | `session.last`           | Go to last message    |
| `<Esc>` | `session.interrupt`      | Interrupt             |

#### Customization

Example using [`snacks.terminal`](https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md) instead:

```lua
local opencode_cmd = 'opencode --port'
---@type snacks.terminal.Opts
local snacks_terminal_opts = {
  win = {
    position = 'right',
    enter = false,
    on_win = function(win)
      -- Set up keymaps and cleanup for an arbitrary terminal
      require('opencode.terminal').setup(win.win)
    end,
  },
}
---@type opencode.Opts
vim.g.opencode_opts = {
  server = {
    start = function()
      require('snacks.terminal').open(opencode_cmd, snacks_terminal_opts)
    end,
    stop = function()
      require('snacks.terminal').get(opencode_cmd, snacks_terminal_opts):close()
    end,
    toggle = function()
      require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
    end,
  },
}
```

## 🚀 Usage

### Ask — `require("opencode").ask()`

Input a prompt for `opencode`.

- Press `<Up>` to browse recent asks.
- Highlights and completes contexts and `opencode` subagents.
  - Press `<Tab>` to trigger built-in completion.
- Set `opts.ask.capture = "buffer"` for a larger centered floating buffer.
  - Configure via `opts.ask.buffer` (for example: `submit_keys`, `cancel_keys`, `submit_on_write`, `linewrap`).
- End the prompt with `\n` to append instead of submit.
- Additionally, when using `snacks.input`:
  - Press `<S-CR>` to append instead of submit.
  - Offers completions via in-process LSP.

### Select — `require("opencode").select()`

Select from all `opencode.nvim` functionality.

- Prompts
- Commands
  - Fetches custom commands from `opencode`
- Server controls

Highlights and previews items when using `snacks.picker`.

### Prompt — `require("opencode").prompt()`

Prompt `opencode`.

- Resolves named references to configured prompts.
- Injects configured contexts.
- `opencode` will interpret `@` references to files or subagents.

### Operator — `require("opencode").operator()`

Wraps `prompt` as an operator, supporting ranges and dot-repeat.

### Command — `require("opencode").command()`

Command `opencode`:

| Command                  | Description                                        |
| ------------------------ | -------------------------------------------------- |
| `session.list`           | List sessions                                      |
| `session.new`            | Start a new session                                |
| `session.select`         | Select a session                                   |
| `session.share`          | Share the current session                          |
| `session.interrupt`      | Interrupt the current session                      |
| `session.compact`        | Compact the current session (reduce context size)  |
| `session.page.up`        | Scroll messages up by one page                     |
| `session.page.down`      | Scroll messages down by one page                   |
| `session.half.page.up`   | Scroll messages up by half a page                  |
| `session.half.page.down` | Scroll messages down by half a page                |
| `session.first`          | Jump to the first message in the session           |
| `session.last`           | Jump to the last message in the session            |
| `session.undo`           | Undo the last action in the current session        |
| `session.redo`           | Redo the last undone action in the current session |
| `prompt.submit`          | Submit the TUI input                               |
| `prompt.clear`           | Clear the TUI input                                |
| `agent.cycle`            | Cycle the selected agent                           |

### LSP

> [!WARNING]
> This feature is experimental! Try it out with `vim.g.opencode_opts.lsp.enabled = true`.

`opencode.nvim` provides an in-process LSP to interact with `opencode` via the LSP functions you're used to!

| LSP Function | `opencode.nvim` Handler                                                 |
| ------------ | ----------------------------------------------------------------------- |
| Hover        | Asks `opencode` for a brief explanation of the symbol under the cursor. |
| Code Actions | Asks `opencode` to explain or fix diagnostics under the cursor.         |

## 👀 Events

`opencode.nvim` forwards `opencode`'s Server-Sent-Events as an `OpencodeEvent` autocmd:

```lua
-- Handle `opencode` events
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*", -- Optionally filter event types
  callback = function(args)
    ---@type opencode.cli.client.Event
    local event = args.data.event
    ---@type number
    local port = args.data.port

    -- See the available event types and their properties
    vim.notify(vim.inspect(event))
    -- Do something useful
    if event.type == "session.idle" then
      vim.notify("`opencode` finished responding")
    end
  end,
})
```

### Edits

When `opencode` edits a file, `opencode.nvim` automatically reloads the corresponding buffer.

### Permissions

When `opencode` requests a permission, `opencode.nvim` waits for idle to ask you to approve or deny it.

### Statusline

```lua
require("lualine").setup({
  sections = {
    lualine_z = {
      {
        require("opencode").statusline,
      },
    }
  }
})
```

## 🙏 Acknowledgments

- Inspired by [nvim-aider](https://github.com/GeorgesAlkhouri/nvim-aider), [neopencode.nvim](https://github.com/loukotal/neopencode.nvim), and [sidekick.nvim](https://github.com/folke/sidekick.nvim).
- Uses `opencode`'s TUI for simplicity — see [sudo-tee/opencode.nvim](https://github.com/sudo-tee/opencode.nvim) for a Neovim frontend.
- [mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server) may better suit you, but it lacks customization and tool calls are slow and unreliable.
