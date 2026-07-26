# PKM.nvim — Project Roadmap for LLM Assistants

**Purpose:** The forward plan — versions, phases, goals — and nothing else.
Detail decreases as work recedes into the future; completed work is summarised in
a line pointing at `doc/CHANGELOG.md`, and is dropped entirely once nothing
pending depends on it.

For the standing rules that govern *how* a phase is executed and verified, see
`doc/PRINCIPLES.md`. For codebase architecture see `doc/ARCHITECTURE.md`; for
code rules, patterns, and environment see `doc/LLM_CONTEXT.md`.

---

## What This Project Is

PKM.nvim is an integrated note-taking and knowledge management plugin for Neovim. It is built around the author's own workflow design — not an implementation of Obsidian, Zettelkasten, or any other established PKM theory. The design is still being refined through daily use, but the current state is close to what the author wants.

The core concept is a **structured note flow**:

```
Scratchpad  →  capture ideas quickly, no friction
    ↓
Journal     →  timestamped daily entries, personal log
    ↓
Consolidated →  permanent numbered knowledge base
```

Notes are plain markdown files with YAML frontmatter. Consolidated notes carry structured citations that create bidirectional links automatically. The system is local-first, cross-platform, and Vim-native.

The note namespace is intentionally **flat and global** — all notes share a single counter, a single root, and a single citation graph. Project organisation is achieved through **views** (saved filter definitions), not through physical separation. Multi-wiki support (separate namespaces) is not a goal.

---

## Current State

**Current version:** see the top released entry in `doc/CHANGELOG.md` (canonical).
All work happens directly on `dev`; `main` holds periodic stable backups of `dev`,
not an independently maintained release line. Upcoming work is organised under
**Release Plan** below.

**Working features:**

== General ==
- ✅ Three folder types: Scratchpad, Journal, Consolidated
- ✅ Note creation with automatic numbering (`0042_note_Title.md`); numbering skips
     trashed note numbers to prevent conflicts on restore
- ✅ Note types within Consolidated: `note`, `bib` (bibliography), `agg` (aggregate/collection)
- ✅ YAML frontmatter management with templates per note type
- ✅ Bidirectional citation system — inserting a citation in A automatically adds a backlink in B
- ✅ Flexible timestamp system (`full`, `date_time`, `date_only`)
- ✅ Free-form `title` field — decoupled from filename; file renamed only via `:PKMRenameNote`
- ✅ Note promotion: scratchpad → consolidated or journal
- ✅ Note conversion between types and folders (transpose)
- ✅ Import existing files into PKM structure
- ✅ Citation cleanup (removes stale references when notes are deleted)
- ✅ Tag merging across all notes
- ✅ Telescope integration: note browser, tag picker, citation picker, tag merge
- ✅ Export utility: filter notes by tag/title/body/filename, copy to folder (`:PKMExport`)
- ✅ Statistics window (`:PKMStats`)
- ✅ Cross-platform: Windows, WSL, Linux, macOS
- ✅ Context-aware citation picker — scores by active view (+2) and shared tags (+1)
- ✅ `:PKMRenameNote` extended to journal and scratchpad

== Editing and Viewing ==
- ✅ Markdown utilities: header counter, level shift, symbol abbreviations
- ✅ Sequence renumbering: nested lists, blockquote-prefixed lists, emphasis-wrapped
     ordinals (`*N*`, `**N**`), `**N. body**` bold-line items, header families
- ✅ `:PKMConvertList` — ordered ↔ unordered list conversion with depth prompting
- ✅ `:PKMMode [on|off]` — session context toggle; activates explorer UI, pre-builds
     index, enables tree-sitter syntax highlighting on PKM notes
- ✅ `:PKMExplorer` — toggle sidebar + buffer panel as a unit
- ✅ Tree-sitter syntax highlighting (PKMMode): frontmatter folding/foldtext,
     citation highlighting (`PKMCitation`), meta-comment highlighting (`PKMMetaComment`)
- ✅ Metadata commands (buffer-only, no disk write): `:PKMSetTitle`, `:PKMAddTag`,
     `:PKMRemoveTag`

== Search ==
- ✅ Boolean filter DSL over `tag`/`title`/`text`/`filename`/`type`/`any` fields
     (AND, OR, NOT, parentheses, quoted values)
- ✅ In-memory note index with incremental invalidation (~290× faster than raw scan)
- ✅ `:PKMBrowse [expr]` — live filter-as-you-type; bare text triggers `any` predicate
- ✅ `:PKMBrowseRecent [n]` — n most recently modified notes (default 20)
- ✅ `:PKMTags` — tag picker; on selection opens browse(`tag:<x>`)
- ✅ `:PKMOrphans` — notes with no tags, no citations, and no matching view
- ✅ Filter autocomplete for `:PKMBrowse`: field prefixes, operators, `tag:<value>`,
     `type:<value>` completions

== Views ==
- ✅ Project view system — named saved filters, sidecar `views.json`, full CRUD
- ✅ Subproject hierarchy — `{parent, filter}` entries composing AND chains
- ✅ `:PKMViewNew` — unified creation (simple view or subproject)
- ✅ `:PKMViewUpdate` — action picker: edit filter / rename / reparent
- ✅ `:PKMViewLast` — reopen last activated view (session-scoped)
- ✅ `:PKMViewSidebar` — two-mode persistent sidebar (overview + detail) with
     50-entry navigation history, `<C-t>` type filter, `<C-s>` no-op,
     `<C-v>` vertical split, `/` scoped search, `?` help float
