# Design

Why templates get filetype `<inner>.jinja` with inner language as the root parser,
and which alternatives were considered.

## Goal

A template is a file of its inner language (the language of the template output),
so users expect all features of the inner language to work in it.
Jinja itself is just an addition on top of it.
Custom delimiters must not change anything for users.

## Constraints

- Jinja treesitter grammar has delimiters hardcoded as literal tokens in the lexer,
  and treesitter can't configure grammars at runtime.
  So custom delimiters can be supported only by changing the text before parsing.
  There was no existing solution for this in Neovim or Vim plugins.
- A buffer has a single root parser, which gets the whole text.
  Other languages are injected into regions of its tree.
- The root language is chosen by filetype with `vim.treesitter.language.get_lang()`,
  and filetype to language mapping is global.
  Everything calling `vim.treesitter.get_parser(buf)` without a language
  (folds, indentation, textobjects, `get_node()`, `:Inspect`, etc.) uses it.
- Inner language parser can't parse the whole template:
  e.g. YAML parser gets an error on the first `{% if %}`
  and nothing after it is highlighted.

Compound filetype `a.b` in Vim means "main filetype `a` with addition `b`"
(e.g. `yaml.ansible`, `markdown.vimwiki`):

- ftplugins of all parts are loaded;
- `get_lang()` uses the first part;
- `FileType` autocommands and LSP clients match only the whole filetype;
- conform.nvim checks the whole filetype, then its parts from the last to the first,
  and ignores empty tables;
- nvim-lint also uses tools of the filetype parts.

## Current approach

- Templates with known inner language get filetype `<inner>.jinja` with any delimiters.
- The root parser is the inner language one,
  but it parses only the text outside of Jinja tags (including raw block body),
  set by `LanguageTree:set_included_regions()`.
  Regions are recalculated after changes.
- Jinja tags are highlighted by overlay on top of the inner language:
  masked text is parsed by jinja parser,
  with custom delimiters replaced by default ones.
- Templates without known inner language get filetype `jinja` with jinja root parser.

### Private API

`LanguageTree:set_included_regions()` is private,
but it is used by injections since at least Neovim 0.9
and its docstring mentions template languages as its use case.
There are no plans to remove it:

