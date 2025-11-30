# OpenCode Diff Review Feature

This feature provides PR-style review of changes made by OpenCode, allowing you to review, navigate, and accept/reject file edits.

## Configuration

**Enabled by default** - no configuration needed!

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = true,  -- PR-style review (default: true)
      open_in_tab = false,  -- Open review in tab instead of vsplit(default: false)
    },
  },
}
```

**To disable:**

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
4. **Review UI opens** showing current file's changes
5. **Navigate and decide:**
   - `n` - Next file
   - `p` - Previous file
   - `a` - Accept this file (keep changes)
   - `r` - Reject this file (restore original using `before` content)
   - `A` - Accept all files
   - `R` - Reject all files
   - `q` - Close review (keeps current state)

**Restore Strategy:**

- Uses `before` content from `messaged.updated` event
- Writes original content back to disk
- Reloads buffer if open in editor
- No Git dependencies required
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
4. **Review UI appears** showing all changes
5. **Navigate with `n`/`p`**, accept with `a`, or reject with `r`

## Files

**Core Implementation:**

- `plugin/events/session_diff.lua` - Listens for `OpencodeEvent:message.updated`
- `lua/opencode/diff.lua` - Review UI and restore logic

## Current Limitations

1. **Simple diff display** - Shows before/after content using vim.diff(unified)
3. **No per-hunk review** - Accept/reject entire file only

## Future Enhancements

- [x] Proper unified diff rendering with syntax highlighting
- [ ] Per-hunk accept/reject
- [ ] Floating window option
- [ ] Side-by-side diff view
- [ ] Integration with existing diff tools (vim-fugitive, diffview.nvim)
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
-- session.diff event includes:
{
  diff = {
    {
      file = "path/to/file.lua",
      before = "original content...",  -- ← We use this!
      after = "new content...",
      additions = 10,
      deletions = 5
    }
  }
}

-- To revert:
vim.fn.writefile(vim.split(file_data.before, "\n"), file_data.file)
```
