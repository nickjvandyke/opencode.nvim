local M = {}

--- Get the markdown type to use based on the filename. First gets the neovim type
--- for the file. Then apply any specific overrides. Falls back to using the file
--- extension if nothing else matches
--- @param filename string filename, possibly including path
--- @return string markdown_filetype
function M.get_markdown_filetype(filename)
  if not filename or filename == "" then
    return ""
  end

  local file_type_overrides = {
    javascriptreact = "jsx",
    typescriptreact = "tsx",
    sh = "bash",
    yaml = "yml",
    text = "txt", -- nvim 0.12-nightly returns text as the type which breaks our unit tests
  }

  local file_type = vim.filetype.match({ filename = filename }) or ""

  if file_type_overrides[file_type] then
    return file_type_overrides[file_type]
  end

  if file_type and file_type ~= "" then
    return file_type
  end

  return vim.fn.fnamemodify(filename, ":e")
end

---@param title string
---@param opts? table config of nvim_open_win()
---@return integer bufid
---@return integer winid
function M.create_scratch_floatwin(title, opts)
  title = string.format(" %s ", title)
  local bufid = vim.api.nvim_create_buf(false, true)
  local bo = vim.bo[bufid]
  bo.bufhidden = "wipe"
  bo.buftype = "nofile"
  bo.swapfile = false
  local width = math.min(vim.o.columns, 100)
  local col = math.floor((vim.o.columns - width) / 2)
  local winid = vim.api.nvim_open_win(
    bufid,
    true,
    vim.tbl_deep_extend("force", {
      relative = "editor",
      row = math.floor((vim.o.lines - 2) / 4),
      col = col,
      width = width,
      height = math.floor(vim.o.lines / 2),
      border = "rounded",
      title = title,
      title_pos = "center",
    }, opts or {})
  )
  -- basic setup
  vim.opt_local.number = false
  vim.opt_local.colorcolumn = {}
  return bufid, winid
end

return M
