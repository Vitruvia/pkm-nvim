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
canonical form produced by `:PKMCite insert`. Do not use other forms for
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

## Bibliography Notes

A `bib` note records a *source*, so other notes can cite it (`[bib[xxx]]`) instead
of repeating the reference inline.

-   **The standard citation goes at the top**, as the first content after the
    frontmatter — **BibTeX preferred** (`@book{…}`, `@article{…}`), other citation
    formats allowed. This is the one part every bib note must carry precisely.
-   **Summaries and part-notes are optional**, and follow the citation. When an
    assistant adds them, they carry the assistant authorship markers (a
    `By Claude:` header with model and time), because a summary is a *reading* of
    the source, not the source itself; the citation block is not so marked.
-   A bib note is **the same source on both sides**, so it may be copied between
    vaults (the user's and an assistant's), adding the destination's authorship
    tags/markers on the copy. A user-authored bib note is not altered without the
    user's permission. (Assistant doctrine: `AGENT_PROTOCOL.md` § 10.)

`api.cite_source` writes a new bib note in exactly this shape (bibtex at the top)
and cites it in one call.

---

## Header and Body Organization

-   At most one `#`-level header per note (the note title, if shown at all).
-   `##` through `####` organize sections. Deeper nesting should be rare.
-   Each section header should be self-explanatory without reading the
    preceding body.

---

## Lists

PKM recognises several ordered-list families automatically — the same forms are
**renumbered** (`:PKMList renumber`), **highlighted**, and **wrapped**
(`:PKMList wrap`). Write a marker in one of these forms and it is treated as a list
item; write anything else and it is prose. These three behaviours agree by design,
so a human or an assistant only has to learn one rule set.

### Brazilian legal hierarchy

The five legal levels, outermost to innermost (LC 95/1998):

| Level      | Marker                                       | Examples          |
|------------|----------------------------------------------|-------------------|
| artigo     | `Art. Nº` (n ≤ 9, ordinal `º`) / `Art. N`    | `Art. 1º`, `Art. 10` |
| parágrafo  | `§ Nº` / `§ N` (same ordinal rule)           | `§ 1º`, `§ 10`    |
| inciso     | uppercase roman + ` - `                      | `I -`, `II -`     |
| alínea     | lowercase letter + `)`                       | `a)`, `b)`        |
| subalínea  | lowercase roman + `.`                        | `i.`, `ii.`       |

-   Markers are **standalone** — write `§ 1º` and `i.`, never `- § 1º` / `- i.`.
    (A `- i.` line is a plain markdown bullet whose text happens to start with
    `i.`; it is not a legal marker and is not renumbered or highlighted as one.)
-   Renumbering a selection that spans **two or more** levels renumbers the whole
    block in one pass: each level restarts under its parent (a new inciso resets
    its alíneas, a new artigo resets everything below it).
-   **Ordinal rule**: artigo and parágrafo use the `º` ordinal up to the ninth and a
    plain cardinal from the tenth on. `Parágrafo único` (the sole § of an article)
    is written out in full and left as-is.
-   The subalínea token is validated as a canonical roman numeral, so a word made of
    roman letters (`civil.`, `mil.`) is prose, not a marker.

### Other ordered lists

-   Plain **digit** lists (`1.`/`1)`) and **bullets** (`-`, `*`, `+`) are native
    markdown and are recognised by wrap and renumber.
-   The legal forms own the roman/lettered markers (inciso ` - `, alínea `)`,
    subalínea `.`), so a plain `I.` roman list is **not** recognised — use a digit
    list, or the legal form.

### Indentation and wrapping

-   **Indent each nested level by 4 spaces** for readability. Renumbering keys off
    marker *type*, not indentation, so indent is cosmetic to it — but consistent
    indent makes the hierarchy legible and is what the wrap builds on.
-   **`:PKMList wrap`** reflows to `textwidth`, keeping continuation lines at
    **marker-indent + 4** — the level indent, *never* the marker width. A short
    marker is padded to the 4-space tab stop (`1.` + 2 spaces, `-` + 3); a long
    marker (`xiii.`, `100.`) overflows only its first line, while continuation stays
    at marker-indent + 4. Same-level items stay visually aligned, and a long prefix
    never fakes a deeper level:

    ```
    i.  primeira linha do item ....................
        continuação em marker-indent + 4 .........

    xiii. primeira linha (o conteúdo transborda após o marcador)
        continuação ainda em marker-indent + 4 (Opção A)
    ```

-   **Blockquotes reflow** at a normalised prefix of `>` + 3 spaces per nesting
    level (a 4-column indent — `>   ` at depth 1, `>   >   ` at depth 2), with the
    marker repeated on every wrapped line. A bare `>` is a paragraph break; a quoted
    list/marker line (`> - x`, `> i. y`) is re-prefixed but left on one line (nested
    structure inside a quote is not reflowed).
-   Headers, tables and frontmatter are never reflowed. Fenced code is preserved —
    the ` ``` ` fences stay put and the **content** wraps per line (each line at its
    own indent, never joined).

---

## Assistant-Authored Notes

Notes an LLM assistant creates or edits follow extra conventions, so authorship
and history stay legible to both the human and future assistants. The *when* and
*why* live in `doc/AGENT_PROTOCOL.md`; the *formats* are here.

**Authorship markers** (full rules in `AGENT_PROTOCOL.md` § 7):
-   Filename marker `NNNN_<type>_By<Author>_<slug>.md` — for an assistant-created
    note in a vault **other than** the assistant's own. It is `By<Author>`, no
    hyphen (e.g. `0007_note_ByClaude_afo-audit.md`).
-   Tag `by-claude` — on every assistant-*created* note, in any vault including
    its own.
-   Comment prefix `By Claude: ` — on every comment the assistant adds to a note
    it did not author.

**Changelog block.** Every note in the assistant's own vault ends with a short
changelog the assistant maintains. Each entry names what was added, removed, or
changed, and why. When it grows long, older entries may be summarised further,
keeping the most relevant passages verbatim.

**Version/model metadata.** Each such note carries, above the body and outside the
frontmatter, its version and the model responsible (e.g. `Claude Opus 4.8`). When
several models edited different passages, name the predominant one followed by
"and others" and mark each passage's model as a metadata line or comment where it
fits best; the changelog records the model per edit. Long histories may summarise
the oldest models (e.g. `Claude Opus < 4.0 and Claude Sonnet < 3`).

**Provenance and references** (rationale in `AGENT_PROTOCOL.md` § 10, where a note
is provisional knowledge, not settled fact). Every assistant-authored note records
enough for a future reader to weigh and re-verify it:
-   **Author and date** — the authorship markers above, plus the note's creation
    date (from the frontmatter).
-   **References consulted** — each with enough to re-find *and re-date* it: a book
    or paper by **edition and publishing year**, a website by **visit date**. A
    claim drawn from a source is attributed to that source, not stated bare. A
    `## References` (or `## Sources`) section at the note's end is the usual home;
    an inline `[short [bib-003]]` citation may point into it (see § In-Text
    Citations).

**Comment placement.** Prefer the top or bottom of a section over inline. Where a
comment must sit near specific content, place it at the start or end of the
paragraph or block, not mid-sentence, so user notes stay uncluttered. (The
`((...))` meta-comment form is defined above.)

---

## Rationale

These conventions are intentionally minimal. Their purpose is to reduce the
number of formatting decisions made during note-taking, and to produce notes
that are legible to AI tooling without preprocessing. Further conventions may
be added as needs emerge from daily use.
