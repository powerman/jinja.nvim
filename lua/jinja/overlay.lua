--[[ Highlighting of Jinja tags on top of the inner language ]]
--
--  To highlight tags the buffer text is masked before parsing it with the jinja parser:
--  text outside of tags is replaced by spaces
--  and custom delimiters are replaced by default ones padded by spaces.
--  So custom delimiters can't be shorter than default ones
--  to keep positions in the masked text same as in the buffer.

local default_delimiters = require('jinja').default_delimiters

local M = {}

-- Higher than treesitter (100) to override highlighting of the inner language.
local priority = vim.hl.priorities.treesitter + 10

---@type table<integer, JinjaDelimiters>
local attached = {}

---@class _JinjaHighlight
---@field [1] integer Row (0-based).
---@field [2] integer Start column (0-based, inclusive).
---@field [3] integer|nil End column (0-based, exclusive), nil means end of line.
---@field [4] string Highlight group.

---@type table<integer, { tick: integer, rows: table<integer, _JinjaHighlight[]> }>
local cache = {}

---@class _JinjaTag
---@field [1] integer Start offset (1-based, inclusive).
---@field [2] integer End offset (1-based, exclusive).
---@field [3] string Kind: block, variable or comment.

-- Returns position of the end delimiter of a tag.
-- Like Jinja lexer, skips strings (which may contain the end delimiter) if `strings` is true.
-- Unterminated string is an error in Jinja, so then the first end delimiter is used.
---@param text string
---@param close string End delimiter.
---@param from integer Position after the start delimiter.
---@param strings boolean
---@return integer|nil
local function find_end(text, close, from, strings)
    local pos = from
    while true do
        local s = text:find(close, pos, true)
        -- Search only before the end delimiter to avoid scanning the rest of text for each tag.
        local q = strings and s and text:sub(pos, s - 1):find '[\'"]'
        if not q then
            return s
        end
        q = pos + q - 1
        local quote = text:sub(q, q)
        local e = q + 1
        while true do
            e = text:find('[\\' .. quote .. ']', e)
            if not e then
                return text:find(close, from, true)
            elseif text:sub(e, e) == quote then
                break
            end
            e = e + 2 -- Skip escaped character.
        end
        pos = e + 1
    end
end

