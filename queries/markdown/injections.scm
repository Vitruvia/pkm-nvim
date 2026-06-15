;; extends

; ─── YAML frontmatter injection ────────────────────────────────────────────
; Injects the yaml parser into the frontmatter region (--- ... --- block at
; the document start). Requires the yaml parser to be installed separately —
; it is not bundled with Neovim. Silent no-op if yaml is unavailable.
((minus_metadata) @injection.content
  (#set! injection.language "yaml")
  (#set! injection.include-children))