- draft [neovim#36030](https://github.com/neovim/neovim/pull/36030)
  (stalled since October 2025) considers keeping it with a stricter API
  accepting only `Range6[]`;
- [neovim#39454](https://github.com/neovim/neovim/issues/39454)
  proposes to replace internal `Range6` with `vim.range`.

So the plugin passes `Range6[]`.

The root tree is usually parsed by `parse()` without a range, because its region is empty.
With non-empty regions `parse()` without a range doesn't parse the root tree,
so other plugins would get outdated trees after changes (or none after adding a tag).
To avoid this the plugin overrides private `LanguageTree:_parse_regions()`
on its parser instance.
If it'll be renamed, other plugins will get outdated trees again, but nothing will fail.

If `set_included_regions()` will be removed,
then fallback is alternative "Jinja root registered for `<inner>.jinja`" below.

## Alternatives

Measured with a bash template having a function inside `{% if %}`,
with default delimiters for jinja root and with custom ones for bash root:

| Feature                    | `jinja` | `_jinja` | `jinja.sh` | `sh.jinja` ¹ | `sh.jinja` ² | `sh._jinja` |
| -------------------------- | ------- | -------- | ---------- | ------------ | ------------ | ----------- |
| Root parser                | jinja   | bash     | jinja      | jinja        | bash         | bash        |
| `get_lang(ft)`             | jinja   | ✗ none   | jinja      | jinja        | bash         | bash        |
| Highlighting, `:Inspect`   | ✓       | ✓        | ✓          | ✓            | ✓            | ✓           |
| Folds, indent, textobjects | ✓       | ✗        | ✓          | ✓            | ✓            | ✓           |
| `gcc` (Comment.nvim)       | ✓       | ✗        | ✓          | ✓            | ✓            | ✓           |
| `get_node()`               | jinja   | ✗        | jinja      | jinja        | ✓            | ✓           |
| Inner language ftplugin    | ✗       | ✗        | ✓          | ✓            | ✓            | ✓           |
| `FileType sh`, bashls      | ✗       | ✗        | ✗          | ✗            | ✗            | ✗           |
| conform.nvim checks        | `jinja` | —        | sh, jinja  | jinja, sh    | jinja, sh    | \_jinja, sh |
| jinja-lsp (default config) | ✓       | ✗        | ✗          | ✗            | ✗            | ✗           |

¹ With `vim.treesitter.language.register('jinja', 'sh.jinja')`.
² Current approach.

Jinja root works fine for most features, because they take injections into account,
but `get_node()` returns a jinja node there.
Features working with LSP or `FileType` autocommands
can't be fixed by the plugin for any compound filetype,
users have to add `<inner>.jinja` to their configs.

### Separate `jinja` and `_jinja` (initial implementation)

Filetype `jinja` with jinja root for default delimiters
and `_jinja` with inner root for custom ones.

- ✗ There is no `_jinja` parser, so `get_parser(buf)` returns nil
  and everything except highlighting is broken for custom delimiters.
- ✗ No inner language ftplugin.
- ✗ Users see different filetypes for the same kind of files.

### `jinja.<inner>` and `<inner>.jinja`

`jinja.<inner>` gives jinja root for default delimiters by the first part,
`<inner>.jinja` gives inner root for custom ones.

- ✓ Only public API.
- ✗ Modes differ by order of filetype parts.
- ✗ conform.nvim checks `<inner>` before `jinja` for default delimiters,
  so inner language formatters can't be disabled with a single `jinja` key.
- ✗ `get_node()` returns a jinja node for default delimiters.

### Jinja root registered for `<inner>.jinja`

`<inner>.jinja` with jinja root registered by `vim.treesitter.language.register()`
for default delimiters and `<inner>._jinja` with inner root for custom ones.
Custom delimiters need another filetype, because registration is global.

- ✓ Only public API.
- ✓ conform.nvim checks the jinja key first in both modes.
- ✗ Modes differ by filetype suffix.
- ✗ Each inner filetype has to be registered.
- ✗ `get_node()` returns a jinja node for default delimiters.

### `<inner>.jinja` with inner root (chosen)

- ✓ Matches the goal: same filetype and same behaviour with any delimiters.
- ✓ All treesitter features see the inner language, including `get_node()`.
- ✗ Depends on two private APIs (see above).
- ✗ Inner language parser sees the text without tags,
  so a tag used as a value may break its syntax (e.g. `k = {{ x }}` in TOML).
  Errors stay local, the rest of the file is parsed correctly.
- ✗ Regions are recalculated after changes.

It was chosen because it is the only alternative matching the goal,
private APIs look stable enough and are used in a way failing gracefully.

## Tools of the inner language

Tools using compound filetype parts see Jinja tags.
E.g. results of formatters on templates (default / custom delimiters):

- yamlfmt fails / formats, but may change tags indentation;
- taplo fails / fails on a tag used as a value;
- shfmt formats both.

Formatters never know about tags, so it's better to disable them for templates
(see README.md).
Also a formatter configured for `jinja` (e.g. djlint) runs for all templates.

LSP clients attach only to the exact filetypes listed in their configs.
jinja-lsp supports only default delimiters
and provides completion, hover, go to definition and diagnostics
("Undefined variable", "Template not found") using backend code in Rust or Python.
It's useless for Copier or Cookiecutter templates,
where variables are defined in `copier.yml` or `cookiecutter.json`.
It can be enabled for templates with
`vim.lsp.config('jinja_lsp', { filetypes = { 'jinja', 'html.jinja' } })`.

## Implementation notes

- Jinja grammar has hardcoded line comments (`##`) and partially line statements (`#`),
  which are disabled in Jinja by default.
  With jinja root parser they hide e.g. `## Heading` comments of the inner language,
  but text outside of tags is masked before parsing it with jinja parser.

- Inner filetype is detected in `ftdetect/` instead of a `FileType` autocommand,
  because detection by content (e.g. by shebang for `*.sh.jinja`) doesn't work
  when `did_filetype()` is true.
- Detection by content uses the template text,
  e.g. a file without extension with lines starting with `#` is detected as `conf`.
- Neovim 0.13 runtime has `ftplugin/jinja.vim`, which sets `commentstring`
  and overwrites `b:undo_ftplugin`.
  So the plugin's ftplugin is in `after/ftplugin/`
  and integration tests set `runtimepath` like plugin managers do.
