# cmp-buffer

nvim-cmp source for buffer words.

## Setup

```lua
require'cmp'.setup {
  sources = {
    { name = 'buffer' }
  }
}
```

## Configuration

The below source configuration are available.


### keyword_length (type: number)

_Default:_ `3`

Specify word length to gather.


### keyword_pattern (type: string)

_Default:_ `[[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([\-.]\w*\)*\)]]`

A vim's regular expression for creating a word list from buffer content.

You can set this to `\k\+` if you want to use the `iskeyword` option for recognizing words.


### get_bufnrs (type: fun(): number[])

_Default:_ `function() return { vim.api.nvim_get_current_buf() } end`

A function that specifies the buffer numbers to complete.

You can use the following pre-defined recipes.

##### All buffers

```lua
get_bufnrs = function()
  return vim.api.nvim_list_bufs()
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


## Locality bonus comparator (distance-based sorting)

This source also provides a comparator function which uses information from the word indexer
to sort completion results based on the distance of the word from the cursor line. It will also
sort completion results coming from other sources, such as Language Servers, which might improve
accuracy of their suggestions too. The usage is as follows:

```lua
local cmp = require('cmp')
local cmp_buffer = require('cmp_buffer')

cmp.setup({
  sources = {
    { name = 'buffer' },
      -- The rest of your sources...
  },
  sorting = {
    comparators = {
      function(...) return cmp_buffer:compare_locality(...) end,
      -- The rest of your comparators...
    }
  }
})
```