- ✅ `:PKMViews` — tree-structured picker over all views (parent-child hierarchy)
- ✅ Scoped note search within sidebar (`/`) and views tree (`<C-f>`)
- ✅ `views.get_last_view()` — active view context for consumers
- ✅ `:PKMExportView [name]` — export named view's notes, skips filter form
- ✅ `:PKMBuffers` — persistent bottom buffer-list panel with auto-refresh
- ✅ Per-tabpage state for both sidebar (`views.lua`) and buffer panel (`ui.lua`)

== Trash ==
- ✅ `:PKMDeleteNote` — soft-delete to `.pkm-trash/` (when `trash.enabled = true`);
     backlinks preserved for clean restoration
- ✅ `:PKMRestoreNote` — picker over trash manifest; moves note back, re-indexes
- ✅ `:PKMEmptyTrash` — permanently deletes all trash and strips backlinks
- ✅ Auto-purge via `trash.max_age_days` (default 60; 0 = disable)
- ✅ Trash manifest records `filename`, `original_path`, `title`, `deleted_at`,
     `deleted_timestamp`

**Known limitations:**
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support

**Metadata notes:**
- The `status` field has been **removed** from frontmatter. Do not reintroduce it.
- Citation structure: `cites: {notes: [], bib: []}` and `cited_by: {notes: [], bib: []}`.
- The `title` field is free-form and never overwritten by the system after creation.
- Trash is isolated to `.pkm-trash/` inside the PKM root (not OS trash).
- Note numbers skip trashed entries; gaps are intentional (numbers are identifiers, not labels).

---


## Architecture Reference

Codebase layout, per-module responsibilities, and configuration shape live in
`doc/ARCHITECTURE.md` (single owner). `config.lua` is the canonical source of
configuration defaults.

---

## Development Roadmap

### Active

See "Current State" above.

---

### Versioning Policy

