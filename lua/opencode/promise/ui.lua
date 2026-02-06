local M = {}

---Wraps `vim.ui.select` in a `Promise`.
---
---@generic T
---@param items T[]
---@param opts table
---@return Promise<T>
function M.select(items, opts)
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    vim.ui.select(items, opts, function(choice)
      if choice == nil then
        return reject()
      else
        resolve(choice)
      end
    end)
  end)
end

---Wraps `vim.ui.input` in a `Promise`.
---
---@param opts table
---@return Promise<string>
function M.input(opts)
  local Promise = require("opencode.promise")
  return Promise.new(function(resolve, reject)
    vim.ui.input(opts, function(input)
      if input == nil or input == "" then
        return reject()
      else
        resolve(input)
      end
    end)
  end)
end

return M
