; extends

; Inject inner language into text of Jinja templates.
; The b:jinja_lang variable is set in ftplugin/jinja.lua,
; and used by the set-jinja-lang! directive (plugin/jinja.lua).
; Raw block body is not processed by Jinja, so it is also a text of the inner language.
([
  (content)
  (raw_body)
] @injection.content
  (#set-jinja-lang!)
  (#set! injection.combined))
