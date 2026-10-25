; extends

; Background of whole Jinja tags, to make them stand out from inner language.
[
  (render_expression)
  (comment)
  (raw_start)
  (raw_end)
] @jinja.tag

; Block tags may have no own node (e.g. `{% if x %}` may be a part of if_block),
; so the range of the start delimiter is expanded up to the end delimiter.
(_
  [
    "{%"
    "{%-"
    "{%+"
  ] @jinja.tag
  (#jinja-tag-range! @jinja.tag))
