local buffer = require('cmp_buffer.buffer')

local defaults = {
  keyword_pattern = [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([\-]\w*\)*\)]],
  get_bufnrs = function()
    return { vim.api.nvim_get_current_buf() }
  end,
}

local source = {}

source.new = function()
  local self = setmetatable({}, { __index = source })
  self.buffers = {}
  return self
end

source.complete = function(self, request, callback)
  request.option = vim.tbl_deep_extend('keep', request.option, defaults)
  vim.validate({
    keyword_pattern = { request.option.keyword_pattern, 'string', '`opts.keyword_pattern` must be `string`' },
    get_bufnrs = { request.option.get_bufnrs, 'function', '`opts.get_bufnrs` must be `function`' },
  })

  local processing = false
  for _, buf in ipairs(self:_get_buffers(request)) do
    processing = processing or buf.processing
  end

  vim.defer_fn(vim.schedule_wrap(function()
    local input = string.sub(request.context.cursor_before_line, request.offset)
    local items = {}
    local words = {}
    for _, buf in ipairs(self:_get_buffers(request)) do
      for _, word in ipairs(buf:get_words()) do
        if not words[word] and input ~= word then
          words[word] = true
          table.insert(items, {
            label = word,
            dup = 0,
          })
        end
      end
    end

    callback({
      items = items,
      isIncomplete = processing,
    })
  end), processing and 100 or 0)
end

--- _get_bufs
source._get_buffers = function(self, request)
  local buffers = {}
  for _, bufnr in ipairs(request.option.get_bufnrs()) do
    if not self.buffers[bufnr] then
      local new_buf = buffer.new(bufnr, request.option.keyword_pattern)
      new_buf:index()
      new_buf:watch()
      self.buffers[bufnr] = new_buf
    end
    table.insert(buffers, self.buffers[bufnr])
  end

  return buffers
end

return source
