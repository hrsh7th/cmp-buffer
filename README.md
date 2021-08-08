# cmp-buffer

nvim-cmp source for buffer words.

# configuration

The below source configuration are available.


### keyword_pattern _Type: string_

A vim's regular expression for creating a word list from buffer content.

_Default: [[\%(-\?\d\+\%(\.\d\+\)\?\|\h\w*\%([\-.]\w*\)*\)]]_


### get_bufnrs _Type: fun(): number[]_

A function that specifies the buffer numbers to complete.

_Default: function() return { vim.api.nvim_get_current_buf() } end_

