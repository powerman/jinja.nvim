--[[ Hiding of Jinja tags from the inner language parser ]]
--
--  The inner language parser is the root parser of the buffer,
--  but it parses only the text outside of Jinja tags,
--  like the inner language injected into the jinja parser tree.

local overlay = require 'jinja.overlay'

local M = {}

---@class _JinjaRegions
---@field lang string Language of the root parser.
---@field delims JinjaDelimiters

---@type table<integer, _JinjaRegions>
local attached = {}

---@type table<integer, true>
local subscribed = {}

---@type table<integer, true>
local scheduled = {}

-- Returns ranges of text outside of Jinja tags (including raw block body).
---@param lines string[]
---@param delims JinjaDelimiters
---@return Range6[]
function M.ranges(lines, delims)
    local text = table.concat(lines, '\n')
    local _, tags = overlay.mask(text, delims)
    local position = overlay.positions(lines)
    local ranges = {}
    ---@param from integer 1-based, inclusive.
    ---@param to integer 1-based, exclusive.
    local function add(from, to)
        if from < to then
            local sr, sc = position(from)
            local er, ec = position(to)
            ranges[#ranges + 1] = { sr, sc, from - 1, er, ec, to - 1 }
        end
    end
    local from = 1
    for _, tag in ipairs(tags) do
        add(from, tag[1])
        from = tag[2]
    end
    -- Trailing newline makes ranges non-empty, because empty ranges mean the whole buffer.
    add(from, #text + 2)
    return ranges
end

-- Root tree is usually parsed by `parse()` without a range, because its region is empty,
-- and other plugins expect this, so it must be the same for the root tree with regions.
---@param parser vim.treesitter.LanguageTree
local function parse_without_range(parser)
    if rawget(parser, '_parse_regions') then
        return
    end
    local parse_regions = parser._parse_regions
    -- NOTE: LanguageTree:_parse_regions() is a private method,
    -- if it'll be renamed then other plugins will get outdated trees after changes
    -- (see DESIGN.md).
    parser._parse_regions = function(self, range, ...)
        return parse_regions(self, range or true, ...)
    end
end

---@param buf integer
---@param ranges Range6[]
local function set(buf, ranges)
    -- Root parser of the buffer is the one used for its filetype by other plugins.
    local lang = attached[buf].lang
    if vim.treesitter.language.get_lang(vim.bo[buf].filetype) ~= lang then
        return
    end
    local parser = vim.treesitter.get_parser(buf, lang)
    if parser then
        -- NOTE: LanguageTree:set_included_regions() is a private API used for injections,
        -- but there is no public API to exclude text from the root parser.
        -- If it'll be removed then templates with default delimiters should use jinja parser
        -- as the root one with injected inner language (see DESIGN.md for fallback).
        parser:set_included_regions { ranges }
        parse_without_range(parser)
    end
end

---@param buf integer
local function update(buf)
    scheduled[buf] = nil
    local state = attached[buf]
    if state and vim.api.nvim_buf_is_loaded(buf) then
        set(buf, M.ranges(vim.api.nvim_buf_get_lines(buf, 0, -1, false), state.delims))
    end
end

-- Treesitter adjusts regions on edits itself,
-- so they need to be recalculated only to add or remove tags,
-- which can be done once for all changes made at the same time (e.g. by `:s`).
---@param buf integer
local function schedule_update(buf)
    if not scheduled[buf] then
        scheduled[buf] = true
        vim.schedule(function()
            update(buf)
        end)
    end
end

-- Makes root parser of the buffer for given language to ignore Jinja tags.
-- Should be called before starting treesitter highlighting to avoid reparsing.
---@param buf integer
---@param lang string
---@param delims JinjaDelimiters
function M.attach(buf, lang, delims)
    attached[buf] = { lang = lang, delims = delims }
    update(buf)
    if subscribed[buf] then
        return
    end
    subscribed[buf] = true
    vim.api.nvim_buf_attach(buf, false, {
        on_bytes = function(_, b)
            if not attached[b] then
                subscribed[b] = nil
                return true
            end
            schedule_update(b)
        end,
        on_reload = function(_, b)
            schedule_update(b)
        end,
        on_detach = function(_, b)
            attached[b], subscribed[b] = nil, nil
        end,
    })
end

-- Makes the parser (if it is the one used for the buffer) to parse the whole buffer again.
---@param buf integer
---@param parser? vim.treesitter.LanguageTree
function M.detach(buf, parser)
    if attached[buf] and parser and parser:lang() == attached[buf].lang then
        parser:set_included_regions { {} }
        parser._parse_regions = nil
    end
    attached[buf] = nil
end

return M
