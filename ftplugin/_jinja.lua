-- Jinja template with custom delimiters.
-- Treesitter parser of the inner language highlights the whole text,
-- and Jinja tags are highlighted on top of it (see lua/jinja/overlay.lua).

local jinja = require 'jinja'
local buf = vim.api.nvim_get_current_buf()
local delims = jinja.delimiters(vim.api.nvim_buf_get_name(buf)) or jinja.default_delimiters

vim.bo.commentstring = delims.comment[1] .. ' %s ' .. delims.comment[2]
local ft = jinja.inner_filetype(buf)
jinja.start(buf, ft and vim.treesitter.language.get_lang(ft))
require('jinja.overlay').attach(buf, delims)

vim.b.undo_ftplugin = 'setl cms< | lua vim.treesitter.stop()'
