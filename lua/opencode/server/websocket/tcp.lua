local uv = vim.uv

local M = {}

function M.create_server(host, port, on_connection)
  local server = uv.new_tcp()
  if not server then
    return nil, "Failed to create TCP server"
  end

  local ok, err = server:bind(host, port)
  if not ok then
    server:close()
    return nil, err or "Failed to bind to port"
  end

  ok, err = server:listen(128, function(listen_err)
    if listen_err then
      return
    end

    local client = uv.new_tcp()
    if not client then
      return
    end

    server:accept(client)
    on_connection(client)
  end)

  if not ok then
    server:close()
    return nil, err or "Failed to listen"
  end

  return server
end

function M.close_server(server)
  if server then
    server:close()
  end
end

function M.write(client, data)
  if client and not client:is_closing() then
    client:write(data)
  end
end

function M.close_client(client)
  if client and not client:is_closing() then
    client:close()
  end
end

return M
