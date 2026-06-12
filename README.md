# opencode.nvim

Bridge Neovim and [OpenCode AI](https://opencode.ai/) to stay in your flow.

https://github.com/user-attachments/assets/e85e021c-fa8f-466e-830c-c667b28f611e

> Like what you see? Check out [my config](https://github.com/nickjvandyke/nvim).

## ✨ Features

- Connect to _any_ OpenCode server, or start an integrated instance
- Inject editor context (cursor, selection, buffer, ...)
- Input prompts with completions, highlights, and normal mode
- Select and define re-usable prompts
- Execute commands
- Monitor and respond to events
- Accept/reject and reload edits
- _Vim-y_ — operator and dot-repeat
- Simple and sensible defaults to get you started quickly

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

vim.o.autoread = true -- Required for `vim.g.opencode_opts.events.reload`

-- Recommended/example keymaps
vim.keymap.set({ "n", "x" }, "<leader>oa", function() require("opencode").ask("@this: ") end, { desc = "Ask OpenCode…" })
vim.keymap.set({ "n", "x" }, "<leader>os", function() require("opencode").select() end,       { desc = "Select OpenCode…" })

vim.keymap.set({ "n", "x" }, "go",  function() return require("opencode").operator("@this ") end,        { desc = "Append range to OpenCode", expr = true })
vim.keymap.set("n",          "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Append line to OpenCode", expr = true })

vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end,   { desc = "Scroll OpenCode up" })
vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll OpenCode down" })
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
      -- Your configuration, if any; goto definition on the type or field for details
    }

    vim.o.autoread = true -- Required for `vim.g.opencode_opts.events.reload`

    -- Recommended/example keymaps
    vim.keymap.set({ "n", "x" }, "<leader>oa", function() require("opencode").ask("@this: ") end, { desc = "Ask OpenCode…" })
    vim.keymap.set({ "n", "x" }, "<leader>os", function() require("opencode").select() end,       { desc = "Select OpenCode…" })

    vim.keymap.set({ "n", "x" }, "go",  function() return require("opencode").operator("@this ") end,        { desc = "Append range to OpenCode", expr = true })
    vim.keymap.set("n",          "goo", function() return require("opencode").operator("@this ") .. "_" end, { desc = "Append line to OpenCode", expr = true })

    vim.keymap.set("n", "<S-C-u>", function() require("opencode").command("session.half.page.up") end,   { desc = "Scroll OpenCode up" })
    vim.keymap.set("n", "<S-C-d>", function() require("opencode").command("session.half.page.down") end, { desc = "Scroll OpenCode down" })
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

> [!TIP]
> Run `:checkhealth opencode` after setup.

### Integrations

<details>
<summary><a href="https://github.com/folke/snacks.nvim">snacks.nvim</a></summary>

```lua
require("snacks").setup({
  input = {
    enabled = true, -- Enhances `ask()`
  },
  picker = {
    enabled = true, -- Enhances `select()`
    actions = {
      ---@param picker snacks.Picker
      opencode_send = function(picker)
        local items = vim.tbl_map(function(item) ---@param item snacks.picker.Item
          return item.file
            and require("opencode").format({ path = item.file, from = item.pos, to = item.end_pos })
            or item.text
        end, picker:selected({ fallback = true }))

        require("opencode").prompt(table.concat(items, ", ") .. " ")
      end,
    },
    win = {
      input = {
        keys = {
          ["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
        },
      },
    },
  },
})
```

</details>

<details>
<summary><a href="https://github.com/nvim-lualine/lualine.nvim">lualine.nvim</a></summary>

```lua
require("lualine").setup({
  sections = {
    lualine_z = {
      {
        -- Shows the currently connected server and its status
        require("opencode").statusline,
      },
    }
  }
})
```

</details>

## ⚙️ Configuration

`opencode.nvim` provides a rich and reliable default experience — see all available options and their defaults [here](./lua/opencode/config.lua).

### Contexts

`opencode.nvim` replaces placeholders in prompts with the corresponding context:

| Placeholder    | Context                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `@this`        | Range or selection if any, else cursor position                         |
| `@buffer`      | Current buffer                                                          |
| `@buffers`     | Open buffers                                                            |
| `@visible`     | Visible text                                                            |
| `@diagnostic`  | Diagnostics within the range or selection if any, else under the cursor |
| `@diagnostics` | Current buffer diagnostics                                              |
| `@quickfix`    | Quickfix list                                                           |
| `@marks`       | Global marks                                                            |

> [!TIP]
> OpenCode reads referenced files from disk — save your changes!

### Prompts

Select prompts to review, explain, and improve your code:

