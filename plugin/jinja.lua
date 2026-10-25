if vim.g.loaded_jinja then
    return
end
vim.g.loaded_jinja = true

-- Sets language to inject into text of templates (see queries/jinja/injections.scm).
-- Must be registered globally because jinja may be injected into buffers of other filetypes.
vim.treesitter.query.add_directive('set-jinja-lang!', function(_, _, source, _, metadata)
    if type(source) == 'number' then
        metadata['injection.language'] = vim.b[source].jinja_lang
    end
end, { force = true })

-- Expands range of the block tag start delimiter up to the end delimiter
-- (see queries/jinja/highlights.scm).
vim.treesitter.query.add_directive('jinja-tag-range!', function(match, _, _, pred, metadata)
    local id = pred[2]
    local node = match[id]
    -- Neovim 0.11 may provide a single node instead of a list.
    node = type(node) == 'table' and node[#node] or node
    local last = node:next_sibling()
    while last and not last:type():find '%%}$' do
        last = last:next_sibling()
    end
    if last then
        local sr, sc = node:start()
        local _, _, er, ec = last:range()
        metadata[id] = metadata[id] or {}
        metadata[id].range = { sr, sc, er, ec }
    end
end, { force = true })

local function set_hl()
    vim.api.nvim_set_hl(0, '@jinja.tag', { default = true, link = 'ColorColumn' })
end
set_hl()
vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('Jinja', { clear = true }),
    callback = set_hl,
})
