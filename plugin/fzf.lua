if not pcall(require, "fzf-lua") then
  return
end

vim.api.nvim_create_user_command("OpencodeFzfBuffers", function(opts)
  local prompt_prefix = opts.fargs[1] or ""
  require("opencode").fzf.select_buffers(prompt_prefix)
end, {
  nargs = "?",
  desc = "Select buffers using fzf-lua and send to opencode",
})

vim.api.nvim_create_user_command("OpencodeFzfFiles", function(opts)
  local prompt_prefix = opts.fargs[1] or ""
  require("opencode").fzf.select_files(prompt_prefix)
end, {
  nargs = "?",
  desc = "Select project files using fzf-lua and send to opencode",
})

vim.api.nvim_create_user_command("OpencodeFzfAsk", function(opts)
  local prompt_text = opts.fargs[1] or ""
  require("opencode").fzf.ask_with_files(prompt_text)
end, {
  nargs = "?",
  desc = "Ask opencode with files selected via fzf-lua",
})

vim.api.nvim_create_user_command("OpencodeFzfAppend", function()
  require("opencode").fzf.append_files_to_current_prompt()
end, {
  nargs = 0,
  desc = "Append files selected via fzf-lua to current opencode prompt",
})
