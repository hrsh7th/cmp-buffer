---@class cmp_buffer.Timer
---@field public handle any
---@field private callback_wrapper_instance fun()|nil
local timer = {}

function timer.new()
  local self = setmetatable({}, { __index = timer })
  self.handle = vim.loop.new_timer()
  self.callback_wrapper_instance = nil
  return self
end

---@param timeout_ms number
---@param repeat_ms number
---@param callback fun()
function timer:start(timeout_ms, repeat_ms, callback)
  local scheduled = false
  local function callback_wrapper()
    if scheduled then
      return
    end
    scheduled = true
    vim.schedule(function()
      scheduled = false
      if self.callback_wrapper_instance ~= callback_wrapper then
        return
      end
      callback()
    end)
  end
  self.handle:start(timeout_ms, repeat_ms, callback_wrapper)
  self.callback_wrapper_instance = callback_wrapper
end

function timer:stop()
  self.handle:stop()
  self.callback_wrapper_instance = nil
end

function timer:is_active()
  return self.handle:is_active()
end

function timer:close()
  self.handle:close()
end

return timer
