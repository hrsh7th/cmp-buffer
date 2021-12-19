---@class cmp_buffer.Buffer
---@field public bufnr number
---@field public opts cmp_buffer.Options
---@field public regex any
---@field public indexing_chunk_size number
---@field public indexing_interval number
---@field public timer any|nil
---@field public lines_count number
---@field public lines_words table<number, string[]>
---@field public unique_words_curr_line table<string, boolean>
---@field public unique_words_other_lines table<string, boolean>
---@field public unique_words_curr_line_dirty boolean
---@field public unique_words_other_lines_dirty boolean
---@field public last_edit_first_line number
---@field public last_edit_last_line number
---@field public closed boolean
---@field public on_close_cb fun()|nil
---@field public words_distances table<string, number>
---@field public words_distances_last_cursor_row number
---@field public words_distances_dirty boolean
local buffer = {}

---Create new buffer object
---@param bufnr number
---@param opts cmp_buffer.Options
---@return cmp_buffer.Buffer
function buffer.new(bufnr, opts)
  local self = setmetatable({}, { __index = buffer })

  self.bufnr = bufnr
  self.timer = nil
  self.closed = false
  self.on_close_cb = nil

  self.opts = opts
  self.regex = vim.regex(self.opts.keyword_pattern)
  self.indexing_chunk_size = 1000
  self.indexing_interval = 200

  self.lines_count = 0
  self.lines_words = {}

  self.unique_words_curr_line = {}
  self.unique_words_other_lines = {}
  self.unique_words_curr_line_dirty = true
  self.unique_words_other_lines_dirty = true
  self.last_edit_first_line = 0
  self.last_edit_last_line = 0

  self.words_distances = {}
  self.words_distances_dirty = true
  self.words_distances_last_cursor_row = 0

  return self
end

---Close buffer
function buffer.close(self)
  self.closed = true
  self:stop_indexing_timer()

  self.lines_count = 0
  self.lines_words = {}

  self.unique_words_curr_line = {}
  self.unique_words_other_lines = {}
  self.unique_words_curr_line_dirty = false
  self.unique_words_other_lines_dirty = false
  self.last_edit_first_line = 0
  self.last_edit_last_line = 0

  self.words_distances = {}
  self.words_distances_dirty = false
  self.words_distances_last_cursor_row = 0

  if self.on_close_cb then
    self.on_close_cb()
  end
end

function buffer.stop_indexing_timer(self)
  if self.timer and not self.timer:is_closing() then
    self.timer:stop()
    self.timer:close()
  end
  self.timer = nil
end

function buffer.mark_all_lines_dirty(self)
  self.unique_words_curr_line_dirty = true
  self.unique_words_other_lines_dirty = true
  self.last_edit_first_line = 0
  self.last_edit_last_line = 0
end

---Indexing buffer
function buffer.index(self)
  self.lines_count = vim.api.nvim_buf_line_count(self.bufnr)
  for i = 1, self.lines_count do
    self.lines_words[i] = {}
  end

  self:index_range_async(0, self.lines_count)
end

--- Workaround for https://github.com/neovim/neovim/issues/16729
function buffer.safe_buf_call(self, callback)
  if vim.api.nvim_get_current_buf() == self.bufnr then
    callback()
  else
    vim.api.nvim_buf_call(self.bufnr, callback)
  end
end

function buffer.index_range(self, range_start, range_end)
  self:safe_buf_call(function()
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, range_start, range_end, true)
    for i, line in ipairs(lines) do
      self:index_line(range_start + i, line)
    end
  end)
end

function buffer.index_range_async(self, range_start, range_end)
  local chunk_start = range_start

  local lines = vim.api.nvim_buf_get_lines(self.bufnr, range_start, range_end, true)

  self.timer = vim.loop.new_timer()
  self.timer:start(
    0,
    self.indexing_interval,
    vim.schedule_wrap(function()
      if self.closed then
        return
      end

      local chunk_end = math.min(chunk_start + self.indexing_chunk_size, range_end)
      self:safe_buf_call(function()
        for linenr = chunk_start + 1, chunk_end do
          self:index_line(linenr, lines[linenr])
        end
      end)
      chunk_start = chunk_end
      self:mark_all_lines_dirty()
      self.words_distances_dirty = true

      if chunk_end >= range_end then
        self:stop_indexing_timer()
      end
    end)
  )
