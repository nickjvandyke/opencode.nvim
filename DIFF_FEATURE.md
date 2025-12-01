# OpenCode Diff Review Feature

This feature provides PR-style review of changes made by OpenCode, allowing you to review, navigate, and accept/reject file edits.

## Enhanced Diff View (Default)

OpenCode provides an enhanced diff viewing experience using vim's built-in diff-mode with side-by-side comparison!

### Features

- **Side-by-side diff**: Split view with before/after comparison
- **Syntax highlighting**: Vim's native diff highlighting
- **Hunk navigation**: Jump between changes with `]c` / `[c`
- **File panel**: Toggleable list of all changed files (`gp`)
- **File navigation**: `<Tab>` / `<S-Tab>` to cycle through files
- **Revert support**: Press `R` to revert the current file
- **Single tab**: All files use the same tab for better workspace management
- **Standard vim diff**: All standard diff-mode commands work (`:h diff-mode`)

### How It Works

1. **Temp files created**: OpenCode creates temp files with `before` content
2. **Actual files contain**: The `after` content (already written)
3. **Side-by-side diff**: Temp file (left) vs actual file (right)
4. **Navigate seamlessly**: Switch between files in the same tab
5. **File panel**: See all changed files at a glance

### Keybindings (Enhanced Diff Mode)

- `gp` - Toggle file panel (shows all changed files)
- `<Tab>` - Next file
- `<S-Tab>` - Previous file
- `]c` - Next hunk (change)
- `[c` - Previous hunk (change)
- `R` - Revert current file to original
- `q` - Close diff view
- See `:h diff-mode` for more diff commands

### File Panel

Press `gp` to toggle a sidebar showing all changed files:

```
OpenCode Changed Files
────────────────────────────────────────
  
▶ 1. config.lua +12 -5
  2. diff.lua +87 -34
  3. health.lua +0 -15

────────────────────────────────────────
Press <Enter> to jump, gp to close panel
```

- `▶` indicates the current file
- `<Enter>` - Jump to selected file
- `gp` - Close panel
- `q` - Close entire diff view

## Configuration

**Enabled by default** - no configuration needed!

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = true,  -- PR-style review (default: true)
      use_enhanced_diff = true,  -- Use enhanced vim diff-mode (default: true)
      open_in_tab = false,  -- For basic mode: open in tab (default: false)
    },
  },
}
```

**To use basic unified diff view** (single buffer with diff output):

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      use_enhanced_diff = false,  -- Use basic unified diff view
    },
  },
}
```

**To disable diff review entirely:**

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = false,
    },
  },
}
```

## How It Works

1. **AI makes edits** across multiple files
2. **Files are written** to disk immediately
3. **`message.updated` event fires** with complete change data:
   - All modified files in one event
   - Each file includes `before` (original) and `after` (new) content
4. **Review UI opens** automatically:
   - **Enhanced mode** (default): Side-by-side diff in new tab with file panel
   - **Basic mode**: Unified diff view in split/tab
5. **Navigate and decide:**
   - **Enhanced mode**: `gp` for file panel, `<Tab>` / `<S-Tab>` for files, `]c` / `[c` for hunks, `R` to revert
   - **Basic mode**: `n` / `p` for files, `a` / `r` to accept/reject, `A` / `R` for all

**Restore Strategy:**

- Uses `before` content from `message.updated` event
- Writes original content back to disk
- Reloads buffer if open in editor
- No Git dependencies required

## Keybindings

### Enhanced Mode (Default)

When using enhanced diff view (side-by-side with vim diff-mode):
- `gp` - Toggle file panel
- `<Tab>` - Next file
- `<S-Tab>` - Previous file
- `]c` - Next hunk (change)
- `[c` - Previous hunk (change)
- `R` - Revert current file to original
- `q` - Close diff view

### Basic Mode (Unified Diff)

When enhanced mode is disabled:
- `n` - Next file
- `p` - Previous file
- `a` - Accept this file (keep changes)
- `r` - Reject this file (restore original using `before` content)
- `A` - Accept all files
- `R` - Reject all files
- `q` - Close review (keeps current state)

## Usage Example

### Testing Session Diff Review

1. **Enable the feature** (it's on by default)
2. **Ask OpenCode to make changes:**

   ```
   Update file1.txt and file2.txt with programming jokes
   ```

3. **Wait for OpenCode to finish**
4. **Review UI appears** showing all changes in side-by-side diff
5. **Navigate with `<Tab>`/`<S-Tab>`** or press `gp` for file panel
6. **Review hunks** with `]c`/`[c`
7. **Revert if needed** with `R`, or close with `q`

## Files

**Core Implementation:**

- `plugin/events/session_diff.lua` - Listens for `OpencodeEvent:message.updated`
- `lua/opencode/diff.lua` - Review UI and restore logic

## Current Limitations

### Enhanced Mode
1. **Manual acceptance** - Files stay changed until you revert them
2. **No per-hunk revert** - Must revert entire file (could be added with staging logic)
3. **Temp files** - Creates temp directory for before content (auto-cleaned on close)

### Basic Mode
1. **Simple diff display** - Shows before/after content using vim.diff(unified)
2. **No per-hunk review** - Accept/reject entire file only
3. **Limited navigation** - File-level only, no hunk jumping

**Recommendation**: Use enhanced mode (default) for the best experience!

## Future Enhancements

- [x] Side-by-side vim diff-mode view
- [x] File panel for navigation
- [x] Single tab with buffer switching
- [ ] Per-hunk accept/reject (staging)
- [ ] Floating window option for file panel
- [ ] Integration with other diff tools (vim-fugitive, mini.diff)
- [ ] Configurable keybindings
- [ ] Auto-close after accepting all
- [ ] File filtering/searching in multi-file reviews

## Architecture

### Event Flow

```
 → session.created
  → message.updated (user)
  → session.status (busy)
  → message.updated (assistant starts)
  → message.part.updated (streaming response)
  → [4x tool calls executed, files edited]
  → message.updated (finish: "tool-calls")
  → session.diff (ONE event with all cumulative changes in the session)
  → message.updated (Using this as the indicator for a Q&A cycle, only contains diff for files
  changed, not like session.diff that contains everything)
  → session.status (idle)
```

### Restore Strategy

Instead of Git stash/commit, we use the `before` content from the event:

```lua
-- message.updated event includes:
{
  summary = {
    diffs = {
      {
        file = "path/to/file.lua",
        before = "original content...",  -- ← We use this!
        after = "new content...",
        additions = 10,
        deletions = 5
      }
    }
  }
}

-- To revert:
vim.fn.writefile(vim.split(file_data.before, "\n"), file_data.file)
```

### Enhanced Diff Implementation

```lua
-- 1. Create temp directory
local temp_dir = vim.fn.tempname() .. "_opencode_diff"

-- 2. Write before content to temp files
local temp_before = temp_dir .. "/" .. filename .. ".before"
vim.fn.writefile(vim.split(before_content, "\n"), temp_before)

-- 3. Open side-by-side diff in single tab
vim.cmd("tabnew")
vim.cmd("edit " .. temp_before)  -- Left: before
vim.cmd("rightbelow vertical diffsplit " .. actual_file)  -- Right: after
vim.cmd("diffthis")  -- Enable diff mode

-- 4. Navigate between files in same tab
-- Just switch buffers in the same windows!
```
