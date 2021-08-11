# cmp-buffer

nvim-cmp source for buffer words.

# Configuration

The below source configuration are available.


### keyword_pattern (type: string)

_Default: [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([\-.]\w*\)*\)]]_

A vim's regular expression for creating a word list from buffer content.


### get_bufnrs (type: fun(): number[])

_Default: function() return { vim.api.nvim_get_current_buf() } end_

A function that specifies the buffer numbers to complete.

You can use the following pre-defined recipes.

##### All buffers

```lua
get_bufnrs = function()
  return vim.api.nvim_list_bufs()()
end
```

##### Visible buffers

```lua
get_bufnrs = function()
  local bufs = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    bufs[vim.api.nvim_win_get_buf(win)] = true
  end
  return vim.tbl_keys(bufs)
end
```

