local M = {}

---@class opencode.integrations.diff.MiniDiffOpts
---@field open_cmd? string Ex command used to open the target file. Defaults to `tabnew`.
---@field ensure_overlay? boolean Whether to enable `mini.diff` overlay while the edit session is active. Defaults to `true`.

---@param buf integer
---@param line integer
local function accept_hunk(buf, line)
  local mini_diff = require("mini.diff")
  mini_diff.do_hunks(buf, "reset", { line_start = line, line_end = line })
end

---Create an edit renderer backed by `mini.diff`.
---
---Falls back to the built-in `:diffpatch` renderer when `mini.diff` is not available
---or the proposed text cannot be computed.
---
---@param opts? opencode.integrations.diff.MiniDiffOpts
---@return fun(ctx: opencode.events.permissions.edits.Context): opencode.events.permissions.edits.Session?
function M.mini_diff(opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    open_cmd = "tabnew",
    ensure_overlay = true,
  })

  return function(ctx)
    local ok, mini_diff = pcall(require, "mini.diff")
    if not ok then
      return ctx.open_default()
    end

    local proposed = ctx.proposed_text()
    if not proposed then
      return ctx.open_default()
    end

    vim.cmd(("%s %s"):format(opts.open_cmd, vim.fn.fnameescape(ctx.filepath)))
    local bufnr = vim.api.nvim_get_current_buf()
    local previous_state = mini_diff.get_buf_data(bufnr)
    local previous_config = vim.deepcopy(vim.b[bufnr].minidiff_config)

    pcall(mini_diff.disable, bufnr)
    vim.b[bufnr].minidiff_config = { source = mini_diff.gen_source.none() }

    local enabled = pcall(mini_diff.enable, bufnr)
    local ref_ok = enabled and pcall(mini_diff.set_ref_text, bufnr, proposed)
    if not ref_ok then
      pcall(vim.cmd, "tabclose")
      return ctx.open_default()
    end

    if opts.ensure_overlay then
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        local buf_data = mini_diff.get_buf_data(bufnr) or {}
        if not buf_data.overlay then
          pcall(mini_diff.toggle_overlay, bufnr)
        end
      end)
    end

    return {
      bufnr = bufnr,
      close = function()
        pcall(mini_diff.disable, bufnr)
        vim.b[bufnr].minidiff_config = previous_config

        if previous_state then
          pcall(mini_diff.enable, bufnr)
          if previous_state.ref_text ~= nil then
            pcall(mini_diff.set_ref_text, bufnr, previous_state.ref_text)
          end
          if previous_state.overlay then
            pcall(mini_diff.toggle_overlay, bufnr)
          end
        end
      end,
      next_hunk = function()
        mini_diff.goto_hunk("next")
      end,
      prev_hunk = function()
        mini_diff.goto_hunk("prev")
      end,
      accept_hunk = function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        accept_hunk(bufnr, line)
      end,
    }
  end
end

return M
