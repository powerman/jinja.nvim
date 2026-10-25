# jinja.nvim

[![License MIT](https://img.shields.io/badge/license-MIT-royalblue.svg)](LICENSE)
[![Neovim 0.12+](https://img.shields.io/badge/Neovim-0.12%2B-royalblue?logo=neovim&logoColor=white)](https://neovim.io/)
[![Lua 5.1](https://img.shields.io/badge/Lua-5.1-blue)](https://www.lua.org/)
[![Test](https://img.shields.io/github/actions/workflow/status/powerman/jinja.nvim/test.yml?label=test)](https://github.com/powerman/jinja.nvim/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/powerman/jinja.nvim?color=blue)](https://github.com/powerman/jinja.nvim/releases/latest)

## About

Neovim plugin for treesitter highlighting of Jinja templates, including custom delimiters.

Jinja allows changing tag delimiters (e.g. Copier's `_envops` or Cookiecutter's
`_jinja2_env_vars`), but treesitter jinja parser supports only default ones.
This plugin highlights both kinds of templates, together with the language of the template
output (inner language) detected by file name without `.jinja` (e.g. `config.yml.jinja`).

## Features

- Templates with default delimiters (filetype `jinja`):
  - Jinja tags are highlighted by treesitter jinja parser.
  - Inner language is injected into text outside of tags and into raw blocks.
- Templates with custom delimiters (filetype `_jinja`):
  - Inner language is highlighted by its own treesitter parser.
  - Jinja tags are highlighted on top of it using treesitter jinja parser.
  - Custom delimiters are configured per directory.
- Whole Jinja tags are captured as `@jinja.tag` (e.g. to add a background).
- Sets `commentstring` to Jinja comment.
- Starts treesitter highlighting by itself.

## Requirements

- Neovim 0.12+.
- Treesitter parsers and highlight queries for `jinja`, `jinja_inline` and inner languages,
  e.g. installed by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

## Installation

Install the plugin with your preferred package manager.
The plugin loads its modules only when needed, so it should not be lazy-loaded.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
    'powerman/jinja.nvim',
    opts = {
        -- Your configuration here, if any.
    },
}
```

## Setup

You should call `setup()` only if you need custom delimiters
(package managers configured as shown above will do this for you).
It must be called before opening templates, because it affects filetype detection.

```lua
require('jinja').setup {
    -- Your configuration here, if any.
}
```

## Configuration

```lua
---@type JinjaConfig
local defaults = {
    -- Custom delimiters for templates inside directories matching `dir` glob.
    -- The first matching entry wins.
    delimiters = {
        -- {
        --     dir = '~/Templates/copier-*', -- Matches all subdirectories too.
        --     -- Start and end strings, not set ones keep default values.
        --     -- Custom delimiters can't be shorter than default ones.
        --     block = { '{%', '%}' },
        --     variable = { '{{', '}}' },
        --     comment = { '{#', '#}' },
        -- },
    },
}
```

Example. Copier templates with `_envops` changing delimiters
to look like comments in YAML, TOML, shell scripts, etc.:

```lua
require('jinja').setup {
    delimiters = {
        {
            dir = '~/Templates/copier-*',
            block = { '#{', '}#' },
            variable = { '#=', '=#' },
            comment = { '#%', '%#' },
        },
    },
}
```

## Highlighting

Tokens inside Jinja tags are highlighted with usual treesitter groups like `@keyword.jinja`.
Whole Jinja tags are captured as `@jinja.tag` group, which is not defined by default.
Define it to make tags stand out, e.g. with a background.
Like other highlight groups it is cleared on loading a color scheme,
so define it in your color scheme config
or in a `ColorScheme` autocommand created before loading a color scheme:

```lua
vim.api.nvim_create_autocmd('ColorScheme', {
    callback = function()
        vim.api.nvim_set_hl(0, '@jinja.tag', { bg = '#2a3448' })
    end,
})
```

Example. Use a light background for tags with
[tokyonight.nvim](https://github.com/folke/tokyonight.nvim):

```lua
require('tokyonight').setup {
    on_highlights = function(hl, c)
        hl['@jinja.tag'] = { bg = require('tokyonight.util').blend_bg(c.cyan, 0.15) }
    end,
}
```

## How it works

Treesitter parser of a buffer is chosen by its filetype (e.g. for folds and indentation),
so templates with custom delimiters need a separate filetype `_jinja`
to use inner language parser instead of jinja parser.

To highlight tags in `_jinja` buffers the buffer text is masked before parsing it
with jinja parser: text outside of tags is replaced by spaces
and custom delimiters are replaced by default ones (padded by spaces if needed).

## Limitations

- Templates with custom delimiters:
  - Inner language parser sees Jinja tags as a text,
    so choose delimiters which won't break inner language syntax (e.g. look like comments).
  - End delimiter inside a string in a tag (e.g. `#= '=#' =#`) ends the tag.
  - Line statements and line comments are not supported.
- Indentation is not provided.
