local assert = require 'luassert'

local child = require('mini.test').new_child_neovim()
teardown(child.stop)

-- Parsers and queries installed by nvim-treesitter for tests (see tests/run.lua).
local site = vim.fn.stdpath 'data' .. '/site'
local dir = vim.fn.stdpath 'cache' .. '/jinja'

before_each(function()
    child.restart { '--cmd', 'set rtp+=.', '--cmd', 'set rtp^=' .. site }
    child.o.lines, child.o.columns = 10, 40
end)

---@param path string
---@param lines string[]
local function edit(path, lines)
    child.cmd('edit ' .. vim.fn.fnameescape(path))
    child.api.nvim_buf_set_lines(0, 0, -1, true, lines)
end

-- Returns nil instead of vim.NIL for missing values.
---@param code string
local function get(code)
    local value = child.lua(code)
    if value ~= vim.NIL then
        return value
    end
end

local function lang()
    return get [[
        local active = vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()]
        return active and active.tree:lang()
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

describe('default delimiters', function()
    before_each(function()
        edit(dir .. '/a.yml.jinja', {
            'k: 1',
            '{% if x %}',
            '{% raw %}r: 2{% endraw %}',
            '{% endif %}',
        })
    end)

    it('should start jinja highlighting', function()
        assert.equals('jinja', child.bo.filetype)
        assert.equals('jinja', lang())
        assert.equals('yaml', child.b.jinja_lang)
        assert.equals('{# %s #}', child.bo.commentstring)
    end)

    it('should inject inner language into text and raw block', function()
        assert.is_true(vim.list_contains(captures(0, 0), 'yaml:property'))
        assert.is_true(vim.list_contains(captures(2, 9), 'yaml:property'))
    end)

    it('should highlight whole tags', function()
        assert.same({
            { 1, 0, 1, 10 },
            { 2, 0, 2, 9 },
            { 2, 13, 2, 25 },
            { 3, 0, 3, 11 },
        }, tag_ranges())
    end)

    it('should stop highlighting on filetype change', function()
        child.bo.filetype = 'text'
        assert.is_nil(lang())
        assert.is_nil(get 'return vim.b.jinja_lang')
    end)
end)

describe('custom delimiters', function()
    before_each(function()
        child.lua(
            [[ require('jinja').setup { delimiters = { { dir = ..., variable = { '#=', '=#' } } } } ]],
            { dir }
        )
        child.api.nvim_set_hl(0, '@jinja.tag', { bg = '#ff0000' })
        edit(dir .. '/a.yml.jinja', { 'k: 1 # a #= x =#' })
    end)

    it('should start inner language highlighting', function()
        assert.equals('_jinja', child.bo.filetype)
        assert.equals('yaml', lang())
        assert.equals('{# %s #}', child.bo.commentstring)
    end)

    it('should highlight tags on top of inner language', function()
        local attr = child.get_screenshot().attr[1]
        -- Spaces inside of YAML comment: outside and inside of the tag.
        assert.is_not.equals(attr[7], attr[12])
    end)

    it('should not affect files outside of configured directories', function()
        edit(dir .. '-other/a.yml.jinja', { 'k: #= x =#' })
        assert.equals('jinja', child.bo.filetype)
    end)
end)
