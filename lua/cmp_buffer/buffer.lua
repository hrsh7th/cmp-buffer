---@class cmp_buffer.Buffer
---@field public bufnr number
---@field public regex any
---@field public length number
---@field public pattern string
---@field public timer any|nil
---@field public words table<number, string[]>
---@field public processing boolean
local buffer = {}

---Create new buffer object
---@param bufnr number
---@param length number
---@param pattern string
---@return cmp_buffer.Buffer
function buffer.new(bufnr, length, pattern)
  local self = setmetatable({}, { __index = buffer })
  self.bufnr = bufnr
  self.regex = vim.regex(pattern)
  self.length = length
  self.pattern = pattern
  self.timer = nil
  self.words = {}
  self.processing = false
  return self
end

---Close buffer
function buffer.close(self)
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  self.words = {}
end

---Indexing buffer
function buffer.index(self)
  self.processing = true
  local index = 1
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  self.timer = vim.loop.new_timer()
  self.timer:start(
    0,
    200,
    vim.schedule_wrap(function()
      local chunk = math.min(index + 1000, #lines)
      vim.api.nvim_buf_call(self.bufnr, function()
        for i = index, chunk do
          self:index_line(i, lines[i] or '')
        end
      end)
      index = chunk + 1

      if chunk >= #lines then
        if self.timer then
          self.timer:stop()
          self.timer:close()
          self.timer = nil
        end
        self.processing = false
      end
    end)
  )
end

--- watch
function buffer.watch(self)
  vim.api.nvim_buf_attach(self.bufnr, false, {
    on_lines = vim.schedule_wrap(function(_, _, _, firstline, old_lastline, new_lastline, _, _, _)
      if not vim.api.nvim_buf_is_valid(self.bufnr) then
        self:close()
        return true
      end

      -- append
      for i = old_lastline, new_lastline - 1 do
        table.insert(self.words, i + 1, {})
      end

      -- remove
      for _ = new_lastline, old_lastline - 1 do
        table.remove(self.words, new_lastline + 1)
      end

      -- replace lines
      local lines = vim.api.nvim_buf_get_lines(self.bufnr, firstline, new_lastline, false)
      vim.api.nvim_buf_call(self.bufnr, function()
        for i, line in ipairs(lines) do
          if line then
            self:index_line(firstline + i, line or '')
          end
        end
      end)
    end),
  })
end

---@param linenr number
---@param line string
function buffer.index_line(self, linenr, line)
  local words = {}
  local word_i = 1

  local remaining = line
  while #remaining > 0 do
    -- NOTE: Both start and end indexes here are 0-based (unlike Lua strings),
    -- and the end index is not inclusive.
    local match_start, match_end = self.regex:match_str(remaining)
    if match_start and match_end then
      local word = remaining:sub(match_start + 1, match_end)
      if #word >= self.length then
        words[word_i] = word
        word_i = word_i + 1
      end
      remaining = remaining:sub(match_end + 1)
    else
      break
    end
  end

  self.words[linenr] = words
end

--- get_words
function buffer.get_words(self)
  local words = {}
  for _, line in ipairs(self.words) do
    for _, w in ipairs(line) do
      table.insert(words, w)
    end
  end
  return words
end

return buffer
