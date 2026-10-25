local assert = require 'luassert'

local child = require('mini.test').new_child_neovim()
teardown(child.stop)

-- Parsers and queries installed by nvim-treesitter for tests (see tests/run.lua).
local data = vim.fn.stdpath 'data'
local dir = vim.fn.stdpath 'cache' .. '/jinja'
local custom_dir = dir .. '/custom'

before_each(function()
    -- Like plugin managers, to load ftplugins in the same order.
    child.restart {
        '--cmd',
        'set rtp^=. rtp+=./after',
        '--cmd',
        'set rtp^=' .. data .. '/site',
        '--cmd',
        'set rtp+=' .. data .. '/lazy/nvim-treesitter',
    }
    child.o.lines, child.o.columns = 10, 40
    child.lua(
        [[
            require('jinja').setup {
                delimiters = {
                    { dir = ..., block = { '#{', '}#' }, variable = { '#=', '=#' }, comment = { '#%', '%#' } },
                },
            }
        ]],
        { custom_dir }
    )
    child.api.nvim_set_hl(0, '@jinja.tag', { bg = '#ff0000' })
end)

---@param lines string[]
local function to_custom(lines)
    return vim.tbl_map(function(line)
        return (line:gsub('{%%', '#{'):gsub('%%}', '}#'):gsub('{{', '#='):gsub('}}', '=#'))
    end, lines)
end

---@param path string
---@param lines string[]
local function edit(path, lines)
    vim.fn.mkdir(vim.fs.dirname(path), 'p')
    vim.fn.writefile(lines, path)
    child.cmd('edit! ' .. vim.fn.fnameescape(path))
end

-- Returns nil instead of vim.NIL for missing values.
---@param code string
local function get(code)
    local value = child.lua(code)
    if value ~= vim.NIL then
        return value
    end
end

local function highlighter_lang()
    return get [[
        local active = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
        return active and active.tree:lang()
    ]]
end

