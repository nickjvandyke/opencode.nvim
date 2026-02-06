---`opencode.nvim` public API.
local M = {}

M.ask = require("opencode.ui.ask").ask
M.select = require("opencode.ui.select").select
M.select_session = require("opencode.ui.select_session").select_session
M.select_server = require("opencode.ui.select_server").select_server

M.prompt = require("opencode.api.prompt").prompt
M.operator = require("opencode.api.operator").operator
M.command = require("opencode.api.command").command

M.toggle = require("opencode.provider").toggle
M.start = require("opencode.provider").start
M.stop = require("opencode.provider").stop

M.statusline = require("opencode.status").statusline

return M
