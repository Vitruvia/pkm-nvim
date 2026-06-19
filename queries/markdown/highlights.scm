; extends

; queries/markdown.highlights.scm

; ─── Indented code blocks ──────────────────────────────────────────────────
; Markdown treats 4-space-indented paragraphs as code and highlights them
; green. PKM convention: only backtick-fenced code is code. @pkm.indented
; is linked to Normal in syntax.lua, suppressing the code colour.
(indented_code_block) @pkm.indented

; ─── List markers at all nesting depths ────────────────────────────────────
; Some colorschemes do not define @markup.list for deeply nested items.
; Explicit node captures ensure visibility at every level.
(list_marker_dot)         @markup.list
(list_marker_parenthesis) @markup.list
(list_marker_minus)       @markup.list
(list_marker_star)        @markup.list
(list_marker_plus)        @markup.list
