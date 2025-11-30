# OpenCode Diff Review Feature

This feature provides PR-style review of changes made by OpenCode, allowing you to review, navigate, and accept/reject file edits.

## Configuration

**Enabled by default** - no configuration needed!

```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = true,  -- PR-style review (default: true)
    },
  },
}
```

**To disable:**
```lua
vim.g.opencode_opts = {
  events = {
    session_diff = {
      enabled = false,  -- Disable diff review
    },
  },
}
```

## How It Works

1. **AI makes edits** across multiple files
2. **Files are written** to disk immediately
3. **`session.diff` event fires** with complete change data:
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
- Uses `before` content from `session.diff` event
- Writes original content back to disk
- Reloads buffer if open in editor
- No Git dependencies required
   - `A` - Accept all files
   - `R` - Reject all files
   - `q` - Close review (keeps current state)

**Restore Strategy:**
- Uses `before` content from `session.diff` event
- Writes original content back to disk
- Reloads buffer if open in editor
- No Git dependencies required

### Permission-Based Review

1. **AI wants to edit file** → Permission request fires
2. **Shows unified diff** in vertical split
3. **User decides:**
   - `<leader>aa` - Accept edit (file will be written)
   - `<leader>ar` or `q` - Reject edit (file won't be modified)
4. **Repeat for each file** individually

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
- `plugin/events/session_diff.lua` - Listens for `OpencodeEvent:session.diff`
- `lua/opencode/diff.lua` - Review UI and restore logic
- `lua/opencode/config.lua` - Configuration options
- `lua/opencode/events.lua` - Type definitions

**Legacy (kept for compatibility):**
- `plugin/events/permissions.lua` - Permission-based review (disabled by default)

## Current Limitations

1. **Simple diff display** - Shows before/after content, not unified diff format (yet)
2. **No syntax highlighting** - Displays as plain diff format
3. **No per-hunk review** - Accept/reject entire file only
4. **Buffer management** - Opens in vertical split (not configurable yet)

## Future Enhancements

- [ ] Proper unified diff rendering with syntax highlighting
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
AI makes edits
    ↓
Files written to disk
    ↓
OpencodeEvent:session.diff fires
    ↓
plugin/events/session_diff.lua catches it
    ↓
lua/opencode/diff.lua handles review
    ↓
User reviews in split buffer
    ↓
Accept (keep) or Reject (restore from 'before' content)
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

**Benefits:**
- No Git dependency
- No pollution of Git history
- 100% accurate (exact original content)
- Works in any project

## Comparison: Permission vs Session Diff

| Aspect | Permission Review | Session Diff Review |
|--------|------------------|---------------------|
| **Timing** | Before file write | After file write |
| **Unified view** | ❌ One file at a time | ✅ All files together |
| **Navigation** | ❌ Sequential only | ✅ Free navigation |
| **Configuration** | Needs OpenCode config | Works out of the box |
| **Undo method** | Don't write file | Restore from `before` |
| **Reliability** | ⚠️ Works sometimes | ✅ Always works |

**Recommendation:** Use Session Diff Review for better UX.
