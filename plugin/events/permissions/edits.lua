---@type string?
local current_edit_request_id = nil
---@type nil|integer
local diff_tabpage = nil
---@type nil|integer
local diff_tabpage_number = nil
---@type nil|integer
local diff_bufnr = nil
---@type opencode.events.permissions.edits.Session?
local diff_session = nil
---@type opencode.events.permissions.edits.ActiveRequest?
local active_request = nil
local keymaps_registered = false

---@class opencode.events.permissions.edits.ActiveRequest
---@field request_id string
---@field port number

---@type opencode.events.permissions.edits.Keymaps
local default_keymaps = {
  accept = "da",
  reject = "dr",
  close = "q",
  accept_hunk = "dp",
  reject_hunk = "do",
  next_hunk = "]c",
  prev_hunk = "[c",
}

---@class opencode.events.permissions.edits.Opts
---
---Whether to display proposed edits from `opencode` and allow accepting/rejecting them from within Neovim.
---@field enabled? boolean
---
---Custom renderer for proposed edits. Defaults to Neovim's built-in `:diffpatch`.
---Receives a render context and can return a session with hunk actions and cleanup hooks.
---@field renderer? fun(ctx: opencode.events.permissions.edits.Context): opencode.events.permissions.edits.Session?
---@field keymaps? opencode.events.permissions.edits.Keymaps

---@class opencode.events.permissions.edits.Keymaps
---@field accept? string|false
---@field reject? string|false
---@field close? string|false
---@field accept_hunk? string|false
---@field reject_hunk? string|false
---@field next_hunk? string|false
---@field prev_hunk? string|false

---@class opencode.events.permissions.edits.Session
---@field bufnr? integer
---@field close? fun()
---@field next_hunk? fun()
---@field prev_hunk? fun()
---@field accept_hunk? fun()
---@field reject_hunk? fun()

---@class opencode.events.permissions.edits.Context
---@field request_id string
---@field filepath string
---@field diff string
---@field state table
---@field proposed_text fun(): string?
---@field permit fun(reply: opencode.server.permission.Reply)
---@field close fun()
---@field open_default fun(): opencode.events.permissions.edits.Session?

---@return integer?
local function current_line()
  if not diff_bufnr or not vim.api.nvim_buf_is_valid(diff_bufnr) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  return cursor[1]
end

---@param reply opencode.server.permission.Reply
---@param port number
---@param request_id string
local function permit(reply, port, request_id)
  require("opencode.server").new(port):next(function(server) ---@param server opencode.server.Server
    server:permit(request_id, reply)
  end)
end

local function cleanup_diff()
  if diff_session and diff_session.close then
    pcall(diff_session.close)
  end

  diff_session = nil
  diff_bufnr = nil
  active_request = nil
end

local function close_diff()
  current_edit_request_id = nil
  cleanup_diff()

  if diff_tabpage and vim.api.nvim_tabpage_is_valid(diff_tabpage) then
    vim.api.nvim_set_current_tabpage(diff_tabpage)
    vim.cmd("tabclose")
  end

  diff_tabpage = nil
  diff_tabpage_number = nil
end

---@param msg string
local function notify_info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "opencode" })
end

---@return opencode.events.permissions.edits.Session?, opencode.events.permissions.edits.ActiveRequest?
local function get_active_diff()
  if not diff_session or not active_request or not current_edit_request_id then
    notify_info("No active opencode edit diff")
    return nil, nil
  end

  return diff_session, active_request
end

---@param filepath string
---@return string
local function normalize_filepath(filepath)
  local normalized = vim.fs.normalize(filepath)
  if vim.startswith(normalized, "/") then
    return normalized
  end

  local absolute_like = vim.fs.normalize("/" .. normalized)
  if vim.uv.fs_stat(absolute_like) then
    return absolute_like
  end

  local cwd_relative = vim.fs.normalize(vim.fn.getcwd() .. "/" .. normalized)
  if vim.uv.fs_stat(cwd_relative) then
    return cwd_relative
  end

  return absolute_like
end

