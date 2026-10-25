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
    local node = match[id][#match[id]]
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
