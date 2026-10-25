local M = {}

---@class JinjaDelimiters
---@field block string[] Start and end strings of block tags.
---@field variable string[] Start and end strings of variable tags.
---@field comment string[] Start and end strings of comment tags.

---@class JinjaCustomDelimiters
---@field dir string Glob matching directories with templates (e.g. `~/Templates/copier-*`).
---@field block? string[] Start and end strings of block tags.
---@field variable? string[] Start and end strings of variable tags.
---@field comment? string[] Start and end strings of comment tags.

---@class JinjaConfig
---@field delimiters? JinjaCustomDelimiters[] Custom delimiters, the first matching entry wins.

---@type JinjaDelimiters
M.default_delimiters = {
    block = { '{%', '%}' },
    variable = { '{{', '}}' },
    comment = { '{#', '#}' },
}

---@class _JinjaCustomDelimiters
---@field glob vim.lpeg.Pattern Matches files inside configured directories.
---@field delimiters JinjaDelimiters

---@type _JinjaCustomDelimiters[]
local custom = {}

---@param name string
---@param pair any
---@param default string[]
local function validate_pair(name, pair, default)
    vim.validate(name, pair, 'table', true)
    if pair == nil then
        return
    end
    for i = 1, 2 do
        if type(pair[i]) ~= 'string' or #pair[i] < #default[i] then
            -- Shorter delimiters can't be replaced by default ones without shifting positions.
            error(
                ('[Jinja] %s[%d] must be a string with at least %d characters'):format(
                    name,
                    i,
                    #default[i]
                ),
                0
            )
        end
    end
end

---Configures custom delimiters.
---@param opts? JinjaConfig
function M.setup(opts)
    vim.validate('opts', opts, 'table', true)
    opts = opts or {}
    vim.validate('opts.delimiters', opts.delimiters, 'table', true)

    local new = {}
    for i, entry in ipairs(opts.delimiters or {}) do
        local name = ('opts.delimiters[%d]'):format(i)
        vim.validate(name, entry, 'table')
        vim.validate(name .. '.dir', entry.dir, 'string')
        for kind, default in pairs(M.default_delimiters) do
            validate_pair(name .. '.' .. kind, entry[kind], default)
        end
        new[i] = {
            glob = vim.glob.to_lpeg(vim.fs.normalize(entry.dir) .. '/**'),
            -- Like Jinja environment options, delimiters not set explicitly keep defaults.
            delimiters = {
                block = entry.block or M.default_delimiters.block,
                variable = entry.variable or M.default_delimiters.variable,
                comment = entry.comment or M.default_delimiters.comment,
            },
        }
    end
    custom = new
end

---Returns custom delimiters configured for a directory containing the file, if any.
---@param path string Absolute path to the file.
---@return JinjaDelimiters|nil
function M.delimiters(path)
    for _, entry in ipairs(custom) do
        if entry.glob:match(path) then
            return entry.delimiters
        end
    end
end

---Returns filetype of the template output, detected by file name without `.jinja`.
---@param path string
---@param buf? integer Buffer with the template, used for detection by content.
---@return string|nil filetype
---@return fun(buf: integer)|nil on_detect
function M.inner_filetype(path, buf)
    local name = path:match '^(.+)%.jinja$'
    if name then
        return vim.filetype.match { filename = name, buf = buf }
    end
end

---@type table<integer, string>
local started = {}

---Starts treesitter highlighting unless it is already started for the same language.
---@param buf integer
---@param lang string|nil
function M.start(buf, lang)
    local active = vim.treesitter.highlighter.active[buf]
    if active and active.tree:lang() == lang then
        started[buf] = lang
    elseif lang and vim.treesitter.language.add(lang) then
        vim.treesitter.start(buf, lang)
        started[buf] = lang
    end
end

---Disables everything enabled for the template by ftplugin.
---@param buf integer
function M.detach(buf)
    buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
    require('jinja.overlay').detach(buf)
    -- Highlighting for a new filetype may be already started by FileType autocommands.
    local active = vim.treesitter.highlighter.active[buf]
    local ours = active and active.tree:lang() == started[buf]
    require('jinja.regions').detach(buf, ours and active.tree or nil)
    if ours then
        vim.treesitter.stop(buf)
    end
    started[buf] = nil
end

return M