---@param filepath string
---@param diff string
---@return string?
local function patched_text(filepath, diff)
  local patch_filepath = vim.fn.tempname() .. ".patch"
  local output_filepath = vim.fn.tempname()
  filepath = normalize_filepath(filepath)

  if vim.fn.filereadable(filepath) ~= 1 then
    vim.notify("Target file for opencode edit renderer does not exist: " .. filepath, vim.log.levels.ERROR, { title = "opencode" })
    return nil
  end

  if vim.fn.writefile(vim.split(diff, "\n"), patch_filepath) ~= 0 then
    vim.notify("Failed to write patch file for opencode edit renderer", vim.log.levels.ERROR, { title = "opencode" })
    return nil
  end

  local result =
    vim.system({ "patch", "--silent", "--output", output_filepath, filepath, patch_filepath }, { text = true }):wait()
  if result.code ~= 0 then
    vim.notify(
      "Failed to compute proposed text for opencode edit renderer: " .. filepath,
      vim.log.levels.ERROR,
      { title = "opencode" }
    )
    return nil
  end

  return table.concat(vim.fn.readfile(output_filepath), "\n")
end

---@param filepath string
---@param diff string
---@return opencode.events.permissions.edits.Session?
local function open_with_diffpatch(filepath, diff)
  filepath = normalize_filepath(filepath)
  local patch_filepath = vim.fn.tempname() .. ".patch"
  if vim.fn.writefile(vim.split(diff, "\n"), patch_filepath) ~= 0 then
    vim.notify("Failed to write patch file to diff opencode edit request", vim.log.levels.ERROR, { title = "opencode" })
    return nil
  end

  vim.cmd("silent! bwipeout " .. vim.fn.fnameescape(filepath .. ".new"))
  vim.cmd("tabnew " .. vim.fn.fnameescape(filepath))
  local ok = pcall(vim.cmd, "silent vert diffpatch " .. vim.fn.fnameescape(patch_filepath))
  if not ok then
    vim.cmd("tabclose")
    return nil
  end

  return { bufnr = vim.api.nvim_get_current_buf() }
end

---@param session opencode.events.permissions.edits.Session
local function activate_session(session)
  diff_session = session
  diff_bufnr = session.bufnr or vim.api.nvim_get_current_buf()
  diff_tabpage = vim.api.nvim_get_current_tabpage()
  diff_tabpage_number = vim.api.nvim_tabpage_get_number(diff_tabpage)

  local tabclosed_group = vim.api.nvim_create_augroup("OpencodeEditTabClose", { clear = false })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = tabclosed_group,
    pattern = tostring(diff_tabpage_number),
    once = true,
    callback = function()
      cleanup_diff()
      diff_tabpage = nil
      diff_tabpage_number = nil
      current_edit_request_id = nil
    end,
    desc = "Clean up opencode edit diff state",
  })
end

local function accept_edit()
  local _, request = get_active_diff()
  if not request then
    return
  end

  current_edit_request_id = nil
  permit("once", request.port, request.request_id)
end

local function reject_edit()
  local _, request = get_active_diff()
  if not request then
    return
  end

  current_edit_request_id = nil
  permit("reject", request.port, request.request_id)
end

local function accept_hunk()
  local session, request = get_active_diff()
  if not session or not request then
    return
  end

  current_edit_request_id = nil
  permit("reject", request.port, request.request_id)

  if session.accept_hunk then
    session.accept_hunk()
    return
  end

  if vim.wo.diff then
    vim.cmd.normal({ "dp", bang = true })
    return
  end

  notify_info("Active opencode edit renderer does not support accepting hunks")
end

local function reject_hunk()
  local session, request = get_active_diff()
  if not session or not request then
    return
  end

  current_edit_request_id = nil
  permit("reject", request.port, request.request_id)

  if session.reject_hunk then
    session.reject_hunk()
    return
  end

  if vim.wo.diff then
    vim.cmd.normal({ "do", bang = true })
    return
  end

  notify_info("Active opencode edit renderer does not support rejecting hunks")
end

---@param direction "next"|"prev"
local function goto_hunk(direction)
  local session = get_active_diff()
  if not session then
    return
  end

  local method = direction == "next" and session.next_hunk or session.prev_hunk
  if method then
    method()
    return
  end

  if vim.wo.diff then
    vim.cmd.normal({ direction == "next" and "]c" or "[c", bang = true })
    return
  end

  notify_info("Active opencode edit renderer does not support hunk navigation")
