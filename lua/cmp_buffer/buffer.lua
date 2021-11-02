---@class cmp_buffer.Buffer
---@field public bufnr number
---@field public regex any
---@field public length number
---@field public pattern string
---@field public indexing_chunk_size number
---@field public indexing_interval number
---@field public timer any|nil
---@field public lines_words table<number, string[]>
---@field public unique_words table<string, boolean>
---@field public unique_words_dirty boolean
---@field public processing boolean
local buffer = {}

---Create new buffer object
---@param bufnr number
---@param length number
---@param pattern string
---@param indexing_chunk_size number
---@param indexing_interval number
---@return cmp_buffer.Buffer
function buffer.new(bufnr, length, pattern, indexing_chunk_size, indexing_interval)
  local self = setmetatable({}, { __index = buffer })
  self.bufnr = bufnr
  self.regex = vim.regex(pattern)
  self.length = length
  self.pattern = pattern
  self.indexing_chunk_size = indexing_chunk_size
  self.indexing_interval = indexing_interval
  self.timer = nil
  self.lines_count = 0
  self.lines_words = {}
  self.unique_words = {}
  self.unique_words_dirty = true
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
  self.lines_count = 0
  self.lines_words = {}
  self.unique_words = {}
  self.unique_words_dirty = false
end

---Indexing buffer
function buffer.index(self)
  self.processing = true

  self.lines_count = vim.api.nvim_buf_line_count(self.bufnr)
  local chunk_max_size = self.indexing_chunk_size
  if chunk_max_size < 1 then
    -- Index all lines in one go.
    chunk_max_size = self.lines_count
  end
  local chunk_start = 0

  if self.indexing_interval <= 0 then
    -- sync algorithm

    vim.api.nvim_buf_call(self.bufnr, function()
      while chunk_start < self.lines_count do
        local chunk_end = math.min(chunk_start + chunk_max_size, self.lines_count)
        -- For some reason requesting line arrays multiple times in chunks
        -- leads to much better memory usage than doing that in one big array,
        -- which is why the sync algorithm has better memory usage than the
        -- async one.
        local chunk_lines = vim.api.nvim_buf_get_lines(self.bufnr, chunk_start, chunk_end, true)
        for linenr = chunk_start + 1, chunk_end do
          self.lines_words[linenr] = {}
          self:index_line(linenr, chunk_lines[linenr - chunk_start])
        end
        chunk_start = chunk_end
      end
    end)

    self:rebuild_unique_words()

    self.processing = false
    return
  end

  -- async algorithm

  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, true)
  -- This flag prevents vim.schedule() callbacks from piling up in the queue
  -- when the indexing interval is very short.
  local scheduled = false

  self.timer = vim.loop.new_timer()
  self.timer:start(0, self.indexing_interval, function()
    if scheduled then
      return
    end
    scheduled = true
    vim.schedule(function()
      scheduled = false

      local chunk_end = math.min(chunk_start + chunk_max_size, self.lines_count)
      vim.api.nvim_buf_call(self.bufnr, function()
        for linenr = chunk_start + 1, chunk_end do
          self.lines_words[linenr] = {}
          self:index_line(linenr, lines[linenr])
        end
      end)
      chunk_start = chunk_end

      if chunk_end >= self.lines_count then
        if self.timer then
          self.timer:stop()
          self.timer:close()
          self.timer = nil
        end
        self.processing = false
      end
    end)
  end)
end

-- See below.
local shared_marker_table_for_preallocation = {}

--- watch
function buffer.watch(self)
  -- NOTE: As far as I know, indexing in watching can't be done asynchronously
  -- because even built-in commands generate multiple consequent `on_lines`
  -- events, and I'm not even mentioning plugins here. To get accurate results
  -- we would have to either re-index the entire file on throttled events (slow
  -- and looses the benefit of on_lines watching), or put the events in a
  -- queue, which would complicate the plugin a lot. Plus, most changes which
  -- trigger this event will be from regular editing, and so 99% of the time
  -- they will affect only 1-2 lines.
  vim.api.nvim_buf_attach(self.bufnr, false, {
    -- NOTE: line indexes are 0-based and the last line is not inclusive.
    on_lines = function(_, _, _, first_line, old_last_line, new_last_line, _, _, _)
      if not vim.api.nvim_buf_is_loaded(self.bufnr) then
        return true
      end

      local delta = new_last_line - old_last_line
      local new_lines_count = self.lines_count + delta
      if delta > 0 then -- append
        -- Explicitly reserve more slots in the array part of the lines table,
        -- all of them will be filled in the next loop, but in reverse order
        -- (which is why I am concerned about preallocation). Why is there no
        -- built-in function to do this in Lua???
        for i = self.lines_count + 1, new_lines_count do
          self.lines_words[i] = shared_marker_table_for_preallocation
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
          self:index_line(first_line + i, line)
        end
      end)

      self.unique_words_dirty = true
    end,

    on_detach = function(_)
      self:close()
    end,
  })
end

--- add_words
---@param linenr number
---@param line string
function buffer.index_line(self, linenr, line)
  local words = self.lines_words[linenr]
  for k, _ in ipairs(words) do
    words[k] = nil
  end
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
end

--- get_words
function buffer.get_words(self)
  -- NOTE: unique_words are rebuilt on-demand because it is common for the
  -- watcher callback to be fired VERY frequently, and a rebuild needs to go
  -- over ALL lines, not just the changed ones.
  if self.unique_words_dirty then
    self:rebuild_unique_words()
  end
  return self.unique_words
end

--- rebuild_unique_words
function buffer.rebuild_unique_words(self)
  for w, _ in pairs(self.unique_words) do
    self.unique_words[w] = nil
  end
  for _, line in ipairs(self.lines_words) do
    for _, w in ipairs(line) do
      self.unique_words[w] = true
    end
  end
  self.unique_words_dirty = false
end

return buffer
