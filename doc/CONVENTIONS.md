# PKM.nvim — Note-Taking Conventions

This document defines the standard formats for note content. These conventions
are designed to reduce cognitive load during note-taking, improve human
readability, and support AI/RAG tooling that processes the notes.

These are the STABLE conventions. Implementation in syntax highlighting,
autocmds, and templates is tracked in ROADMAP.md §9.

---

## In-Text Annotations

`(text)` — standard inline parenthetical. Used for asides, clarifications, or
supplementary remarks that belong to the note's main argument.

`((text))` — author meta-comment. Content is addressed to the author or a
future reader/AI, not to the note's primary argument. Examples:
- `((Review tomorrow))`
- `((See Enderton Logic Ch.2 [bib-xxx]))`

The double-paren distinguishes meta-comments from standard textual parentheses.
Parentheses that are part of cited or transcribed content should not use the
double form. If ambiguity is unavoidable, add a short author tag:
`((AC: this is my comment))`.

---

## In-Text Citations

`[text]` — general citation marker for external sources, by abbreviated title
or identifier. Examples: `[CF/88]`, `[Stein-2003]`.

`[note[xxx]]`, `[bib[xxx]]` — PKM structured citations. These are the
canonical form produced by `:PKMInsertCitation`. Do not use other forms for
PKM-internal references; the citation engine depends on this exact pattern.

Nested: `[CF/88 [bib-003]]` — links a short external reference to its PKM
bibliography entry.

---

## Header and Body Organization

- At most one `#`-level header per note (the note title, if shown at all).
- `##` through `####` organize sections. Deeper nesting should be rare.
- Each section header should be self-explanatory without reading the preceding
  body.

---

## Rationale

These conventions are intentionally minimal. Their purpose is to reduce the
number of formatting decisions made during note-taking, and to produce notes
that are legible to AI tooling without preprocessing. Further conventions may
be added as needs emerge from daily use.
