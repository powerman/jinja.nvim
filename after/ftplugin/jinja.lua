-- Jinja template with filetype `<inner>.jinja` or just `jinja` if inner language is unknown.
-- See "How it works" in README.md.

local jinja = require 'jinja'
local buf = vim.api.nvim_get_current_buf()
local custom = jinja.delimiters(vim.api.nvim_buf_get_name(buf))
local delims = custom or jinja.default_delimiters
local lang = vim.treesitter.language.get_lang(vim.bo.filetype)

-- It's an after-ftplugin to run after ftplugins of the inner language and of Jinja
-- (since Neovim 0.13 its jinja ftplugin sets Jinja commentstring).
local undo = vim.b.undo_ftplugin and vim.b.undo_ftplugin .. ' | ' or ''
undo = undo .. 'setl cms< | '
if lang == 'jinja' then
    vim.bo.commentstring = delims.comment[1] .. ' %s ' .. delims.comment[2]
    jinja.start(buf, 'jinja')
    if custom then
        require('jinja.overlay').attach(buf, custom)
    end
else
    local inner = vim.bo.filetype:gsub('%.jinja$', '')
    vim.bo.commentstring = vim.filetype.get_option(inner, 'commentstring')
    require('jinja.regions').attach(buf, lang, delims)
    jinja.start(buf, lang)
    require('jinja.overlay').attach(buf, delims)
end
vim.b.undo_ftplugin = undo .. "lua require('jinja').detach(0)"
