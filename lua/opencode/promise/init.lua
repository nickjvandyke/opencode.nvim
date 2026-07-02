-- https://github.com/notomo/promise.nvim with modifications.

---@diagnostic disable: invisible

---Equivalent to [JavaScript's `Promise`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise).
---Typed specifically for LuaLS to correctly infer generics.
---@class Promise<T>
---@field private _status "pending" | "fulfilled" | "rejected"
---@field private _value any
---@field private _queued Promise[]
---@field private _unhandled_detector table
---@field private _on_fulfilled? fun(value: T): any
---@field private _on_rejected? fun(reason: any): any
---@field private _handled boolean
local Promise = {
  _is_promise = true,
}
Promise.__index = Promise

local PromiseStatus = { Pending = "pending", Fulfilled = "fulfilled", Rejected = "rejected" }

local is_promise = function(v)
  local tbl = getmetatable(v)
  return tbl ~= nil and tbl._is_promise == true
end

local new_empty_userdata = function()
  return newproxy(true)
end

local new_pending = function(on_fulfilled, on_rejected)
  local tbl = {
    _status = PromiseStatus.Pending,
    _queued = {},
    _value = nil,
    _on_fulfilled = on_fulfilled,
    _on_rejected = on_rejected,
    _handled = false,
  }
  local self = setmetatable(tbl, Promise)

  local userdata = new_empty_userdata()
  self._unhandled_detector = setmetatable({ [self] = userdata }, { __mode = "k" })
  getmetatable(userdata).__gc = function()
    if self._status ~= PromiseStatus.Rejected or self._handled then
      return
    end
    self._handled = true
    vim.schedule(function()
      error("unhandled promise rejection: " .. vim.inspect(self._value, { newline = "", indent = "" }), 0)
    end)
  end

  return self
end

-- Unfortunately LuaLS cannot infer `T` from how `resolve` is called.

---@generic T
---@param executor fun(resolve: fun(value: T), reject: fun(reason: any))
---@return Promise<T>
function Promise.new(executor)
  local self = new_pending()

  local resolve = function(value)
    if is_promise(value) then
      value
        :next(function(v)
          self:_resolve(v)
        end)
        :catch(function(e)
          self:_reject(e)
        end)
      return
    end
    self:_resolve(value)
  end
  local reject = function(reason)
    self:_reject(reason)
  end
  executor(resolve, reject)

  return self
end

---@generic T
---@param value T
---@return Promise<T>
function Promise.resolve(value)
  return Promise.new(function(resolve, _)
    resolve(value)
  end)
end

---@generic T
---@param reason any
---@return Promise<T>
function Promise.reject(reason)
  return Promise.new(function(_, reject)
    reject(reason)
  end)
end

function Promise._resolve(self, value)
  if self._status == PromiseStatus.Rejected then
    return
  end
  self._status = PromiseStatus.Fulfilled
  self._value = value
  for _ = 1, #self._queued do
    local promise = table.remove(self._queued, 1)
    promise:_start_resolve(self._value)
  end
end

function Promise._start_resolve(self, value)
  if not self._on_fulfilled then
    return vim.schedule(function()
      self:_resolve(value)
    end)
  end
  local ok, result = pcall(self._on_fulfilled, value)
  if not ok then
    return vim.schedule(function()
      self:_reject(result)
    end)
  end
  if not is_promise(result) then
    return vim.schedule(function()
      self:_resolve(result)
    end)
  end
  result
    :next(function(v)
      self:_resolve(v)
    end)
    :catch(function(e)
      self:_reject(e)
    end)
end

function Promise._reject(self, reason)
  if self._status == PromiseStatus.Fulfilled then
    return
  end
  self._status = PromiseStatus.Rejected
  self._value = reason
  self._handled = self._handled or #self._queued > 0
  for _ = 1, #self._queued do
    local promise = table.remove(self._queued, 1)
    promise:_start_reject(self._value)
  end
end

function Promise._start_reject(self, reason)
  if not self._on_rejected then
    return vim.schedule(function()
      self:_reject(reason)
    end)
  end
  local ok, result = pcall(self._on_rejected, reason)
  if not ok then
    return vim.schedule(function()
      self:_reject(result)
    end)
  end
  if not is_promise(result) then
    return vim.schedule(function()
      self:_resolve(result)
    end)
  end
  result
    :next(function(v)
      self:_resolve(v)
    end)
    :catch(function(e)
      self:_reject(e)
    end)
end

-- Callbacks are typed to _only_ return Promises - never bare values.
-- Otherwise LuaLS infers their union type instead of narrowing to the most specific one.
-- We also seem to need `---@overload`; LuaLS infers `unknown` when annotated via `---@param`.

---@generic T, U
---@overload fun(self: Promise<T>, on_fulfilled: fun(value: T): (Promise<U> | nil), on_rejected?: fun(reason: any): (Promise<U> | nil)): Promise<U>
---@param self Promise<T>
---@return Promise<U>
function Promise.next(self, on_fulfilled, on_rejected)
  local promise = new_pending(on_fulfilled, on_rejected)
  table.insert(self._queued, promise)
  vim.schedule(function()
    if self._status == PromiseStatus.Fulfilled then
      return self:_resolve(self._value)
    end
    if self._status == PromiseStatus.Rejected then
      return self:_reject(self._value)
    end
  end)
  return promise
end

---@generic T, U
---@overload fun(self: Promise<T>, on_rejected: fun(value: T): (Promise<U> | nil)): Promise<U>
---@param self Promise<T>
---@return Promise<U>
function Promise.catch(self, on_rejected)
  ---@diagnostic disable-next-line: param-type-mismatch
  return self:next(nil, on_rejected)
end

---@generic T
---@overload fun(self: Promise<T>, on_finally: fun()): Promise<T>
---@param self Promise<T>
---@return Promise<T>
function Promise.finally(self, on_finally)
  return self
    :next(function(value)
      on_finally()
      return Promise.resolve(value)
    end)
    :catch(function(reason)
      on_finally()
      return Promise.reject(reason)
    end)
end

---@generic T
---@param list (Promise<T>)[]
---@return Promise<T[]>
function Promise.all(list)
  return Promise.new(function(resolve, reject)
    local remain = #list
    if remain == 0 then
      return resolve({})
    end

    local results = {}
    for i, e in ipairs(list) do
      Promise.resolve(e)
        :next(function(value)
          results[i] = value
          if remain == 1 then
            return resolve(results)
          end
          remain = remain - 1
        end)
        :catch(function(reason)
          reject(reason)
        end)
    end
  end)
end

---@generic T
---@param list (Promise<T>)[]
---@return Promise<T>
function Promise.race(list)
  return Promise.new(function(resolve, reject)
    for _, e in ipairs(list) do
      Promise.resolve(e)
        :next(function(value)
          resolve(value)
        end)
        :catch(function(reason)
          reject(reason)
        end)
    end
  end)
end

---@generic T
---@param list (Promise<T>)[]
---@return Promise<T>
function Promise.any(list)
  return Promise.new(function(resolve, reject)
    local remain = #list
    if remain == 0 then
      return reject({})
    end

    local errs = {}
    for i, e in ipairs(list) do
      Promise.resolve(e)
        :next(function(value)
          resolve(value)
        end)
        :catch(function(reason)
          errs[i] = reason
          if remain == 1 then
            return reject(errs)
          end
          remain = remain - 1
        end)
    end
  end)
end

---@generic T
---@param list (Promise<T>)[]
---@return Promise<{status: string, value?: T, reason?: any}[]>
function Promise.all_settled(list)
  return Promise.new(function(resolve)
    local remain = #list
    if remain == 0 then
      return resolve({})
    end

    local results = {}
    for i, e in ipairs(list) do
      Promise.resolve(e)
        :next(function(value)
          results[i] = { status = PromiseStatus.Fulfilled, value = value }
        end)
        :catch(function(reason)
          results[i] = { status = PromiseStatus.Rejected, reason = reason }
        end)
        :finally(function()
          if remain == 1 then
            return resolve(results)
          end
          remain = remain - 1
        end)
    end
  end)
end

---@generic T
---@return Promise<T>, fun(value: T), fun(reason: any)
function Promise.with_resolvers()
  local resolve, reject
  local promise = Promise.new(function(res, rej)
    resolve = res
    reject = rej
  end)
  return promise, resolve, reject
end

return Promise