-- Returns text with everything outside of Jinja tags replaced by spaces (except newlines)
-- and tag delimiters replaced by default ones, and a list of found tags.
-- Tag without end delimiter in the rest of text ends at the end of line.
---@param text string
---@param delims JinjaDelimiters
---@return string masked
---@return _JinjaTag[] tags
function M.mask(text, delims)
    local parts, tags = {}, {}
    local pos = 1
    while true do
        local kind, start
        for k, d in pairs(delims) do
            local s = text:find(d[1], pos, true)
            -- Like Jinja lexer, prefer the longest start delimiter.
            if s and (not start or s < start or s == start and #d[1] > #delims[kind][1]) then
                kind, start = k, s
            end
        end
        parts[#parts + 1] = text:sub(pos, (start or 0) - 1):gsub('[^\n]', ' ')
        if not start then
            return table.concat(parts), tags
        end

        local open, close = delims[kind][1], delims[kind][2]
        local default = default_delimiters[kind]
        local from = start + #open
        -- Like Jinja lexer, comments end at the first end delimiter.
        local s = find_end(text, close, from, kind ~= 'comment')
        local to = s or text:find('\n', from, true) or #text + 1
        local stop = s and s + #close or to
        local body = text:sub(from, to - 1)
        tags[#tags + 1] = { start, stop, kind }
        -- Padding is added outside to keep whitespace control (e.g. `{{-`) working.
        parts[#parts + 1] = (' '):rep(#open - #default[1])
            .. default[1]
            .. body
            .. (s and default[2] .. (' '):rep(#close - #default[2]) or '')
        pos = stop

        -- Jinja does not parse text inside raw block, so skip it up to the endraw tag.
        if kind == 'block' and s and body:match '^[-+]?%s*raw%s*[-+]?$' then
            local endraw = vim.pesc(open) .. '[-+]?%s*endraw%s*[-+]?' .. vim.pesc(close)
            local e = text:find(endraw, pos)
            if e then
                parts[#parts + 1] = text:sub(pos, e - 1):gsub('[^\n]', ' ')
                pos = e
            end
        end
    end
end

-- Returns a function converting offsets in `table.concat(lines, '\n')` to positions.
-- Offset of the end of the trailing newline is converted to the start of the next row.
---@param lines string[]
---@return fun(offset: integer): integer, integer
function M.positions(lines)
    local line_starts = { 1 }
    for i = 1, #lines do
        line_starts[i + 1] = line_starts[i] + #lines[i] + 1
    end
    ---@param offset integer 1-based.
    ---@return integer row, integer col 0-based.
    return function(offset)
        local lo, hi = 1, #line_starts
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            if line_starts[mid] <= offset then
                lo = mid
            else
                hi = mid - 1
            end
        end
        return lo - 1, offset - line_starts[lo]
    end
end

-- Returns highlights for Jinja tags in lines, grouped by row.
-- Without jinja treesitter parser only tag background is highlighted.
---@param lines string[]
---@param delims JinjaDelimiters
---@return table<integer, _JinjaHighlight[]>
function M.highlights(lines, delims)
    local text = table.concat(lines, '\n')
    local masked, tags = M.mask(text, delims)
    local position = M.positions(lines)

    local rows = {}
    local function add(from, to, hl)
        local sr, sc = position(from)
        local er, ec = position(to)
        local added = {}
        for row = sr, er do
            added[#added + 1] = { row, row == sr and sc or 0, row == er and ec or nil, hl }
            rows[row] = rows[row] or {}
            table.insert(rows[row], added[#added])
        end
        return added
    end

    for _, tag in ipairs(tags) do
        add(tag[1], tag[2], '@jinja.tag')
    end

    local query = #tags > 0
        and vim.treesitter.language.add 'jinja'
        and vim.treesitter.query.get('jinja', 'highlights')
    if not query then
        return rows
    end

    -- Highlights of default delimiters must cover padding of custom ones.
    local widen_from, widen_to = {}, {}
    for _, tag in ipairs(tags) do
        local d, default = delims[tag[3]], default_delimiters[tag[3]]
        widen_from[tag[1] + #d[1] - #default[1]] = tag[1]
        if text:sub(tag[2] - #d[2], tag[2] - 1) == d[2] then
            widen_to[tag[2] - #d[2] + #default[2]] = tag[2]
        end
    end

    local parser = vim.treesitter.get_string_parser(masked, 'jinja')
    local root = parser:parse()[1]:root()
    -- Like treesitter highlighter, the last capture of the same node wins.
    local seen = {}
    -- Tag background is already added above, so skip it if jinja highlights query has it.
    -- Raw block body is masked, so it must keep highlighting of the inner language.
    local skip = {
        spell = true,
        nospell = true,
        ['jinja.tag'] = true,
        ['markup.raw.block'] = true,
    }
    for id, node in query:iter_captures(root, masked) do
        local name = query.captures[id]
        if not name:find '^_' and not skip[name] then
            local _, _, sb, _, _, eb = node:range(true)
            local from, to = sb + 1, eb + 1
            from, to = widen_from[from] or from, widen_to[to] or to
            local hl = '@' .. name .. '.jinja'
            local key = from .. ':' .. to
            if seen[key] then
                for _, h in ipairs(seen[key]) do
                    h[4] = hl
                end
            else
                seen[key] = add(from, to, hl)
            end
        end
    end
    return rows
end

local ns ---@type integer?
local augroup ---@type integer?

local function register()
    if ns then
        return
    end
    ns = vim.api.nvim_create_namespace 'JinjaOverlay'
    augroup = vim.api.nvim_create_augroup('JinjaOverlay', { clear = true })
    vim.api.nvim_set_decoration_provider(ns, {
        on_win = function(_, _, buf)
            if not attached[buf] then
                return false
            end
            local tick = vim.api.nvim_buf_get_changedtick(buf)
            if not cache[buf] or cache[buf].tick ~= tick then
                local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                cache[buf] = { tick = tick, rows = M.highlights(lines, attached[buf]) }
            end
        end,
        on_line = function(_, _, buf, row)
            for _, hl in ipairs(cache[buf].rows[row] or {}) do
                vim.api.nvim_buf_set_extmark(buf, ns, row, hl[2], {
                    end_row = hl[3] and row or row + 1,
                    end_col = hl[3] or 0,
                    hl_group = hl[4],
                    -- Tokens must be drawn over the tag background.
                    priority = hl[4] == '@jinja.tag' and priority or priority + 1,
                    ephemeral = true,
                    -- Inner language may enable spell (e.g. block tags inside YAML comments).
                    spell = hl[4] == '@comment.jinja',
                })
            end
        end,
    })
end

-- Enables highlighting of Jinja tags with given delimiters in the buffer.
---@param buf integer
---@param delims JinjaDelimiters
function M.attach(buf, delims)
    register()
    attached[buf] = delims
    cache[buf] = nil
    vim.api.nvim_clear_autocmds { group = augroup, buffer = buf }
    vim.api.nvim_create_autocmd('BufWipeout', {
        group = augroup,
        buffer = buf,
        callback = function()
            M.detach(buf)
        end,
    })
end

---@param buf integer
function M.detach(buf)
    attached[buf], cache[buf] = nil, nil
    if augroup then
        vim.api.nvim_clear_autocmds { group = augroup, buffer = buf }
    end
end

return M
