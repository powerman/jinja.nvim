local assert = require 'luassert'

local regions = require 'jinja.regions'

local default = require('jinja').default_delimiters

-- Converts ranges to a list of included text for readable assertions.
local function included(text)
    local out = {}
    for _, r in ipairs(regions.ranges(vim.split(text, '\n'), default)) do
        out[#out + 1] = (text .. '\n'):sub(r[3] + 1, r[6])
    end
    return out
end

describe('ranges', function()
    it('should include the whole text without tags', function()
        assert.same({ { 0, 0, 0, 2, 0, 8 } }, regions.ranges({ 'a: 1', 'b:' }, default))
    end)

    it('should exclude tags', function()
        assert.same({ 'a: ', '\n', ' b\n' }, included 'a: {{ x }}\n{% if y %} b')
    end)

    it('should exclude multiline tags', function()
        assert.same({ 'a ', ' b\n' }, included 'a {#\nnote\n#} b')
    end)

    it('should include raw block body', function()
        assert.same({ 'r: {{ x }}', '\n' }, included '{% raw %}r: {{ x }}{% endraw %}')
    end)

    it('should include trailing newline for text with tags only', function()
        assert.same({ { 0, 14, 14, 1, 0, 15 } }, regions.ranges({ '{{ x }}{{ y }}' }, default))
    end)

    it('should use positions of included text', function()
        assert.same(
            { { 0, 0, 0, 0, 3, 3 }, { 0, 10, 10, 1, 0, 11 }, { 1, 10, 21, 2, 0, 23 } },
            regions.ranges({ 'a: {{ x }}', '{% if y %}b' }, default)
        )
    end)
end)
