-- Templates get filetype `<inner>.jinja` (e.g. `yaml.jinja` for `config.yml.jinja`)
-- to keep features of the inner language working (see DESIGN.md).
vim.filetype.add {
    pattern = {
        ['.*%.jinja'] = function(path, buf)
            local ft, on_detect = require('jinja').inner_filetype(path, buf)
            if ft then
                return ft .. '.jinja', on_detect
            end
        end,
    },
}
