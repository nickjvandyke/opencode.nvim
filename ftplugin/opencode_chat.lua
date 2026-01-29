-- Filetype plugin for opencode_chat buffers
-- Provides syntax highlighting for chat messages

-- Enable markdown-like syntax for code blocks
vim.bo.commentstring = "<!-- %s -->"

-- Set up basic syntax highlighting
vim.cmd([[
  syntax match OpencodeHeaderUser "^### You$"
  syntax match OpencodeHeaderAssistant "^### Assistant$"
  syntax match OpencodeHeaderSystem "^### System$"
  syntax match OpencodeSeparator "^─\+$"
  syntax match OpencodeTypingIndicator "^▋$"

  highlight default link OpencodeHeaderUser Title
  highlight default link OpencodeHeaderAssistant Special
  highlight default link OpencodeHeaderSystem Comment
  highlight default link OpencodeSeparator Comment
  highlight default link OpencodeTypingIndicator WarningMsg
]])

-- Enable treesitter markdown highlighting if available
local ok, ts_highlight = pcall(require, "vim.treesitter.highlighter")
if ok then
  ok = pcall(vim.treesitter.start, vim.api.nvim_get_current_buf(), "markdown")
  if not ok then
    -- Fallback to basic markdown syntax
    vim.cmd("runtime! syntax/markdown.vim")
  end
else
  -- Fallback to basic markdown syntax
  vim.cmd("runtime! syntax/markdown.vim")
end