| Name          | Prompt                                                                 |
| ------------- | ---------------------------------------------------------------------- |
| `diagnostics` | Explain `@diagnostics`                                                 |
| `document`    | Add comments documenting `@this`                                       |
| `explain`     | Explain `@this` and its context                                        |
| `fix`         | Fix `@diagnostics`                                                     |
| `implement`   | Implement `@this`                                                      |
| `optimize`    | Optimize `@this` for performance and readability                       |
| `review`      | Review `@this` for correctness and readability                         |
| `test`        | Add tests for `@this`                                                  |

### Server

Run `opencode` locally however you like and `opencode.nvim` will find them! Or point `vim.g.opencode_opts.server.url` to a specific server, including remotes.

> [!IMPORTANT]
> You _must_ run `opencode` with the `--port` flag to expose its server.

If `opencode.nvim` can't find a running `opencode`, it starts one via `vim.g.opencode_opts.server.start`, defaulting to `term://opencode --port`.

<details>
<summary><a href="https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md">snacks.terminal</a></summary>

```lua
local opencode_cmd = 'opencode --port'
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
-- Avoid <leader> here — Neovim watches for keymaps in terminal mode, so your leader key will have input delay.
vim.keymap.set({ 'n', 't' }, '<C-.>', function()
  require('snacks.terminal').toggle(opencode_cmd, snacks_terminal_opts)
end, { desc = 'Toggle OpenCode' })

-- Optionally show upon submitting prompt
vim.api.nvim_create_autocmd('User', {
  pattern = { 'OpencodeEvent:tui.command.execute' },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    if event.properties.command == 'prompt.submit' then
      local win = require('snacks.terminal').get(opencode_cmd, { create = false })
      if win then
        win:show()
      end
    end
  end,
})
```

</details>

## 🚀 Usage

### Ask — `require("opencode").ask()`

Input a prompt for OpenCode.

- End the prompt with a space to append instead of submit.
- Press `<Up>` to browse recent asks.
- Highlights and completes contexts and OpenCode subagents.
  - Press `<Tab>` to trigger built-in completion.
  - Provided by in-process LSP when using `snacks.input`.

### Select — `require("opencode").select()`

Select from all `opencode.nvim` functionality.

- Prompts
- Commands
- Servers

Highlights and previews items when using `snacks.picker`.

### Prompt — `require("opencode").prompt()`

Prompt OpenCode.

- End the prompt with a space to append instead of submit.
- Injects configured contexts.
- OpenCode will interpret references to files or subagents.

### Operator — `require("opencode").operator()`

Wraps `prompt` as an operator, supporting ranges and dot-repeat.

### Command — `require("opencode").command()`

Command OpenCode:

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

## 👀 Events

`opencode.nvim` forwards OpenCode's Server-Sent-Events as an `OpencodeEvent` autocmd:

```lua
-- Handle OpenCode events
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent:*", -- Optionally filter event types
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type string
    local url = args.data.url

    -- See the available event types and their properties
    vim.notify(vim.inspect(event))
    -- Do something useful
    if event.type == "session.idle" then
      vim.notify("OpenCode finished responding")
    end
  end,
})
```

### Edits

When OpenCode edits a file, `opencode.nvim` automatically reloads the corresponding buffer.

### Permissions

When OpenCode requests a permission, `opencode.nvim` waits for idle to ask you to approve or deny it.

#### Edits

For edit requests, `opencode.nvim` opens the target file in a new tab and uses Neovim's `:diffpatch` to display the proposed changes side-by-side. See `:h 'diffopt'` for customization.

| Keymap  | Function                                                                      |
| ------- | ----------------------------------------------------------------------------- |
| `da`    | Accept the entire edit request                                                |
| `dr`    | Reject the entire edit request                                                |
| `]c/[c` | Next/prev change                                                              |
| `dp`    | Natively accept _only_ the hunk under the cursor, and reject the edit request |
| `do`    | Natively reject _only_ the hunk under the cursor, and reject the edit request |
| `q`     | Close the diff                                                                |

## 🙏 Acknowledgments

- Inspired by [nvim-aider](https://github.com/GeorgesAlkhouri/nvim-aider), [neopencode.nvim](https://github.com/loukotal/neopencode.nvim), and [sidekick.nvim](https://github.com/folke/sidekick.nvim).
- Uses OpenCode's TUI for simplicity — see [sudo-tee/opencode.nvim](https://github.com/sudo-tee/opencode.nvim) for a Neovim frontend.
- [mcp-neovim-server](https://github.com/bigcodegen/mcp-neovim-server) may better suit you, but it lacks customization and tool calls are slow and unreliable.
