-- Jinja template with default delimiters.
-- Treesitter jinja parser highlights Jinja tags,
-- inner language is injected into the rest of text (see queries/jinja/injections.scm).

local jinja = require 'jinja'
local buf = vim.api.nvim_get_current_buf()

vim.b.jinja_lang = jinja.inner_filetype(buf)
vim.bo.commentstring = '{# %s #}'
jinja.start(buf, 'jinja')

vim.b.undo_ftplugin = 'setl cms< | unlet! b:jinja_lang | lua vim.treesitter.stop()'
