local M = {}

---Wraps `vim.system` in a `Promise`, catching synchronous executor errors.
---Rejects on exit code > 1 with code and stderr.
---Otherwise resolves to stdout.
---
---@param cmd string[]
---@return Promise<string>
function M.system(cmd)
  return require("opencode.promise").new(function(resolve, reject)
    local ok, err = pcall(function()
      vim.system(cmd, { text = true }, function(obj)
        if obj.code > 1 then -- exit code 1 is expected for our uses - indicates no results for pgrep and lsof
          reject(string.format("`%s` failed with code %d\n%s", cmd[1], obj.code, obj.stderr))
        else
          resolve(obj.stdout)
        end
      end)
    end)
    if not ok then
      -- `vim.system` can error synchronously in the executor, e.g. can't find the given command
      return reject(string.format("Failed to call `%s`: %s", cmd[1], err))
    end
  end)
end

return M
