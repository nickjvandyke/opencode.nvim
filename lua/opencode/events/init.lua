local M = {}

---@class opencode.events.Opts
---
---Whether to subscribe to Server-Sent Events (SSE) from `opencode` and execute `OpencodeEvent:<event.type>` autocmds.
---@field enabled? boolean
---
---Reload buffers edited by `opencode` in real-time.
---Requires `vim.o.autoread = true`.
---@field reload? boolean
---
---Add files edited by `opencode` to the quickfix list.
---@field quickfix? boolean
---
---@field permissions? opencode.events.permissions.Opts

return M
