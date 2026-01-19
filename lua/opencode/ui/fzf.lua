local M = {}

local config = require("opencode.config").opts.fzf or {}

local function is_buf_valid(buf)
  return vim.api.nvim_get_option_value("buftype", { buf = buf }) == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function strip_ansi_codes(str)
  local result = str
  result = result:gsub("\27%[[0-9;]*m", "")
  result = result:gsub("\27%[K", "")
  return result
end

local function strip_file_icon(str)
  local stripped = strip_ansi_codes(str)
  stripped = stripped:gsub("^%s*", "")
  local icon_and_space = stripped:match("^[^\32-\126]+%s+")
  if icon_and_space then
    stripped = stripped:sub(#icon_and_space + 1)
  end
  return stripped:match("^%s*(.-)%s*$")
end

local function format_file_for_opencode(filepath)
  local rel_path = vim.fn.fnamemodify(filepath, ":.")
  return "@" .. rel_path .. " "
end

local function send_files_to_opencode(files, prompt_prefix)
  if not files or #files == 0 then
    return
  end

  local file_contexts = {}
  for _, file in ipairs(files) do
    local clean_file = strip_file_icon(file)
    if clean_file and clean_file ~= "" then
      table.insert(file_contexts, format_file_for_opencode(clean_file))
    end
  end

  if #file_contexts == 0 then
    return
  end

  local prompt = table.concat(file_contexts, " ")
  if prompt_prefix and #prompt_prefix > 0 then
    prompt = prompt_prefix .. " " .. prompt
  end

  require("opencode").prompt(prompt)
end

function M.select_buffers(prompt_prefix)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not found. Please install fzf-lua to use this feature.", vim.log.levels.ERROR)
    return
  end

  local buffers = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if is_buf_valid(buf) then
      local bufname = vim.api.nvim_buf_get_name(buf)
      table.insert(buffers, {
        path = bufname,
        bufnr = buf,
        ordinal = bufname,
        display = bufname,
      })
    end
  end

  if #buffers == 0 then
    vim.notify("No valid buffers found", vim.log.levels.WARN)
    return
  end

  local opts = vim.tbl_deep_extend("force", {
    prompt = "Select buffers> ",
    previewer = false,
    file_icons = false,
    git_icons = false,
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "Tab to select multiple, Enter to confirm",
    },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        send_files_to_opencode(selected, prompt_prefix or config.prompt_prefix)
      end,
    },
  }, config.buffers or {})

  fzf.fzf_exec(
    function(cb)
      for _, buf in ipairs(buffers) do
        cb(buf.display)
      end
      cb(nil)
    end,
    opts
  )
end

function M.select_files(prompt_prefix, opts)
  opts = opts or {}

  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not found. Please install fzf-lua to use this feature.", vim.log.levels.ERROR)
    return
  end

  local files_opts = vim.tbl_deep_extend("force", {
    prompt = "Select files> ",
    previewer = "builtin",
    file_icons = false,
    color_icons = false,
    git_icons = false,
    fzf_opts = {
      ["--multi"] = "",
      ["--header"] = "Tab to select multiple, Enter to confirm",
    },
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        send_files_to_opencode(selected, prompt_prefix or config.prompt_prefix)
      end,
    },
  }, config.files or {})

  if opts.cwd then
    files_opts.cwd = opts.cwd
  end

  fzf.files(files_opts)
end

function M.ask_with_files(prompt_text)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not found. Please install fzf-lua to use this feature.", vim.log.levels.ERROR)
    return
  end

  local function show_file_selector()
    vim.ui.select({ "buffers", "project files" }, { prompt = "Select source: " }, function(choice)
      if not choice then
        return
      end

      if choice == "buffers" then
        M.select_buffers(prompt_text or config.prompt_prefix)
      elseif choice == "project files" then
        M.select_files(prompt_text or config.prompt_prefix)
      end
    end)
  end

  show_file_selector()
end

function M.append_files_to_current_prompt()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    vim.notify("fzf-lua not found. Please install fzf-lua to use this feature.", vim.log.levels.ERROR)
    return
  end

  local function show_file_selector()
    vim.ui.select({ "buffers", "project files" }, { prompt = "Select source: " }, function(choice)
      if not choice then
        return
      end

      if choice == "buffers" then
        M.select_buffers(config.prompt_prefix)
      elseif choice == "project files" then
        M.select_files(config.prompt_prefix)
      end
    end)
  end

  show_file_selector()
end

return M