end

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
      if self.closed then
        return true
      end

      if old_last_line == new_last_line and first_line == new_last_line then
        -- This condition is really intended as a workaround for
        -- https://github.com/hrsh7th/cmp-buffer/issues/28, but it will also
        -- protect us from completely empty text edits.
        return
      end

      local delta = new_last_line - old_last_line
      local old_lines_count = self.lines_count
      local new_lines_count = old_lines_count + delta
      if new_lines_count == 0 then -- clear
        -- This branch protects against bugs after full-file deletion. If you
        -- do, for example, gdGG, the new_last_line of the event will be zero.
        -- Which is not true, a buffer always contains at least one empty line,
        -- only unloaded buffers contain zero lines.
        new_lines_count = 1
        for i = old_lines_count, 2, -1 do
          self.lines_words[i] = nil
        end
        self.lines_words[1] = {}
      elseif delta > 0 then -- append
        -- Explicitly reserve more slots in the array part of the lines table,
        -- all of them will be filled in the next loop, but in reverse order
        -- (which is why I am concerned about preallocation). Why is there no
        -- built-in function to do this in Lua???
        for i = old_lines_count + 1, new_lines_count do
          self.lines_words[i] = vim.NIL
        end
        -- Move forwards the unchanged elements in the tail part.
        for i = old_lines_count, old_last_line + 1, -1 do
          self.lines_words[i + delta] = self.lines_words[i]
        end
        -- Fill in new tables for the added lines.
        for i = old_last_line + 1, new_last_line do
          self.lines_words[i] = {}
        end
      elseif delta < 0 then -- remove
        -- Move backwards the unchanged elements in the tail part.
        for i = old_last_line + 1, old_lines_count do
          self.lines_words[i + delta] = self.lines_words[i]
        end
        -- Remove (already copied) tables from the end, in reverse order, so
        -- that we don't make holes in the lines table.
        for i = old_lines_count, new_lines_count + 1, -1 do
          self.lines_words[i] = nil
        end
      end
      self.lines_count = new_lines_count

      -- replace lines
      self:index_range(first_line, new_last_line)

      if first_line == self.last_edit_first_line and old_last_line == self.last_edit_last_line and new_last_line == self.last_edit_last_line then
        self.unique_words_curr_line_dirty = true
      else
        self.unique_words_curr_line_dirty = true
        self.unique_words_other_lines_dirty = true
      end
      self.last_edit_first_line = first_line
      self.last_edit_last_line = new_last_line

      self.words_distances_dirty = true
    end,

    on_reload = function(_, _)
      if self.closed then
        return true
      end

      -- The logic for adjusting lines list on buffer reloads is much simpler
      -- because tables of all lines can be assumed to be fresh.
      local new_lines_count = vim.api.nvim_buf_line_count(self.bufnr)
      if new_lines_count > self.lines_count then -- append
        for i = self.lines_count + 1, new_lines_count do
          self.lines_words[i] = {}
        end
      elseif new_lines_count < self.lines_count then -- remove
        for i = self.lines_count, new_lines_count + 1, -1 do
          self.lines_words[i] = nil
        end
      end
      self.lines_count = new_lines_count

      self:index_range(0, self.lines_count)
      self:mark_all_lines_dirty()
      self.words_distances_dirty = true
    end,

    on_detach = function(_, _)
      if self.closed then
        return true
      end
      self:close()
    end,
  })
end

local function clear_table(tbl)
  for k in pairs(tbl) do
    tbl[k] = nil
  end
end

---@param linenr number
---@param line string
function buffer.index_line(self, linenr, line)
  local words = self.lines_words[linenr]
  if not words then
    words = {}
    self.lines_words[linenr] = words
  else
    clear_table(words)
  end
  local word_i = 1

  local remaining = line
  while #remaining > 0 do
    -- NOTE: Both start and end indexes here are 0-based (unlike Lua strings),
    -- and the end index is not inclusive.
    local match_start, match_end = self.regex:match_str(remaining)
    if match_start and match_end then
      local word = remaining:sub(match_start + 1, match_end)
      if #word >= self.opts.keyword_length then
        words[word_i] = word
        word_i = word_i + 1
      end
      remaining = remaining:sub(match_end + 1)
    else
      break
    end
  end
end

function buffer.get_words(self)
  -- NOTE: unique_words are rebuilt on-demand because it is common for the
  -- watcher callback to be fired VERY frequently, and a rebuild needs to go
  -- over ALL lines, not just the changed ones.
  if self.unique_words_other_lines_dirty then
    clear_table(self.unique_words_other_lines)
    self:rebuild_unique_words(self.unique_words_other_lines, 0, self.last_edit_first_line)
    self:rebuild_unique_words(self.unique_words_other_lines, self.last_edit_last_line, self.lines_count)
    self.unique_words_other_lines_dirty = false
  end
  if self.unique_words_curr_line_dirty then
    clear_table(self.unique_words_curr_line)
    self:rebuild_unique_words(self.unique_words_curr_line, self.last_edit_first_line, self.last_edit_last_line)
    self.unique_words_curr_line_dirty = false
  end
  return { self.unique_words_other_lines, self.unique_words_curr_line }
end

--- rebuild_unique_words
function buffer.rebuild_unique_words(self, words_table, range_start, range_end)
  for i = range_start + 1, range_end do
    for _, w in ipairs(self.lines_words[i] or {}) do
      words_table[w] = true
    end
  end
end

---@param cursor_row number
---@return table<string, number>
function buffer.get_words_distances(self, cursor_row)
  if self.words_distances_dirty or cursor_row ~= self.words_distances_last_cursor_row then
    local distances = self.words_distances
    clear_table(distances)
    for i = 1, self.lines_count do
      for _, w in ipairs(self.lines_words[i] or {}) do
        local dist = math.abs(cursor_row - i)
        distances[w] = distances[w] and math.min(distances[w], dist) or dist
      end
    end
    self.words_distances_last_cursor_row = cursor_row
    self.words_distances_dirty = false
  end
  return self.words_distances
end

return buffer
