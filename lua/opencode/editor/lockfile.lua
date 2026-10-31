local M = {}

local function get_lockfile_dir()
  -- Opencode actually read the lockfile inside .claude
  -- for some reason
  -- See: https://github.com/anomalyco/opencode/blob/dev/packages/tui/src/editor.ts
  return vim.fn.expand("~/.claude/ide")
end

local function get_lockfile_path(port)
  return get_lockfile_dir() .. "/" .. port .. ".lock"
end

local function get_workspace_folders()
  local folders = {}

  local cwd = vim.fn.getcwd()
  table.insert(folders, cwd)

  return folders
end

function M.generate_auth_token()
  local bytes, err = vim.uv.random(16)
  if not bytes then
    return nil, err or "Failed to obtain random bytes"
  end

  return (bytes:gsub(".", function(byte)
    return string.format("%02x", string.byte(byte))
  end))
end

function M.create(port, auth_token)
  if not port or port <= 0 or port > 65535 then
    return false, "Invalid port number"
  end

  if auth_token ~= nil and type(auth_token) ~= "string" then
    return false, "Authentication token must be a string"
  end

  local lockfile_dir = get_lockfile_dir()
  if vim.fn.mkdir(lockfile_dir, "p", "0700") == 0 and vim.fn.isdirectory(lockfile_dir) == 0 then
    return false, "Failed to create lockfile directory"
  end
  pcall(vim.uv.fs_chmod, lockfile_dir, tonumber("700", 8))

  local lockfile_path = get_lockfile_path(port)

  local lock_content = {
    pid = vim.fn.getpid(),
    workspaceFolders = get_workspace_folders(),
    ideName = "Neovim",
    transport = "ws",
  }

  if auth_token then
    lock_content.authToken = auth_token
  end

  local json = vim.json.encode(lock_content)

  local temp_file = lockfile_path .. ".tmp." .. vim.fn.getpid()
  local fd = io.open(temp_file, "wb")
  if not fd then
    return false, "Failed to create temporary lockfile"
  end

  fd:write(json)
  fd:close()

  local ok, err = os.rename(temp_file, lockfile_path)
  if not ok then
    os.remove(temp_file)
    return false, "Failed to create lockfile: " .. (err or "unknown error")
  end

  return true, lockfile_path
end

function M.remove(port)
  if not port then
    return false
  end

  local lockfile_path = get_lockfile_path(port)

  if vim.fn.filereadable(lockfile_path) == 1 then
    os.remove(lockfile_path)
    return true
  end

  return false
end

function M.exists(port)
  if not port then
    return false
  end

  local lockfile_path = get_lockfile_path(port)
  return vim.fn.filereadable(lockfile_path) == 1
end

function M.read(port)
  if not port then
    return nil
  end

  local lockfile_path = get_lockfile_path(port)

  if vim.fn.filereadable(lockfile_path) == 0 then
    return nil
  end

  local fd = io.open(lockfile_path, "r")
  if not fd then
    return nil
  end

  local content = fd:read("*a")
  fd:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end

  return data
end

function M.clean_all()
  local lockfile_dir = get_lockfile_dir()

  if vim.fn.isdirectory(lockfile_dir) == 0 then
    return
  end

  local files = vim.fn.glob(lockfile_dir .. "/*.lock", true, true)
  for _, file in ipairs(files) do
    local port = vim.fn.fnamemodify(file, ":t:r")
    local lock_data = M.read(tonumber(port))

    if lock_data and lock_data.pid then
      local pid = lock_data.pid
      if not vim.uv.kill(pid, 0) then
        os.remove(file)
      end
    end
  end
end

return M
