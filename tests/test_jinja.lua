local assert = require 'luassert'

local jinja = require 'jinja'

local custom = {
    block = { '#{', '}#' },
    variable = { '#=', '=#' },
    comment = { '#%', '%#' },
}

after_each(function()
    jinja.setup()
end)

describe('setup', function()
    local cases = {
        { 'opts', 42, 'opts: expected table' },
        { 'delimiters', { delimiters = 42 }, 'opts.delimiters: expected table' },
        { 'entry', { delimiters = { 42 } }, 'opts.delimiters[1]: expected table' },
        { 'dir', { delimiters = { {} } }, 'opts.delimiters[1].dir: expected string' },
        {
            'pair',
            { delimiters = { { dir = '/', block = '#{' } } },
            'opts.delimiters[1].block: expected table',
        },
        {
            'short delimiter',
            { delimiters = { { dir = '/', variable = { '$', '$$' } } } },
            '[Jinja] opts.delimiters[1].variable[1] must be a string with at least 2 characters',
        },
        {
            'missing delimiter',
            { delimiters = { { dir = '/', comment = { '##' } } } },
            '[Jinja] opts.delimiters[1].comment[2] must be a string with at least 2 characters',
        },
    }
    for _, case in ipairs(cases) do
        it('should validate ' .. case[1], function()
            local ok, err = pcall(jinja.setup, case[2])
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find(case[3], 1, true), err)
        end)
    end
end)

describe('delimiters', function()
    it('should return nil without config', function()
        assert.is_nil(jinja.delimiters '/tmp/a/x.yml.jinja')
    end)

    it('should return custom delimiters for files inside matching directories', function()
        jinja.setup { delimiters = { vim.tbl_extend('error', { dir = '~/tpl-*' }, custom) } }
        local home = vim.fs.normalize '~'
        assert.same(custom, jinja.delimiters(home .. '/tpl-a/x.yml.jinja'))
        assert.same(custom, jinja.delimiters(home .. '/tpl-b/sub/x.yml.jinja'))
        assert.is_nil(jinja.delimiters(home .. '/tpl/x.yml.jinja'))
        assert.is_nil(jinja.delimiters(home .. '/x/tpl-a/x.yml.jinja'))
    end)

    it('should use default delimiters for not configured tags', function()
        jinja.setup { delimiters = { { dir = '/tpl', variable = custom.variable } } }
        local default = jinja.default_delimiters
        assert.same(
            { block = default.block, variable = custom.variable, comment = default.comment },
            jinja.delimiters '/tpl/x.yml.jinja'
        )
    end)

    it('should return the first matching entry', function()
        jinja.setup {
            delimiters = {
                { dir = '/tpl/a', variable = { '[[', ']]' } },
                { dir = '/tpl', variable = custom.variable },
                { dir = '/tpl/b', variable = { '<<', '>>' } },
            },
        }
        assert.same({ '[[', ']]' }, jinja.delimiters('/tpl/a/x.jinja').variable)
        assert.same(custom.variable, jinja.delimiters('/tpl/b/x.jinja').variable)
    end)
end)
