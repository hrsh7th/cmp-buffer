# cmp-buffer

nvim-cmp source for buffer words.

## Setup

```lua
require('cmp').setup({
  sources = {
    { name = 'buffer' },
  },
})
```

## Configuration

The below source configuration are available. To set any of these options, do:

```lua
cmp.setup({
  sources = {
    { 
      name = 'buffer',
      option = {
        -- Options go into this table
      },
    },
  },
})
```


### keyword_length (type: number)

_Default:_ `3`

Specify word length to gather.


### keyword_pattern (type: string)

_Default:_ `[[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([\-.]\w*\)*\)]]`

A vim's regular expression for creating a word list from buffer content.

You can set this to `[[\k\+]]` if you want to use the `iskeyword` option for recognizing words.
Lua's `[[ ]]` string literals are particularly useful here to avoid escaping all of the backslash
(`\`) characters used for writing regular expressions.

**NOTE:** Be careful with where you set this option! You must do this:

```lua
cmp.setup({
  sources = {
    {
      name = 'buffer',
      -- Correct:
      option = {
        keyword_pattern = [[\k\+]],
      }
    },
  },
})
```

Instead of this:

```lua
cmp.setup({
  sources = {
    {
      name = 'buffer',
      -- Wrong:
      keyword_pattern = [[\k\+]],
    },
  },
})
```

The second notation is allowed by nvim-cmp (documented [here](https://github.com/hrsh7th/nvim-cmp#sourcesnumberkeyword_pattern-type-string)), but it is meant for a different purpose and will not be detected by this plugin as the pattern for searching words.


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


### indexing_interval (type: number)

_Default:_ `200`

The rate (in milliseconds) at which buffers are scanned for words when they are first opened.
Setting this interval to lower values will increase the speed of indexing, but at the expense of
higher CPU usage. By default indexing happens asynchronously, but setting this option to zero or
a negative value will switch indexing to a synchronous algorithm, which uses significantly less
RAM on big files and takes less time in total (to index the entire file), with the obvious
downside of blocking the user interface for a second or two. On small files (up to tens of
thousands of lines, probably) the difference will be unnoticeable, though.


### indexing_chunk_size (type: number)

_Default:_ `1000`

The number of lines processed in batch every `indexing_interval` milliseconds. Setting it to
higher values will make indexing faster, but at the cost of responsiveness of the UI. When using
the synchronous mode, changing this option may improve memory usage, though the default value has
been tested to be pretty good in this regard.

Please note that the `indexing_interval` and `indexing_chunk_size` are advanced options, change
them only if you experience performance or RAM usage problems (or need to work on particularly
large files) and be sure to measure the results!


## Performance on large text files

This source has been tested on code files of a few megabytes in size (5-10) and it has been
optimized for them, however, the indexed words can still take up tens of megabytes of RAM if the
file is big (on small files it _will not be more_ than a couple of megabytes, typically much
less). So if you wish to avoid accidentally wasting lots of RAM when editing big files, you can
tweak `get_bufnrs`, for example like this:

```lua
get_bufnrs = function()
  local buf = vim.api.nvim_get_current_buf()
  local byte_size = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
  if byte_size > 1024 * 1024 then -- 1 Megabyte max
    return {}
  end
  return { buf }
end
```

Of course, this snippet can be combined with any other recipes for `get_bufnrs`.

As another tip, turning on the synchronous indexing mode is very likely to help with reducing
memory usage, see the `indexing_interval` option.


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
