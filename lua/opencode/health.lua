---@module 'snacks'

local M = {}

function M.check()
  vim.health.start("opencode.nvim")

  local uname = vim.uv.os_uname()
  vim.health.info(string.format("OS: %s %s (%s)", uname.sysname, uname.release, uname.machine))

  vim.health.info("`nvim` version: `" .. tostring(vim.version()) .. "`.")

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
  local git_hash = vim.fn.system("cd " .. vim.fn.shellescape(plugin_dir) .. " && git rev-parse HEAD")
  if vim.v.shell_error == 0 then
    git_hash = vim.trim(git_hash)
    vim.health.info("`opencode.nvim` git commit hash: `" .. git_hash .. "`.")
  else
    vim.health.warn("Could not determine `opencode.nvim` git commit hash.")
  end

  vim.health.info("`vim.g.opencode_opts`: " .. (vim.g.opencode_opts and vim.inspect(vim.g.opencode_opts) or "`nil`"))

  if require("opencode.config").opts.events.reload and not vim.o.autoread then
    vim.health.warn(
      "`opts.events.reload = true` but `vim.o.autoread = false`: files edited by `opencode` won't be automatically reloaded in buffers.",
      {
        "Set `vim.o.autoread = true`",
        "Or set `vim.g.opencode_opts.events.reload = false`",
      }
    )
  end

  vim.health.start("opencode.nvim [binaries]")

  if vim.fn.executable("opencode") == 1 then
    local found_version = vim.fn.system("opencode --version")
    found_version = vim.trim(vim.split(found_version, "\n")[1])
    vim.health.ok("`opencode` available with version `" .. found_version .. "`.")

    local found_version_parsed = vim.version.parse(found_version)
    local latest_tested_version = "1.1.11"
    local latest_tested_version_parsed = vim.version.parse(latest_tested_version)
    if found_version_parsed and latest_tested_version_parsed then
      if latest_tested_version_parsed[1] ~= found_version_parsed[1] then
        vim.health.warn(
          "`opencode` version has a `major` version mismatch with latest tested version `"
            .. latest_tested_version
            .. "`: may cause compatibility issues."
        )
      elseif found_version_parsed[2] < latest_tested_version_parsed[2] then
        vim.health.warn(
          "`opencode` version has an older `minor` version than latest tested version `"
            .. latest_tested_version
            .. "`: may cause compatibility issues.",
          {
            "Update `opencode`.",
          }
        )
      elseif found_version_parsed[3] < latest_tested_version_parsed[3] then
        vim.health.warn(
          "`opencode` version has an older `patch` version than latest tested version `"
            .. latest_tested_version
            .. "`: may cause compatibility issues.",
          {
            "Update `opencode`.",
          }
        )
      end
    end
  else
    vim.health.error("`opencode` executable not found in `$PATH`.", {
      "Install `opencode` and ensure it's in your `$PATH`.",
    })
  end

  if vim.fn.executable("curl") == 1 then
    vim.health.ok("`curl` available.")
  else
    vim.health.error("`curl` executable not found in `$PATH`.", {
      "Install `curl` and ensure it's in your `$PATH`.",
    })
  end

  -- Binaries for auto-finding `opencode` process (Unix only)
  if vim.fn.has("win32") == 0 and (not vim.g.opencode_opts or not vim.g.opencode_opts.port) then
    if vim.fn.executable("pgrep") == 1 then
      vim.health.ok("`pgrep` available.")
    else
      vim.health.error(
        "`pgrep` executable not found in `$PATH`.",
        { "Install `pgrep` and ensure it's in your `$PATH`", "Or set `vim.g.opencode_opts.port`." }
      )
    end
    if vim.fn.executable("lsof") == 1 then
      vim.health.ok("`lsof` available.")
    else
      vim.health.error(
        "`lsof` executable not found in `$PATH`.",
        { "Install `lsof` and ensure it's in your `$PATH`", "Or set `vim.g.opencode_opts.port`." }
      )
    end
  end

  vim.health.start("opencode.nvim [snacks]")

  local snacks_ok, snacks = pcall(require, "snacks")
  ---@cast snacks Snacks Cast because CI lint resolves to our `snacks.lua` instead...
  if snacks_ok then
    if snacks.config.get("input", {}).enabled then
      vim.health.ok("`snacks.input` is enabled: `ask()` will be enhanced.")
      -- TODO: Maybe healthcheck verifying that their completion plugin has the LSP source enabled by default?
      -- Otherwise they need to explicitly enable it for `opencode_ask` filetype.
    else
      vim.health.warn("`snacks.input` is disabled: `ask()` will not be enhanced.")
    end
    if snacks.config.get("picker", {}).enabled then
      vim.health.ok("`snacks.picker` is enabled: `select()` will be enhanced.")
    else
      vim.health.warn("`snacks.picker` is disabled: `select()` will not be enhanced.")
    end
  else
    vim.health.warn("`snacks.nvim` is not available: `ask()` and `select()` will not be enhanced.")
  end

  vim.health.start("opencode.nvim [providers]")

  local configured_provider = require("opencode.config").provider
  if configured_provider then
    vim.health.ok("Configured `opencode` provider: `" .. configured_provider.name .. "`.")
  else
    vim.health.warn("No `opencode` provider configured.")
  end

  for _, provider in ipairs(require("opencode.provider").list()) do
    local ok, advice = provider.health()
    if ok == true then
      vim.health.ok("The `" .. provider.name .. "` provider is available.")
    else
      vim.health.warn("The `" .. provider.name .. "` provider is not available — " .. ok, advice)
    end
  end
end

return M
