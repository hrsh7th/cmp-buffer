---@class cmp_buffer.Buffer
---@field public bufnr number
---@field public regex any
---@field public length number
---@field public pattern string
---@field public timer any|nil
---@field public lines_count number
---@field public lines_words table<number, string[]>
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
  self.lines_count = 0
  self.lines_words = {}
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
  self.lines_words = {}
  self.lines_count = 0
end

---Indexing buffer
function buffer.index(self)
  self.processing = true
  self.lines_count = vim.api.nvim_buf_line_count(self.bufnr)
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
    -- NOTE: line indexes are 0-based and the last line is not inclusive.
    on_lines = function(_, _, _, first_line, old_last_line, new_last_line, _, _, _)
      if not vim.api.nvim_buf_is_valid(self.bufnr) then
        self:close()
        return true
      end

      local delta = new_last_line - old_last_line
      local new_lines_count = self.lines_count + delta
      if new_lines_count == 0 then  -- clear
        -- This branch protects against bugs after full-file deletion. If you
        -- do, for example, gdGG, the new_last_line of the event will be zero.
        -- Which is not true, a buffer always contains at least one empty line,
        -- only unloaded buffers contain zero lines.
        new_lines_count = 1
        for i = self.lines_count, 2, -1 do
          self.lines_words[i] = nil
        end
        self.lines_words[1] = {}
      elseif delta > 0 then -- append
        -- Explicitly reserve more slots in the array part of the lines table,
        -- all of them will be filled in the next loop, but in reverse order
        -- (which is why I am concerned about preallocation). Why is there no
        -- built-in function to do this in Lua???
        for i = self.lines_count + 1, new_lines_count do
          self.lines_words[i] = vim.NIL
        end
        -- Move forwards the unchanged elements in the tail part.
        for i = self.lines_count, old_last_line + 1, -1 do
          self.lines_words[i + delta] = self.lines_words[i]
        end
        -- Fill in new tables for the added lines.
        for i = old_last_line + 1, new_last_line do
          self.lines_words[i] = {}
        end
      elseif delta < 0 then -- remove
        -- Move backwards the unchanged elements in the tail part.
        for i = old_last_line + 1, self.lines_count do
          self.lines_words[i + delta] = self.lines_words[i]
        end
        -- Remove (already copied) tables from the end, in reverse order, so
        -- that we don't make holes in the lines table.
        for i = self.lines_count, new_lines_count + 1, -1 do
          self.lines_words[i] = nil
        end
      end
      self.lines_count = new_lines_count

      -- replace lines
      local lines = vim.api.nvim_buf_get_lines(self.bufnr, first_line, new_last_line, true)
      vim.api.nvim_buf_call(self.bufnr, function()
        for i, line in ipairs(lines) do
          if line then
            self:index_line(first_line + i, line)
          end
        end
      end)
    end,
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

  self.lines_words[linenr] = words
end

--- get_words
function buffer.get_words(self)
  local words = {}
  for _, line in ipairs(self.lines_words) do
    for _, w in ipairs(line) do
      table.insert(words, w)
    end
  end
  return words
end

return buffer