The project sits in the 1.x range but is **pre-release**: there are no external
API consumers and the only user is the author. Versioning follows a constrained
form of [Semantic Versioning](https://semver.org/):

- **MAJOR is frozen at `1`** for the whole pre-release period. `2.0.0` is
  reserved for the first public-stability release and is not created during
  ordinary development.
- **MINOR (`1.Y.0`)** — introduces at least one backward-compatible,
  user-facing feature. May also carry bug fixes and refactors.
- **PATCH (`1.y.Z`)** — bug fixes, performance work, and internal refactors
  only. No new user-facing features.
- **"Backward-compatible"** is judged against the author's own configuration and
  workflow, since there are no other consumers. A change that requires the
  author to edit their config is still a MINOR during this phase (never a
  MAJOR), but must be recorded under a **Config changes** note in the CHANGELOG.
- **Phases are the unit of implementation and review** within a version. A phase
  edits each file in **exactly one pass** (see Release Plan operating
  principles). A version may contain one phase or several.
- **Tags** (`git tag -a vX.Y.Z`) are applied only after every phase of a version
  has landed and passed the verification protocol — never mid-version.

---

### Release Plan

*Work is partitioned into the versions below. Discussion-only items live under
**Design Questions**; long-horizon items under **Distant goals**. Shipped versions
are summarised compactly — see `doc/CHANGELOG.md` for their full detail.*

```
v1.5.7 … v1.6.1   ✅ shipped — see doc/CHANGELOG.md
v1.8.0  MINOR  Bulk metadata operations  ✅ released 25/7/2026, tagged
        Nine phases; detail in doc/CHANGELOG.md. This release also carries the
        work planned as v1.6.2 (index build) and v1.7.0 Ph1–Ph2 (deep export,
        relative note) — those two numbers stayed planning labels and have no
        tag of their own.

v1.8.1  PATCH  Defects from the v1.8.0 smoke pass  ✅ released 26/7/2026, tagged
        View membership offering the wrong views, confirmation on every
        removal, and the undo cursor — reproduced before it was touched, which
        is what ended a bug that had been "fixed" three times.

v1.9.0  MINOR  Views from where you already are  ✅ released 26/7/2026, tagged
        :PKMView add|remove <name> on the current note, and a note created
        already inside a view — plus the window placement the second one
        turned out to need.

v1.10.0 MINOR  Header navigation                            (next)
        Ph1 any-level header jumps   (was v1.7.0 Ph3)
```

**Ordering beyond that, decided by the author.** Everything that may *create*
commands comes first — above all the operations that change internal state
(citations, frontmatter, the view registry, the index). The reason is explicit:
an assistant with no command for such an operation edits a note "from the
outside" and breaks the system, so the command has to exist before the API that
would call it. Formatting and syntax highlighting are **not** prerequisites —
an assistant does formatting unaided. Only then comes *Command clearup*
(deciding which registrations survive as typed commands), and only after that
`pkm.api` (Near goals 4). Every listed bugfix lands before `pkm.api`; they are
small, and leaving them under a new public surface is how they become
permanent.

Dependency summary: v1.9.0 follows v1.8.1, because its Phase 1 calls the
`view_flow` that v1.8.1 Phase 1 repairs — shipping it first would build a new
command on the defect. v1.10.0 floats: it touches `markdown.lua` and nothing
else, and may be reordered freely.

---

#### Standing rules — moved out

The Operating Principles, the standing bug-prevention design rules and the
Standing Verification Protocol now live in **`doc/PRINCIPLES.md`**. They apply to
every version and phase and do not change as the plan does, which is why they no
longer sit in a document meant to shrink as work completes. Read that file before
planning or executing a phase.

---

#### Shipped — everything up to v1.9.0

v1.6.1 and v1.6.2: correctness batch, `:PKMViews` open latency, index build cost.
v1.7.0 Ph1–Ph2: deep export, and the relative note — Ph2 shipped inside v1.8.0
Ph1, where the tag engine it seeds from was written. v1.8.0: the bulk-operation
stack in nine phases, released and tagged 25/7/2026. v1.8.1: the three defects
its smoke pass found, released and tagged 26/7/2026. v1.9.0: views reached from
where you already are, released and tagged 26/7/2026. What each changed is in
`doc/CHANGELOG.md`.


Their decisions still constrain pending work, and are the only reason this
section survives:

-   **Deep export runs on the picker selection**, not on every filter match, and
    its two depths are a per-path budget counted from the seeds, mixable in any
    order.
-   **`picker.select_live` is the panel shape** any further bulk operation
    reuses: the prompt *is* the operation, rows recompute per keystroke, the
    preview shows the result. There is no form and no separate result screen.
-   **`picker.choose` is the one-of-N menu**, for a list the caller has already
    ranked. A flow that reaches `vim.ui.select` directly puts a Telescope user
    on the command line halfway through a Telescope flow.
-   **`actions.list()` returns `{ id, label, run }`** — the enumeration that will
    let `pkm.api` discover bulk operations instead of hard-coding them.
-   **`ctx.view` orders, it never decides.** Knowing where a selection came from
    says nothing about what the operation should act on; treating it as an
    answer is what made "add to another view" unreachable from inside one.
-   **Nothing the plugin does may enter the user's undo block.** A buffer
    mutation during the write cycle drags `u` off the edit — Neovim recomputes
    the cursor from the changed region — and no cursor handling repairs it.
    A mutation from a scheduled callback also leaves the block *open* and
    absorbs whatever the user types next; force the break with
    `let &undolevels = &undolevels` (setting it to `-1` discards the history).
    Separately, the post-write rewrite of the file must happen on **every**
    save, or Neovim's record of it goes stale and a later `:w` stops with W11.
-   **`last_updated_on` has no consumer.** Recency is the filesystem mtime the
    index stores; read `entry.mtime`. It must not be trusted as a record of
    human editing — Drive sync, restores and checkouts all push mtime forward.
-   **A key that belongs to "the view surfaces" goes through one helper**, and
    is wired at all five in the same edit. `<C-a>` took three attempts because
    each surface was wired separately, and a chord's prefix must itself be a
    complete mapping or the bare key does nothing.
-   **`create_new_note` owns the window guard**, not its callers: panels set
    `winfixbuf`, so opening a buffer from one is E1513. `utils.focus_editing_win`
    is the single search for a window that may hold a note.

**v1.6.2 and v1.7.0 have no tag.** Their work reached the user inside the v1.8.0
release and the CHANGELOG entry for v1.8.0 records that; the numbers stayed
planning labels. Header navigation, the third phase v1.7.0 never got, is v1.10.0
below.

---

#### v1.10.0 (MINOR) — header navigation

*Was v1.7.0 Ph3, which never shipped; the rest of v1.7.0 went out inside v1.8.0.
It is self-contained and blocks nothing, which is why it sits after the fixes
and the view work rather than before them.*

**Phase 1 — any-level header navigation.**

| File | Single-pass changes |
|---|---|
| `markdown.lua` | Add **any-level** header navigation (jump to next/prev ATX heading regardless of level) via a pure `find_heading_target(lines, cursor, opts) → lnum?`. Neovim already provides **same-level** header motion natively, so PKM adds only the any-level complement; document the native integration. Update the module Public-API header and LuaDoc. *(Optional bundling: Distant goals 1.8's "global next_header" also lives in `markdown.lua` and could ride this same pass if promoted.)* |
| `commands.lua` | `:PKMNextHeader`-family navigation commands. |
| `keymaps.lua` | Wire navigation keymaps when set. |
| `config.lua` | Navigation keymap defaults — consistent with the native same-level motion and existing markdown keymaps (default `false`). |
| docs | `CHANGELOG` (Added). Record the PKM↔Neovim native-motion integration and note that a previously-created same-level command was dropped in favour of the native one. Promote the "different/any-level header" bullet of Distant goals 1.2 into completed scope; restate that list-component and block navigation remain deferred pending the markdown conventions. |

Verification: `test/test_v1100_p1.lua` runs `find_heading_target` over a
mixed-level fixture and asserts next/prev targets at boundaries (first/last
heading; no heading → nil). Smoke: navigate a real note's headings.

Invariants: current Neovim API only; pure targeting function; no global state.

Commit:

```
feat: any-level header navigation

- markdown: any-level header jumps via a pure find_heading_target (ATX only);
  document integration with Neovim's native same-level motion
- commands/keymaps/config: opt-in heading-navigation commands and keymaps
- test: heading targeting over fixtures, including boundaries
- docs: changelog; DA 1.2 (any-level header) promoted; native-motion note
```

---

### Design Questions (discussion-only — not yet planned)

*Reserved space for ideas the author wants tracked as ongoing frameworks rather
than scheduled work. No implementation until explicitly promoted. These three
are related: all concern how notes describe and relate to one another.*

Only decision 4 is open; decisions 1–3 are resolved and summarised below.

1. **Note relationship protocol** — resolved: tag-set relatedness (Jaccard/
   overlap over tag sets) over rigid parent/child nomenclature, which is
   ill-defined here since notes cite freely and a "parent" can be cited by
   a note its "child" cites. Feeds directly into the relevance-ranking
   ideas in Distant goals 9; the v1.7.0 "relative note" feature already
   embodies this view of relationship at creation time.

2. **A note type for describing other notes** — resolved: no new
   frontmatter `type` (a major, hard-to-reverse change for what a naming
   convention solves just as well). Use `_meta` subviews instead — see
   `doc/CONVENTIONS.md` § Views: Meta/Guide Notes for the convention and the
   underscore-first sort order that supports it.

3. **Exportation improvements** — resolved, consistent with decision 2: the
   AI-context-protocol case (shipping a file that tells an AI/LLM how to
   interpret a set of notes) is just another `_meta` subview; exporting a
   view already exports its subviews, so no new mechanism is needed there.
   The default export flow should let the user choose between "export
   current note," "export current view," or a composed export (arbitrary
   views/tags/titles) — tracked as the still-open half of this item under
   Distant goals § Exportation.

4.  **Command clearup:** several commands are residual, while others exist
    mainly to be called as part of other commands. As of now, typing `:PKM` and
    then pressing `<TAB>` for autocomplete is no longer helpful, since the user
    is shown an enormous list of commands (many which are alike). A discussion
    is necessary to determine which commands should be preserved as "typed"
    commands, which should be keymapped, and which should cease to be commands
    (and remain only as internal functions to be used by other commands). Adding
    optional arguments to some commands may be useful as a way to allow advanced
    users to have a direct access to some commands that are usually provided as options.
    Common and safe options should be used as defaults for a multimodal command.
    Cases with multile common options, may be examined to see if any such options
    should remain as individual commands. Commands that create similar panels
    should be consolidated into one multifunctional panel, if possible, as long
    as it does not create a strong dependency on an unstable or not guaranteed
    external tool. But even in this case, we may consider fallbacks that will
    simply show options for what type of panel should be opened (unless the user
    is constantly opening such panels, in which case selecting options will become
    a drag).

    **Partially resolved (v1.8.0 Ph4) — the policy every phase now follows:**

    a.  **A typed command is for what the user invokes directly.** Nothing gets a
        new `:PKM*` name when it fits as an argument to an existing command or as
        an action in a panel. `:PKMExportDeep` (removed) and the batch tag modes
        (moved to `<C-a>`) are the two worked examples.
    b.  **Every capability lands in three layers:** a pure or read-only core with
        no UI; a row in the `actions.lua` registry when it acts on a set of notes;
        and at most one more argument on an existing command. The UI is always the
        thinnest layer.
    c.  **Choosing notes belongs to the navigation panels**, not to a command's
        own scope prompt. A command that needs a selection and has none is the
        exception, not the design.
    d.  **The interactive form and the programmatic form are the same command.**
        Bare, it is the friendly path (`:PKMTags` → the tag browser); with
        arguments, it is deterministic and script-callable (`:PKMTags rename draf
        draft`) — one entry in `:PKM<TAB>` either way. Destructive operations keep
        their confirmation in both forms.

    Still open: which of the 47 registrations are residual, which should become
    keymaps only, and which should stop being commands. That pass belongs with
    the `pkm.api` work in Near goals 4, since the two answer the same question
    from opposite ends.

---

### Near goals (short-term to mid-term)
1.  **Markdown improvements (near):**
    1.  the next_header command currently only works when the cursor is above a
       header. If used this way, it will create a header numbered as the
       current + 1. Create a new "global' next_header command which creates a
       new header based on the last header number (highest numbered /
       last-in-order) of the same level. It creates this header after every
       other header of that same level and below (including plain text), but
       before any header of a higher level (if none exist, then this will be the
       last line in the file), then moves the cursor to the newly
       created header (that is, it will create `## header-(n+1)` whenever the
       cursor is at `## header-m`, for any `m <= n`. *(Lives in `markdown.lua`;
       could be bundled with the v1.7.0 header-navigation pass if promoted.)*;
    2.  Conventions (near): establish our own conventions for markdown, in
        order to provide a guideline for consistent and high-quality
        note-taking, reviewing, and editing, as well as LLM/AI collaboration.
        Some of these conventions may drive
        syntax highlighting and formatting, while others are simply meant to guide the
        user in using consistent notation and terminology. The written
        specification will live in a new `doc/CONVENTIONS.md` (guidance, not yet
        a syntax contract). Examples (non-exhaustive):
        -   spacing: use github's guidelines, which suggest using two spaces after number
            prefixes and 3 spaces after simple symbol prefixes to reach a 4
            space indentation. As for symbols 4 character-large or longer
            and numbers 3 character-large or longer, we should allow the first line
            to sit wherever it lands after the current level indentation + prefix + a space,
            but any other line should start at the current level indentation. This will
            need an adjustment to the wrapping commands, since they currently align all
            text with the first line.  

            ```
            -- Current (undesired), assume the following is a first-level prefix.

            11111111111. first line starts here...............................
                         and all other lines wrap here.

            -- Intended result, assume the following is a first-level prefix.

            11111111111. first line starts here...............................
                and all other lines wrap here.
            ```

            If prefixes are so long that would
            make identation impossible without transgressing the margins (e.g.
            80 characters), then special notations are ensued (such as power
            notations like 10^6 and so on), or the user may opt for prefixes
            that can fit more values in a smaller space (like hexadecimals, or
            number + characters e.g. `a` - `z`, then `aa` - `zz`, and so on).
            This requires additional conventions, evaluations of autowrappers
            and syntax highlighting, and should not break the current working
            features (see best practices from manuals and guidelines on formatting,
            text editing, typesetting, and diagraming).
        -   extend recognized list prefixes to encompass those used in Brazilian
            legal texts, that is "Art. nº." (for "artigo" with n equal or below
            9), "Art. n." (for n above 9), "§ n" (for "parágrafo", following
            the same numbering rules from "artigo", upper case roman numerals
            followed by a "-" separator for "incisos", lowercase letters
            followed by a ")" separator for "alíneas", and lowercase roman
            numerals followed by a "." separator for "subalíneas". This recognition
            implies not only syntax highlighting, but all list functions will
            work with text disposed in this manner.
            -- Current (undesired)

            11111111111. first line starts here...............................
                         and all other lines wrap here.
        -   Conventions for notations when juxtaposing equivalent names like
            `AI/LLM` or `não-exaustivo/não-taxativo`.

2. **Navigation (near):**
    1.  active window: add keymapped commands to allow navigating
        between:
        -   same level list component;
        -   jump to the end or beginning of a list
        -   different level headers (same level headers is already implemented
            by standard neovim; **any-level** header jump is implemented in
            v1.7.0);
        -   diferent level list components;
        -   blocks of the same type (code blocks, lists, citation);
    2.  bookmarks: extract the headers to create an indexed list of topics,
    subtopics, and so on, which can be accessed via a command (the command will
    open a navigation panel for the note in the current active window. This panel
    will allow the user to navigate quickly between headers, and can also be used
    to copy the index).
    3.  Sidebar: There should be a keymap to do so within
        the sidebar and one to do the same without leaving the curren active
        window. The bookmark bar should show the index with
        collapsable/expandable levels, but also allow quick navigation to the
        view system. There should be no autoswitch (the sidebar only shows the
        "bookmark" bar if the user wants it to, and only switches back to the
        view navigation bar if the user wants it to). Important: headers within
        container blocks, like code blocks, should not be extracted into the index.
        Our system should be smart enough to understand our textual structures, and
        we should use conventions to instruct users and AI on how to understand them as well
        (e.g. code blocks are for display, quotation symbols are for quotations, so
        nothing within these blocks is part of the main text's structure, since we
        may want to insert a structured text as part of a block or quotation).

3.  **Functionality (near):**
    1.  Expand our custom syntax highlighting and commands to all
       files outside PKM. Many commands, like `:PKMRenameNote` already
       work outside our system, all we need to do is create a default list
       of commands that we want to always work and make sure they do. Customization
       can be left for a distant future (together with other user customization
       options). We also need to make syntax highlighting work for all markdown
       files (customization and toggling options are deferred to the user
       customization step, to be implemented sometime in the future).
    2.  A custom autowrap that will correctly work with the elements of a PKM
        note, like YAML frontmatter, code blocks, headers (no autowrapping
        headers with text that imediately precedes or follows them), tables, lists
        with custom prefixes, etc.;
    3.  A way to batch add/modify tags. *(Promoted: engine done in v1.8.0 Ph1,
        UI scheduled as v1.8.0 Ph2.)*
    4.  A way to "add" or "remove" file into a view (tag only). *(Promoted:
        scheduled as v1.8.0 Ph3.)* This feature is
    meant to grab all sets of tags (separated by an OR) that a view accepts. If
    only one is available, it is added to the file (no duplicates allowed). If
    more than one are available, the user is shown a panel with the options.
    e.g: if a view has a filter: "tag:a AND tag:b OR tag:c", then the two
    tag sets are {1: [a, b], 2: [c]} (chosing the first set will add both tags
    a and b, because they are part of the same set). Removing a note from a file
    from a view, on the other hand, removes either all tags or the minimal
    sets, presenting choices if more than one is available. e.g.: in the
    previous example, the user would have two initial choices: {1: "remove all (this
    removes a, b, and c)", 2: "minimal" (presents choices: {1: [a, c], 2: [b, c]}).
    [b,c]}

        
4.  **`pkm.api` — a programmatic surface for LLM assistants and advanced users.**
    The author intends to drive the vault from an assistant (Claude) running in a
    terminal or through Neovim's command line: create notes, retag in bulk, query
    views, export a set — without a human at a picker. That needs a boundary the
    plugin does not have yet, and the point of drawing it is as much about what
    stays *out* of `:PKM<TAB>` as about what goes in.

    Shape (not yet designed in detail, but the constraints are fixed):

    -   **`require('pkm.api')` returns data and never opens UI.** Headless-safe by
        construction, so every function is callable from
        `nvim --headless -c "lua ..."` and testable without a screen.
    -   **It wraps existing cores, it does not reimplement them.** The pure and
        read-only layers already exist — `tags.plan`/`preview`/`apply`,
        `filter.parse`/`eval`, `index.get_all`, `export.collect_deep`,
        `views.match_all`, `actions.list` — and the API is the stable naming over
        them. Commands and panels become the other, equally thin, wrapper.
    -   **Bulk operations are enumerable.** `actions.list()` (v1.8.0 Ph4) already
        returns `{ id, label, run }`, which is what lets an assistant discover the
        available operations instead of hard-coding them.
    -   **Writes stay auditable.** Anything that touches disk reports what it
        changed (as `tags.apply` does) and keeps `index.invalidate` discipline;
        confirmation belongs to the *interactive* wrapper, so the API must never
        silently acquire a prompt.
    -   **No new typed commands.** The API is reached from Lua; at most one
        dispatcher would ever be added, and only if a real need appears.

    Sequencing: it comes after the bulk-operation phases it would expose (v1.8.0
    Ph5–Ph6), and it carries the still-open half of *Command clearup* (Design
    Question 4) — deciding which of the 47 registrations survive as typed
    commands once a programmatic path exists.

5.  **Misc** (currently set to be done in the active development's Phase X,
    meaning the LLM assistant should decide when it is best to implement them):
    -   Partially fixed: now I get prompted (have to answer with y or n)
        instead of having to type `w!`. This is an acceptable solution, unless
        the prompt can be removed (automatically accepted) without risk. Being
        cited by another note while open on a buffer will sometimes create the
        need for a forced save, even if nothing else has been changed (check if
        this is mentioned already in some existing version/phase).
    
    -   Fix now: bugfix - syntax highlighting recognizes numbers that start any line as
        a list prefix, as long as it is in the correct indentation level and
        order (e.g. `2.` will only be recognized if there is a previous item
        with number `1.`). The issue is that it does not differentiate lines
        that are wrapped from real new lines. so a text such as `1. <text
        ocupying the first line> 1. ((the 1. is part of the wrapped text,
        starting the next line) <remainder of text> will appear as `1. <list
        item> \n \indentation ((e.g. four spaces)) 1. <sublist item>. A real
        case where this happened was this text `1.  Observar as duas questões
        discursivas, dispostas no edital [note[0205] - 1. Da Prova Discursiva].`,
        which happened to wrap just at the second `1.`, which became highlighted.
        But this `1.` is not a new list item, it is a pointer to `1. Da Prova Discursiva`
        in `note[0205]`. Removing hard-wrapping is an option, but probably not
        a good one, so evaluate alternatives.

### Distant goals (mid-term to long-term)

1.  **Markdown improvements (distant):**
    1.  Conventions (distant) 
        -   evaluate cost-benefit of extending possible list prefix to any
            alphanumeric symbol + a separator from a standard separators list
            (e.g. `-`, `.`, `)`, `:`). Consider the same for symbol sequences.
            This would allow things such as `text:`, `I -`, `I)`, and many
            others to be highlighted and to provide a basis for text wrapping
            and indentation. add a `-` prefix followed by a space and the
            custom prefix, (e.g. `-` § 1º.).This workaround requires the
            indentation conventions and autowrap improvements previously
            described, since otherwise these prefixes will make text wrap
            beyond the defaults of their current level.
        -   displays: 
            -   support for markdown, tsv, and csv tables.
            -   support for space or multispace separated tables/displays.
            -   conventions for separators; 
            -   consider allowing text wrapping inside table cells (this would
                require an adjustment in neovim's autowrap inside tables OR a
                custom autowrap for PKM (leaving the native autowrap
                untouched)). A similar autowrap should also be considered for
                text disposed in two or more columns.
                Example, suppose a user is writing a text that he clearly separated
                in two columns, using spaces or tabs as a delimiter, then the
                wrapping should occur as:

                ```

                -- WRONG --
                - XLIII       Crimes de tortura, tráfico ilícito de entorpecentes e afins,
                terrorismo e crimes hediondos

                -- CORRECT --
                - XLIII       Crimes de tortura, tráfico ilícito de entorpecentes e afins,
                              terrorismo e crimes hediondos

                ```

2. **`lua/pkm/preview.lua`** — Browser-based live preview: Markdown + LaTeX (MathJax),
  WebSocket live updates on save, cross-platform browser opening, terminal fallback
  (glow/mdcat).

3. **Persistent index** — Serialize the in-memory index to disk (msgpack or
   JSON) with mtime-based incremental updates on startup. Needed only if
   startup scan time becomes unacceptable at very large corpus sizes (likely
   >50k notes). The current build cost is ~0.25 ms/note; at 500 notes
   (realistic current scale) that is ~125 ms, which is imperceptible. Run
   `bench.baseline()` on the real corpus before implementing this.

4.  **`_match_cache` in views.lua** — Cache matched path arrays alongside
    filter trees. Makes repeated `match_all` calls O(1) until invalidation.
    **Not adopted by v1.6.1 Ph3**, which reached a ~5–9× overview speedup
    without introducing invalidatable state (`count_many` + precomputed sort
    keys). A cache would now only pay off for repeated *path* queries —
    `:PKMOrphans` and successive detail opens of the same view. Revisit at ~5k
    notes or ~200+ views with observed latency, and only after the cheaper
    `:PKMOrphans` fix in CHANGELOG § Known Bugs (skip the per-view sort).

5.  **Note review queue** — Select and track notes intended for review. May
    include organizers, separators, or filter interactions for priority/subject
    categorisation.

6.  **Explorer UI customisation:**
    1.  positions and width of each panel; auto-on/off triggers by directory,
        CWD, or buffer type; other layout options users may need. 
    2.  Improved help panel with main keymaps for PKM (the current panel is
        sidebar only). This panel would have to update depending on how the
        user customizes their config, so this change is related to "Explorer UI
        Customisation".
    3.  Sidebar options
        -   always on;
        -   always off;
        -   on when a note is opened, then remain on;
        -   on when entering the home notes folder (when it becomes the neovim's
        working folder), then remain on;
        -   off when any note is opened (this is a negative toggle, cumulative with
        the positive toggles, and it takes
        precedence over the positive toggles, e.g. if it is always on + off when any note
        is opened, then it is always on, but as soon as a note is opened, it is turned off;
        it becomes on again if no notes are opened or if the user toggles it on).
    4. Buffer panel options:
        -   always on;
        -   always off;
        -   on when a note is opened, then remain on;
        -   on when entering the home notes folder (when it becomes the neovim's
        working folder), then remain on;
        -   on when a note is opened, but off again when all notes are closed.
    5.  `:PKMExplore` will use its own options for the sidebar and buffer
        panel. Whatever is toggled later (explore or buffer/sidebar) takes
        precedence. User manual toggles always take precedence over anything
        else.
7. **Syntax highlighting (distant):**
    1. Extended list prefixes recognition. 

8.  **System customization:**
    1.  Turn on/off our markdown features, to allow the user to use external
       markdown plugins if they prefer.
    2.  UI customization (either in the telescope-based or in the possible but
       not guaranteed "native" UI).
        -   sidebar and buffer bar positioning.
    3.  PKMMode: 
        -   when to activate or not; 
        -   which functions, commands, and highlighting to propagate generally (outside the pkm system);
        -   root and note folders renaming;
        -   note type renaming;
        -   new note type creation per user need;

9.  **Improved search/browse and citations:** 
    1.  improve the context detection algorithm, but only if it does not
        significantly impair performance, this context detection should enable
        notes to be ordered due to relevance both on search and on the panels
        (buffer and sidebar). E.g. notes related to the view, notes with
        similar citations, recently modified notes, recently opened notes. We
        should define a rationale for the criteria priority and consider
        algorithms used in popular tools to rank the relevance of files, urls,
        etc (like google's). This should make note navigation much more
        intuitive both during edition and when starting a new session.
        (See Design Questions: tag-set relatedness is a candidate signal.)
        Criteria examples: `same subview > same view > same tags, but not
        the same view > no tag/view relationship`; `for files that meet
        the same criteria for subview, view, etc. Those that share the exact
        same tags take precedence over those that have different tags` (these
        are just examples and do not need to be followed. Other interesting
        relationships might include files that were created in a similar period,
        files that were last-modified in a similar period, files that cite
        or are cited by the same files, etc. Textual matches may also be relevant,
        but more complex to implement. The final algorithm should balance all
        this criteria in a rational and useful manner. Inspiration from working
        software such as obsidian, google, and social network may be helpful).

        Example 1:
        `0035_bib_Constituição_da_República_Federativa_do_Brasil_1988.md` was
        not tagged as "direito-constitucional", so it was not captured as a
        contextual note when trying to cite it in other notes within the
        "Direito Constitucional" view. However, its name already suggest it is
        related to the subject, and it is cited by many other notes in the
        "Direito Constitucional" view or with the "direito-constitucional" tag. 

        We should analyze if there is a reasonable way to detect this, and
        perhaps even to rank what appears first depending on a combination of
        context, last opened/edited, frequently opened together, etc., and
        implement whatever is reasonable within our capabilities and
        neovim's/lua constraints, also keeping in mind that maintenability,
        compatibility with future vim's version, compatibility with
        pre-existing and future PKM features, and performance are all very
        important. This is a UX feature and it is important, however, discard
        part of or all of it if it cannot be implemented while also protecting
        or enhancing the points listed at the end of the previous sentence.

        Example 2: notes in the sidebar should be ordered according to
        relevance (e.g. last opened within that view/subview).

    2.  Smart search without losing the current textual match protocol, which
        is correct (withou becoming completely fuzzy, since that makes
        irrelevant text match). Example: typing "remedios" should be able to
        detect "remédios" and typing "remedios constitucionais" should be albe
        to detect "remédios-constitucionais". If there is an exact match,
        however, it should rank above these partial or smart matches.

10.  **Note sync:** Currently, I use Github to store my notes (in a private
     repo) as a means to preserve them and to allow note-taking in multiple
     devices. We should, at some point, create a note syncing within PKM, which
     may allow one or multiple options for a repository (including github
     itself). The sync needs to allow for privacy (e.g. at least one option of
     a private storage, as well as an option of local-only notes. If syncing
     downloads notes in another computer, e.g. Github or Google Drive, there
     should be an easy way to delete the notes locally after the work is done).
     The syncing should be robust and tolerate desynchronized edits without
     issues (using something like a diff to converge modifications). The
     syncing should be fast (no slow syncing like Evernote).

11.     **Note versions and undo:** Currenly, modifying a note and saving it will
    make the previous note disappear (unless the user wants to restore notes
    synced to Github by reverting a "version", but that is cumbersome and
    faulty). Ideally, we should be able to store some versions of the note,
    allowing "undo" even after a note is saved and the program is closed. This
    need to be evalutated in terms of performance and storage costs.

12. **Navigation:**
    1. Improved motion inside tables (quickly move to next cell, column or
       line, including if it is not filled yet. This should make editing
       easier);

---

### Potential but not guaranteed goals (do not design toward)

-   **Alternative PKM modes:** Obsidian-style backlink graph, Zettelkasten
    ID-based linking, etc. Would be selectable configurations, not the default.

-   **Image and visualization support:** embedded images, Mermaid diagram
    support in preview, inline rendering (kitty/iTerm2 protocols).

-   **`:PKMViewStats`** — table of all views with note counts and subproject
    depth. Implementation: iterate `views.list()`, call `match_all()` for each,
    format as notification or float.

-   **Metadata system review (in-file vs. sidecar).** Recorded for future
    reconsideration only. Decision gate: revisit ONLY IF, after (1) the
    modified-buffer write-through fix and (2) frontmatter folding/conceal, the
    in-file approach remains unacceptable in daily use.

-   **PKM UI** - a UI developed for PKM, not dependent on telescope, which will
    allow users to chose which UI to use and allow the development of all
    commands that currently use telescope's UI in a more flexible manner.
    Telescope's UI will not be replaced, nor will telescope based search if we
    are still using it in any part of the main program, but users will be able
    to choose which to enable and, where adequate, they may also be activated
    together and complementarily.

-   **Alternative diagram and imaging methods** — ASCII/text-based art and
    other portable methods for enhancing notes without external image files.
    Any approach must be examined for human readability, AI/machine
    readability, and portability before implementation.

-   **Insertable folds**: a character or character combination to mark
    beginning and ending of folds in any file. These should only be implemented
    if they do not generate heavy performance costs. Otherwise, evaluate if a
    partial implementation can be done without heavy performance costs. If
    neither are possible, skip this feature and note in the roadmap why we
    decided not to implement it yet, and what needs to change for use to
    consider it again. The full spec should:
        -   enable any line or collection of lines marked with the "fold-start"
            and "fold-end" characters to be concealed;
        -   detect if a folding starts in a header and includes all content
            encompassed by it, and if so, show the header's name when folded,
            using a notation or highlighting that makes it clear that it is a
            header and preserving the header title/name.
        -   detect if a folding starts and ends (wraps) a code block, citation
            block, list, or table and mark it as such when folded. If more than
            one of such block exists, a counter should differentiate them (e.g.
            "code block 1, 2...").
        -   detect whether the folding markers wrap around plain text
            (including inline code blocks, bold or italic markers, etc.), but
            not headers, code-blocks, or other existing native "wrappers", and
            identify as just text.
        -   preserve performance even if several folds exist in the same file.
        -   a partial implementation allows concealment only of headers and the
            content they wrap around.
        -   advanced: also include autoconceal options (default: {headers: [on;
            level 2; autofold off], frontmatter [on; level 1; auotfold on]};
            meaning only level 2 headers are wrapped in concealers by default
            but do not start folded. The configs for frontmatter are meant to
            reflect our current usage, in which frontmatter is always wrapped
            with "fold markers" and starts folded by default). Keep in mind
            that the autoconceal option notation was just a "pseudo notation"
            made me for illustration purposes.

-   **Exportation:**
    1. Compatibility export options: 
        -   pkm (standard): export the file in the pkm plugin format. The system
        already expects users to use this format;
        -   common markdown format. This requires reformatting, for example, every
       list prefix not present in the common markdown protocols will be
       standardized (e.g. a legal text containing "Art. 1º." as an item and "§
       1º." as a subitem will have those prefixes changed to "1." and "1.1."
       (or "1.", if "1.1." is not generally compatible) with the correct
       indentation (note that the correct indentation may be present in the
       original note, so only the prefix needs to change). Similar operations
       will be done for every PKM or individual user convention that is not
       supported by the main markdown protocols (we can use CommonMark as a
       default and add options for other usual markdown protocols);
       -    Obsidian: export in a format compatible with Obsidian. This means
       the frontmatter will probably be extracted and turned into something
       that can be passed to Obsidian as metadata. Reformatting will
       also be necessary as to make the markdown and other notation compatible
       with the Obsidian software.

---

### Unlikely goals, nongoals, or out of consideration

- **Multi-wiki** — multiple independent namespaces with separate counters. Superseded
  by the view system. The single global counter guarantees uniqueness; do not break it.
- **Non-flat citations** — hierarchical structure beyond `notes`/`bib`. Undecided;
  current structure may be permanently sufficient.

---

## LLM Assistant Rules, Patterns & Environment

Non-negotiable rules, established code patterns, environment details, debugging
commands, and git conventions are owned by `doc/LLM_CONTEXT.md` — consult it
alongside this document. They are intentionally not restated here, since this
section previously drifted out of sync with its counterpart in `LLM_CONTEXT.md`
(missing rules on one side, missing environment/config detail on the other).

Module structure (file-level header block, section separators, LuaDoc
annotations) is a coding standard owned by the project instructions —
see Coding Standards § Module Structure there.

---

## Neovim Version Compatibility Watch List

Audited 2026-06-21 against Neovim 0.12 (stable, 0.12.3) while still running
0.11.3. Full breaking-changes/deprecations list reviewed; no code changes
required for the 0.11 → 0.12 upgrade itself. Recorded here so future upgrades
don't need to re-derive this from scratch.

**Confirmed safe (re-verified against 0.12 `news.txt`, no action needed):**
- `vim.treesitter.get_parser()` now returns `nil` on failure instead of
  throwing. All call sites in `syntax.lua` already wrap in `pcall` and check
  for `nil`, handling both behaviors. No regression.
- `UndoPost` still does not exist as an autocmd event in 0.12. The existing
  rule ("never register `UndoPost`") remains correct — re-check this line
  specifically at the next major version audit, since it's the one rule most
  likely to silently become obsolete (i.e., wrong, not broken) if Neovim ever
  adds the event.

**Low-priority migration (deprecated, not removed — no urgency):**
- `nvim_create_autocmd()`'s `buffer` key is deprecated in 0.12 in favor of
  `buf` (old key still accepted). Used in `syntax.lua` and `views.lua` at
  minimum. Safe to leave as-is; rename opportunistically when touching those
  autocmds for other reasons, not as a standalone task.

**Watch item (uncertain risk, verify after actual upgrade):**
- 0.12 tightened URI-scheme detection on buffer names (RFC3986). PKM does not
  call `vim.uri_*` or otherwise parse buffer names as URIs, so Windows
  drive-letter paths (`P:/Active/...`, `P:/Notes/...`) should be unaffected.
  Not verified empirically. After upgrading, sanity-check `:PKMNewNote`,
  `follow_link` (`gf`), and sidebar note-opening (`edit` + `fnameescape`)
  against a `P:/Notes` path before trusting this is a non-issue.

**Process for future upgrades:**
- Re-run this audit against `:help news` for the target version before
  upgrading, not after. Check specifically: treesitter API changes (PKM's
  heaviest Neovim-API surface), autocmd event additions/removals, and any
  change to `foldmethod=manual` / `matchadd` semantics (used in `syntax.lua`'s
  frontmatter folding and citation highlighting).
- As of this audit, Neovim's own unreleased/HEAD changelog has no concrete
  items affecting PKM's code surface (no LSP, no diagnostics, no `vim.pack`
  dependency, no use of `vim.pos`/`vim.range`).

---

*Update this document as a batch after each version is completed, per the
Documentation Maintenance Cadence in the project instructions — not
continuously as project state changes.*