-- Returns language, parse errors and amount of included ranges
-- of the root parser used by other plugins.
local function root()
    return child.lua [[
        -- Wait for regions update scheduled after the last change.
        vim.wait(0)
        local parser = vim.treesitter.get_parser()
        if parser then
            local tree = parser:parse()[1]
            return { parser:lang(), tree:root():has_error(), #tree:included_ranges() }
        end
        return {}
    ]]
end

local function captures(row, col)
    return child.lua(
        [[
            vim.treesitter.get_parser():parse(true)
            local names = {}
            for _, c in ipairs(vim.treesitter.get_captures_at_pos(0, ...)) do
                names[#names + 1] = c.lang .. ':' .. c.capture
            end
            return names
        ]],
        { row, col }
    )
end

-- Unlike get_captures_at_pos() it takes into account ranges set by directives, like highlighter.
local function tag_ranges()
    return child.lua [[
        local tree = vim.treesitter.get_parser():parse()[1]
        local query = vim.treesitter.query.get('jinja', 'highlights')
        local ranges = {}
        for id, node, metadata in query:iter_captures(tree:root(), 0) do
            if query.captures[id] == 'jinja.tag' then
                local r = vim.treesitter.get_range(node, 0, metadata[id])
                ranges[#ranges + 1] = { r[1], r[2], r[4], r[5] }
            end
        end
        return ranges
    ]]
end

local templates = {
    {
        name = 'a.yml.jinja',
        ft = 'yaml.jinja',
        lang = 'yaml',
        lines = {
            'k: 1',
            '{% if x %}',
            'v: {{ y }}',
            '{% raw %}r: 2{% endraw %}',
            '{% endif %}',
        },
        captures = {
            { 0, 0, 'yaml:property' },
            { 2, 0, 'yaml:property' },
            { 3, 9, 'yaml:property' },
        },
    },
    {
        name = 'a.toml.jinja',
        ft = 'toml.jinja',
        lang = 'toml',
        lines = {
            'k = 1',
            '{% if x %}',
            's = "{{ y }}"',
            '{% endif %}',
            '[t]',
            'a = 2',
        },
        captures = {
            { 0, 0, 'toml:property' },
            { 2, 0, 'toml:property' },
            { 5, 0, 'toml:property' },
        },
    },
    {
        name = 'a.sh.jinja',
        ft = 'sh.jinja',
        lang = 'bash',
        lines = {
            '#!/bin/bash',
            '{% if x %}',
            'main() {',
            '    echo "{{ y }}"',
            '}',
            '{% endif %}',
        },
        captures = { { 2, 0, 'bash:function' }, { 3, 4, 'bash:function.call' } },
    },
}

for _, mode in ipairs { 'default', 'custom' } do
    local path = mode == 'custom' and custom_dir or dir
    local convert = mode == 'custom' and to_custom
        or function(lines)
            return lines
        end

    describe(mode .. ' delimiters', function()
        for _, t in ipairs(templates) do
            describe(t.name, function()
                before_each(function()
                    edit(path .. '/' .. t.name, convert(t.lines))
                end)

                it('should use inner language as root', function()
                    assert.equals(t.ft, child.bo.filetype)
                    assert.equals(t.lang, highlighter_lang())
                    assert.same({ t.lang, false }, vim.list_slice(root(), 1, 2))
                end)

                it('should highlight inner language', function()
                    for _, c in ipairs(t.captures) do
                        assert.is_true(vim.list_contains(captures(c[1], c[2]), c[3]), c[3])
                    end
                end)

                it('should keep inner language commentstring', function()
                    assert.equals('# %s', child.bo.commentstring)
                end)

                it('should hide added tags from inner language', function()
                    local ranges = root()[3]
                    -- Inside of the text, so treesitter itself would include it into the region.
                    local col = #t.lines[1]
                    child.api.nvim_buf_set_text(0, 0, col, 0, col, convert { '', '{% if z %}' })
                    assert.same({ t.lang, false, ranges + 1 }, root())
                end)
            end)
        end

        it('should provide updated tree to parse() without range', function()
            edit(path .. '/a.yml.jinja', convert { 'k: 1', '{% if x %}' })
            -- In a single call, to avoid parsing by highlighter on redraw.
            local node = get [[
                local parser = vim.treesitter.get_parser()
                parser:parse()
                vim.api.nvim_buf_set_lines(0, -1, -1, true, { 'v: 2' })
                return parser:parse()[1]:root():named_descendant_for_range(2, 0, 2, 0):type()
            ]]
            assert.equals('string_scalar', node)
        end)

        it('should highlight tags on top of inner language', function()
            edit(path .. '/a.yml.jinja', convert { 'k: 1', '{% if x %}' })
            local attr = child.get_screenshot().attr
            -- Spaces outside and inside of the tag.
            assert.is_not.equals(attr[1][3], attr[2][3])
        end)

        it('should provide treesitter features of inner language', function()
            edit(path .. '/a.sh.jinja', convert(templates[3].lines))
            child.lua [[
                vim.wo.foldmethod = 'expr'
                vim.wo.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
            ]]
            assert.equals(1, child.fn.foldlevel(4))
            assert.equals(
                child.fn.shiftwidth(),
                get [[ return require('nvim-treesitter.indent').get_indent(4) ]]
            )
            assert.equals(
                'word',
                get [[ return vim.treesitter.get_node({ pos = { 3, 4 } }):type() ]]
            )
        end)

        it('should stop on filetype change', function()
            edit(path .. '/a.yml.jinja', convert(templates[1].lines))
            assert.is_true(root()[3] > 1)
            child.bo.filetype = 'yaml'
            assert.is_nil(highlighter_lang())
            -- The same parser now parses Jinja tags as YAML.
            assert.equals(1, root()[3])
        end)
    end)
end

describe('template without inner language', function()
    it('should use jinja parser with default delimiters', function()
        edit(
            dir .. '/a.jinja',
            { 'text', '{% if x %}', '{% raw %}r{% endraw %}{{ y }}', '{% endif %}' }
        )
        assert.equals('jinja', child.bo.filetype)
        assert.equals('jinja', highlighter_lang())
        assert.equals('{# %s #}', child.bo.commentstring)
        assert.same({
            { 1, 0, 1, 10 },
            { 2, 0, 2, 9 },
            { 2, 10, 2, 22 },
            { 2, 22, 2, 29 },
            { 3, 0, 3, 11 },
        }, tag_ranges())
    end)

    it('should highlight tags with custom delimiters', function()
        -- Lines starting with `#` would make Neovim to detect inner filetype `conf` by content.
        edit(custom_dir .. '/a.jinja', { 'text', 'x #{ if x }#' })
        assert.equals('jinja', child.bo.filetype)
        assert.equals('#% %s %#', child.bo.commentstring)
        local attr = child.get_screenshot().attr
        assert.is_not.equals(attr[1][3], attr[2][3])
    end)
end)
