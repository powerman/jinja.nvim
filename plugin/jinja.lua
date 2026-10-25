if vim.g.loaded_jinja then
    return
end
vim.g.loaded_jinja = true

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