end

local function register_keymaps()
  if keymaps_registered then
    return
  end

  local opts = require("opencode.config").opts.events.permissions.edits or {}
  local keymaps = vim.tbl_extend("force", default_keymaps, opts.keymaps or {})
  local mappings = {
    { lhs = keymaps.accept, rhs = accept_edit, desc = "Accept opencode edit" },
    { lhs = keymaps.reject, rhs = reject_edit, desc = "Reject opencode edit" },
    { lhs = keymaps.close, rhs = close_diff, desc = "Close opencode edit diff" },
    { lhs = keymaps.accept_hunk, rhs = accept_hunk, desc = "Accept opencode edit hunk" },
    { lhs = keymaps.reject_hunk, rhs = reject_hunk, desc = "Reject opencode edit hunk" },
    { lhs = keymaps.next_hunk, rhs = function() goto_hunk("next") end, desc = "Next opencode edit hunk" },
    { lhs = keymaps.prev_hunk, rhs = function() goto_hunk("prev") end, desc = "Previous opencode edit hunk" },
  }

  for _, mapping in ipairs(mappings) do
    if mapping.lhs then
      vim.keymap.set("n", mapping.lhs, mapping.rhs, { desc = mapping.desc })
    end
  end

  keymaps_registered = true
end

---@param filepath string
---@param diff string
---@param port number
---@param request_id string
---@return opencode.events.permissions.edits.Context
local function build_context(filepath, diff, port, request_id)
  filepath = normalize_filepath(filepath)
  local state = {}

  return {
    request_id = request_id,
    filepath = filepath,
    diff = diff,
    state = state,
    proposed_text = function()
      if state.proposed_text == nil then
        state.proposed_text = patched_text(filepath, diff)
      end

      return state.proposed_text
    end,
    permit = function(reply)
      permit(reply, port, request_id)
    end,
    close = function()
      close_diff()
    end,
    open_default = function()
      return open_with_diffpatch(filepath, diff)
    end,
  }
end

vim.api.nvim_create_autocmd("User", {
  group = vim.api.nvim_create_augroup("OpencodeEdits", { clear = true }),
  pattern = { "OpencodeEvent:permission.asked", "OpencodeEvent:permission.replied" },
  callback = function(args)
    ---@type opencode.server.Event
    local event = args.data.event
    ---@type number
    local port = args.data.port

    local opts = require("opencode.config").opts.events.permissions or {}
    if not opts.enabled or not opts.edits.enabled then
      return
    end

    if event.type == "permission.asked" and event.properties.permission == "edit" then
      local idle_delay_ms = opts.idle_delay_ms or 1000
      vim.notify(
        "`opencode` requested permission — awaiting idle…",
        vim.log.levels.INFO,
        { title = "opencode", timeout = idle_delay_ms }
      )
      require("opencode.util").on_user_idle(idle_delay_ms, function()
        local ok, err = pcall(function()
          register_keymaps()
          local filepath = event.properties.metadata.filepath
          local diff = event.properties.metadata.diff
          local renderer = opts.edits.renderer

          cleanup_diff()
          local ctx = build_context(filepath, diff, port, event.properties.id)
          local session = nil

          if renderer then
            local renderer_ok, result = pcall(renderer, ctx)
            if renderer_ok then
              session = result
            else
              vim.notify("Custom opencode edit renderer failed; falling back to diffpatch", vim.log.levels.WARN, {
                title = "opencode",
              })
            end
          end

          if not session then
            session = ctx.open_default()
          end

          if not session then
            vim.notify("Failed to display opencode edit diff", vim.log.levels.ERROR, { title = "opencode" })
            return
          end

          activate_session(session)
          current_edit_request_id = event.properties.id
          active_request = { request_id = event.properties.id, port = port }
        end)

        if not ok then
          vim.notify("Failed to handle opencode edit request: " .. err, vim.log.levels.ERROR, { title = "opencode" })
        end
      end)
    elseif event.type == "permission.replied" and current_edit_request_id == event.properties.requestID then
      close_diff()
    end
  end,
  desc = "Display opencode proposed edits",
})
