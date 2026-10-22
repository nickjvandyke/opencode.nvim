local M = {}

function M.check()
  vim.health.start("opencode.nvim")

  local uname = vim.uv.os_uname()
  vim.health.info(string.format("OS: %s %s (%s)", uname.sysname, uname.release, uname.machine))

  vim.health.info("Neovim version: `" .. tostring(vim.version()) .. "`")

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
  local git_hash =
    vim.trim(vim.fn.system("cd " .. vim.fn.shellescape(plugin_dir) .. " && git rev-parse HEAD")):gsub("\n", "\\n")
  if vim.v.shell_error == 0 then
    vim.health.info("opencode.nvim git commit: `" .. git_hash .. "`")
  else
    vim.health.warn("opencode.nvim git commit: `" .. git_hash .. "`")
  end

  vim.health.info("`vim.g.opencode_opts`: " .. vim.inspect(vim.g.opencode_opts))
  local opts = require("opencode.config").opts

  if opts.events.reload.enabled and not vim.o.autoread then
    vim.health.warn(
      "`vim.g.opencode_opts.events.reload.enabled = true` but `vim.o.autoread = false`: files edited by `opencode` can't be automatically reloaded in buffers.",
      "Set `vim.o.autoread = true`."
    )
  end

  vim.health.start("opencode.nvim [executables]")

  if vim.fn.executable("opencode") == 1 then
    local found_version = vim.trim(vim.fn.system("opencode --version"))
    vim.health.ok("`" .. found_version .. "`" .. " available.")

    local found_version_parsed = vim.version.parse(found_version)
    local minimum_version = "2.0"
    local minimum_version_parsed = vim.version.parse(minimum_version)
    if
      found_version_parsed
      and minimum_version_parsed
      and vim.version.cmp(found_version_parsed, minimum_version_parsed) < 0
    then
      vim.health.warn(
        "`opencode` version is older than the minimum supported version `"
          .. minimum_version
          .. "`: may cause compatibility issues.",
        {
          "Update `opencode`.",
        }
      )
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

  if not (opts and opts.server and opts.server.url) then
    local registration = require("opencode.server.discovery").registration()
    if registration then
      vim.health.ok(
        "OpenCode background service "
          .. (registration.version and ("(v" .. registration.version .. ") ") or "")
          .. "registered at `"
          .. registration.url
          .. "`."
      )
    else
      vim.health.info(
        "No OpenCode background service registered yet. Run `opencode` to start it, or set `vim.g.opencode_opts.server.url`."
      )
    end
  end

  local connected = require("opencode.server").connected
  if connected then
    vim.health.ok("Connected to OpenCode at `" .. connected.url .. "`.")
  end

  vim.health.start("opencode.nvim [snacks]")

  local snacks_ok, snacks = pcall(require, "snacks")
  if snacks_ok then
    if snacks.config.get("input", {}).enabled then
      vim.health.ok("snacks.input enabled: `ask()` enhanced.")
    else
      vim.health.warn("snacks.input disabled: `ask()` not enhanced.")
    end
    if snacks.config.get("picker", {}).enabled then
      vim.health.ok("snacks.picker enabled: `select()` enhanced.")
    else
      vim.health.warn("snacks.picker disabled: `select()` enhanced.")
    end
  else
    vim.health.warn("snacks.nvim not available: `ask()` and `select()` not enhanced.")
  end
end

return M
