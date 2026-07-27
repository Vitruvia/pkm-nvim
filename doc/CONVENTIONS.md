# PKM.nvim — Note-Taking Conventions

This document defines the standard formats for note content. These conventions
are designed to reduce cognitive load during note-taking, improve human
readability, and support AI/RAG tooling that processes the notes.

These are the STABLE conventions. Their implementation in syntax highlighting,
autocmds, and templates is tracked in `doc/ROADMAP.md` (the markdown-conventions
items under Near/Distant goals).

---

## In-Text Annotations

`(text)` — standard inline parenthetical. Used for asides, clarifications, or
supplementary remarks that belong to the note's main argument.

`((text))` — author meta-comment. Content is addressed to the author or a
future reader/AI, not to the note's primary argument. Examples:
-   `((Review tomorrow))`
-   `((See Enderton Logic Ch.2 [bib-xxx]))`

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

`[Vault::note{xxx}]` — a reference to a note in **another vault**. Example:
`[Vitruvia::note{0042}]`. Vaults do not share an index, tags, views or a
citation graph, so this deliberately does not resolve: no frontmatter is
written on either side and `goto_citation` will not follow it. It is a pointer
for a human (or an assistant) to act on, not a link.

The braces are what make that guarantee structural rather than a promise. The
citation engine scans for `[%a][%w_%-]*%[[%w%-_]+%]` — a word followed by a
**square** bracket — so `note{0042}` cannot match it under any surrounding
text, whereas `[Vitruvia::note[0042]]` *would*: the scanner finds the inner
`note[0042]` regardless of the wrapper, and if the current vault happens to
hold its own note 0042 the reference silently becomes a real citation to the
wrong note. The outer `[ ]` is the same in-text wrapper every citation uses;
only the inner brackets change, and they change to say "this one does not
resolve".

---

## Header and Body Organization

-   At most one `#`-level header per note (the note title, if shown at all).
-   `##` through `####` organize sections. Deeper nesting should be rare.
-   Each section header should be self-explanatory without reading the
    preceding body.

---

## Lists

-   Ordered lists that use non-native markdown can either:
    1.  use PKM-styled markdown; or
    2.  use simple bullets like `-` followed by the prefix. E.g. `- A) <text>`.

    The user may choose any of these options differently based on their needs
    and intent for each file/note. The second option is more externally
    compatible, while the first is more readable within PKM.

---

## Rationale

These conventions are intentionally minimal. Their purpose is to reduce the
number of formatting decisions made during note-taking, and to produce notes
that are legible to AI tooling without preprocessing. Further conventions may
be added as needs emerge from daily use.
