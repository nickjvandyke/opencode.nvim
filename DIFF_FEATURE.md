# OpenCode Diff Review Feature

This feature provides PR-style review of changes made by OpenCode, allowing you to review, navigate, and accept/reject file edits.

## Overview

OpenCode supports **two different diff viewing modes** to suit your preferences:

### 1. Enhanced Mode (Default - No Dependencies)

Uses vim's built-in diff-mode with side-by-side comparison and a custom file panel. **This is the default mode** - works out of the box!

**Features:**
- Side-by-side diff with syntax highlighting
- Custom file panel showing all changed files
- Per-hunk staging with `a`/`r` keymaps
- File navigation with `<Tab>`/`<S-Tab>`
- Hunk navigation with `]x`/`[x`
- Single tab for all files
- No external dependencies required

**Configuration:**
```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      diff_mode = "enhanced",  -- This is the default
    },
  },
}
```

### 2. Unified Mode (Minimal)

Simple unified diff view in a single buffer for lightweight reviews.

**Features:**
- Minimal UI
- Unified diff format (like `git diff`)
- File-level accept/reject
- Lightweight and fast

**Configuration:**
```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      diff_mode = "unified",
    },
  },
}
```

## Keybindings

### Enhanced Mode

**Diff View:**
- `gp` - Toggle file panel
- `<Tab>` - Next file
- `<S-Tab>` - Previous file
- `]x` - Next hunk
- `[x` - Previous hunk
- `a` - Accept current hunk (keep change)
- `r` - Reject current hunk (revert change)
- `A` - Accept all hunks in current file
- `R` - Revert entire current file
- `q` - Close diff view

**File Panel:**
- `<Enter>` - Jump to selected file
- `gp` - Close panel
- `q` - Close diff view

### Unified Mode

- `n` - Next file
- `p` - Previous file
- `a` - Accept this file (keep changes)
- `r` - Reject this file (revert to original)
- `A` - Accept all files
- `R` - Reject all files
- `q` - Close review

## Per-Hunk Staging

**Enhanced mode** supports per-hunk accept/reject operations, allowing you to selectively keep or discard individual changes within a file.

**Accept Hunk (`a`):**
1. Position cursor on a hunk you want to keep
2. Press `a` to accept
3. Hunk disappears from diff (both sides now match)
4. Change is kept in the actual file

**Reject Hunk (`r`):**
1. Position cursor on a hunk you want to revert
2. Press `r` to reject  
3. Hunk disappears from diff (both sides now match)
4. Change is reverted in the actual file

**Accept All (`A`):**
- Accept all remaining hunks in the current file
- All changes are kept

**Implementation:** Uses vim's built-in diff commands (`diffput` to accept, `diffget` to reject).

## Configuration

**Full configuration options:**

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = true,           -- Enable diff review (default: true)
      diff_mode = "enhanced",   -- "enhanced" | "unified" (default: "enhanced")
      open_in_tab = false,      -- For unified mode (default: false)
    },
  },
}
```

**Disable diff review:**

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = false,
    },
  },
}
```

## File Panel

### Enhanced Mode Panel

Shows a list of changed files with stats:

```
OpenCode Changed Files
────────────────────────────────────────
  
▶ 1. config.lua +12 -5
  2. diff.lua +87 -34
  3. health.lua +8 -15

────────────────────────────────────────
Keymaps:
  <Enter>  Jump to file
  <Tab>    Next file
  <S-Tab>  Previous file
  ]x       Next hunk
  [x       Previous hunk
  a        Accept hunk
  r        Reject hunk
  A        Accept all hunks
  gp       Toggle panel
  R        Revert file
  q        Close diff
```

- **Dynamic width**: 20% of screen (minimum 25 columns)
- **▶ marker**: Shows current file
- **Stats**: `+additions -deletions` for each file
- **Full keymap reference**: Built into panel footer

## Health Check

Run `:checkhealth opencode` to verify your configuration:

**Enhanced mode:**
```
opencode.nvim [diff review]
  - OK: Session diff review is enabled.
  - OK: Diff mode: Enhanced (side-by-side vim diff-mode with file panel)
```

**Unified mode:**
```
opencode.nvim [diff review]
  - OK: Session diff review is enabled.
  - OK: Diff mode: Unified (simple unified diff view)
```

## Mode Comparison

| Feature | Enhanced | Unified |
|---------|----------|---------|
| **Dependencies** | None | None |
| **UI Quality** | ⭐⭐⭐⭐ | ⭐⭐ |
| **File Panel** | Custom | None |
| **Side-by-side** | ✅ | ❌ |
| **Per-hunk staging** | ✅ | ❌ |
| **File navigation** | ✅ | ✅ |
| **Hunk navigation** | ✅ | ❌ |
| **Syntax highlighting** | ✅ | Limited |

**Recommendations:**
- **Best UX**: Use `diff_mode = "enhanced"` (default) - great UX without any plugins
- **Minimal**: Use `diff_mode = "unified"` for simple, lightweight reviews

## How It Works

1. **AI makes edits** across multiple files
2. **Files are written** to disk immediately  
3. **`message.updated` event fires** with change data
4. **Diff mode determined** from config
5. **Review UI opens** automatically based on mode:
   - **Enhanced**: Custom vim diff-mode implementation
   - **Unified**: Simple unified diff buffer
6. **Navigate and stage:**
   - Use keymaps to navigate files/hunks
   - Accept or reject individual hunks (enhanced mode)
   - Changes persist immediately to disk

**Restore Strategy:** All modes use the `before` content from the event (no Git required):

```lua
-- To revert a file:
vim.fn.writefile(vim.split(file_data.before, "\n"), file_data.file)

-- To revert a hunk:
vim.cmd("diffget")  -- Pull original from "before" buffer
vim.cmd("write")
```

## Files

**Core Implementation:**
- `plugin/events/session_diff.lua` - Event listener
- `lua/opencode/diff.lua` - Both diff modes
- `lua/opencode/config.lua` - Configuration
- `lua/opencode/health.lua` - Health check

## Future Enhancements

- [x] Side-by-side vim diff-mode view
- [x] File panel for navigation
- [x] Per-hunk accept/reject (staging)
- [ ] Configurable keybindings
- [ ] Auto-close after accepting all
- [ ] File filtering/search in panel
- [ ] Custom diff algorithms
