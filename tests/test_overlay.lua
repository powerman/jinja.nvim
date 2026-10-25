local assert = require 'luassert'

local overlay = require 'jinja.overlay'

local default = require('jinja').default_delimiters

local custom = {
    block = { '#{', '}#' },
    variable = { '#=', '=#' },
    comment = { '#%', '%#' },
}

local long = {
    block = { '<%%', '%%>' },
    variable = { '<%=', '=%>' },
    comment = { '<%#', '#%>' },
}

-- Converts highlights to a list of "text:group" for readable assertions.
local function hl(text, delims)
    local lines = vim.split(text, '\n')
    local out = {}
    local rows = overlay.highlights(lines, delims or default)
    for row = 0, #lines - 1 do
        local line = lines[row + 1]
        for _, h in ipairs(rows[row] or {}) do
            out[#out + 1] = line:sub(h[2] + 1, h[3] or #line) .. ':' .. h[4]
        end
    end
    return out
end

local function tags_only(highlights)
    return vim.tbl_filter(function(s)
        return s:find('@jinja.tag', 1, true) ~= nil
    end, highlights)
end

describe('mask', function()
    it('should replace text outside of tags by spaces', function()
        local masked, tags = overlay.mask('a {{ x }}\nb ${{ y }}', default)
        assert.equals('  {{ x }}\n   {{ y }}', masked)
        assert.same({ { 3, 10, 'variable' }, { 14, 21, 'variable' } }, tags)
    end)

    it('should replace custom delimiters by default ones', function()
        local masked, tags = overlay.mask('k: ${{ x }} #= a -=#\n#{ if b }#', custom)
        assert.equals('            {{ a -}}\n{% if b %}', masked)
        assert.same({ { 13, 21, 'variable' }, { 22, 32, 'block' } }, tags)
    end)

    it('should replace custom comment delimiters by default ones', function()
        local masked, tags = overlay.mask('#% note %# #{ else }#', custom)
        assert.equals('{# note #} {% else %}', masked)
        assert.same({ { 1, 11, 'comment' }, { 12, 22, 'block' } }, tags)
    end)

    it('should pad longer custom delimiters outside of default ones', function()
        local masked, tags = overlay.mask('x <%=- a -=%> <%% if b %%>', long)
        assert.equals('   {{- a -}}   {% if b %} ', masked)
        assert.same({ { 3, 14, 'variable' }, { 15, 27, 'block' } }, tags)
    end)

    it('should prefer the longest start delimiter', function()
        local delims = {
            block = { '[[%', '%]]' },
            variable = { '[[', ']]' },
            comment = { '[[#', '#]]' },
        }
        local masked, tags = overlay.mask('[[ a ]] [[% if b %]]', delims)
        assert.equals('{{ a }}  {% if b %} ', masked)
        assert.same({ { 1, 8, 'variable' }, { 9, 21, 'block' } }, tags)
    end)

    it('should support multiline tags', function()
        local masked = overlay.mask('a {#\nnote\n#} b', default)
        assert.equals('  {#\nnote\n#}  ', masked)
    end)

    it('should continue tag until the end delimiter on next lines', function()
        local masked, tags = overlay.mask('a {{ x\nb {{ y }}', default)
        assert.equals('  {{ x\nb {{ y }}', masked)
        assert.same({ { 3, 17, 'variable' } }, tags)
    end)

    it('should end tag without end delimiter at the end of line', function()
        local masked, tags = overlay.mask('a {{ x\nb', default)
        assert.equals('  {{ x\n ', masked)
        assert.same({ { 3, 7, 'variable' } }, tags)
    end)

    it('should mask text inside raw block', function()
        local masked, tags = overlay.mask('#{ raw }# #= x =# #{- endraw }# #= y =#', custom)
        assert.equals('{% raw %}         {%- endraw %} {{ y }}', masked)
        assert.same({ { 1, 10, 'block' }, { 19, 32, 'block' }, { 33, 40, 'variable' } }, tags)
    end)

    it('should parse text after raw block without endraw', function()
        local masked, tags = overlay.mask('#{ raw }# #= x =#', custom)
        assert.equals('{% raw %} {{ x }}', masked)
        assert.same({ { 1, 10, 'block' }, { 11, 18, 'variable' } }, tags)
    end)
end)

describe('highlights', function()
    it('should ignore lines without tags', function()
        assert.same({}, hl 'key: [value] # comment')
        assert.same({}, hl('key: ${{ github.ref }} {% raw %}', custom))
    end)

    it('should highlight tag background', function()
        assert.same({ '#= a =#:@jinja.tag' }, tags_only(hl('/bin/#= a =#', custom)))
        assert.same(
            { '{#:@jinja.tag', 'note:@jinja.tag', '#}:@jinja.tag' },
            tags_only(hl 'x {#\nnote\n#} y')
        )
    end)

    describe('with jinja parser', function()
        it('should be installed for tests', function()
            assert.is_true(vim.treesitter.language.add 'jinja')
        end)

        it('should highlight tag tokens', function()
            assert.same({
                "#{ if not (type == 'go') }#:@jinja.tag",
                '#{:@keyword.directive.jinja',
                'if:@keyword.conditional.jinja',
                '(:@punctuation.bracket.jinja',
                'type:@variable.jinja',
                '==:@operator.jinja',
                "'go':@string.jinja",
                '):@punctuation.bracket.jinja',
                '}#:@keyword.directive.jinja',
            }, hl("#{ if not (type == 'go') }#", custom))
        end)

        it('should highlight padding of longer delimiters', function()
            assert.same({
                '<%=- a -=%>:@jinja.tag',
                '<%=-:@keyword.directive.jinja',
                'a:@variable.jinja',
                '-=%>:@keyword.directive.jinja',
            }, hl('<%=- a -=%>', long))
        end)

        it('should not highlight raw block body', function()
            assert.same({
                '#{ raw }#:@jinja.tag',
                '#{ raw }#:@keyword.jinja',
                '#{ endraw }#:@jinja.tag',
                '#{ endraw }#:@keyword.jinja',
            }, hl('#{ raw }#\nk: #= x =#\n#{ endraw }#', custom))
        end)

        it('should highlight comment with custom delimiters', function()
            assert.same({
                '#% note %#:@jinja.tag',
                '#% note %#:@comment.jinja',
            }, hl('#% note %#', custom))
        end)
    end)
end)
