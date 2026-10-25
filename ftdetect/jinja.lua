-- Templates with custom delimiters (see `delimiters` option) are highlighted differently.
vim.filetype.add {
    pattern = {
        ['.*%.jinja'] = function(path)
            if require('jinja').delimiters(path) then
                return '_jinja'
            end
        end,
    },
}
