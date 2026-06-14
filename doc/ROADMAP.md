# PKM.nvim — Project Roadmap for LLM Assistants

**Purpose:** Comprehensive guide for AI assistants continuing development across sessions. Read this before touching any code.

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

**Working features:**
== General ==
- ✅ Three folder types: Scratchpad, Journal, Consolidated
- ✅ Note creation with automatic numbering (`0042_note_Title.md`)
- ✅ Note types within Consolidated: `note`, `bib` (bibliography), `agg` (aggregate/collection)
- ✅ YAML frontmatter management with templates per note type
- ✅ Bidirectional citation system — inserting a citation in A automatically adds a backlink in B
- ✅ Flexible timestamp system (`full`, `date_time`, `date_only`)
- ✅ Free-form `title` field — decoupled from filename; file renamed only via `:PKMRenameNote`
- ✅ Note promotion: scratchpad → consolidated or journal
- ✅ Note conversion between types
- ✅ Import existing files into PKM structure
- ✅ Citation cleanup (removes stale references when notes are deleted)
- ✅ Tag merging across all notes
- ✅ Telescope integration: note browser, tag picker, citation picker, tag merge
- ✅ Export utility: filter notes by tag/title/body/filename, copy to folder (`:PKMExport`)
- ✅ Statistics window (`:PKMStats`)
- ✅ Cross-platform: Windows, WSL, Linux, macOS
- ✅ Context-aware citation picker — scores by active view (+2) and shared tags
     (+1); `<C-v>` view-only toggle
- ✅ `:PKMRenameNote` extended to journal and scratchpad
== Editing and viewing ==
- ✅ Markdown utilities — header counter, level shift, symbol abbreviations,
     sequence renumbering (single-family, flat counter — superseded plan in
     Next Steps §3, "Improved renumbering").
== Search ==
- ✅ Boolean filter system — full DSL over tag/title/text/filename
     (AND, OR, NOT, parentheses)
- ✅ In-memory note index with incremental invalidation (~290× faster)
- ✅ :PKMBrowse [expr] — index+filter browser. Pipeline (telescope.browse /
     ui.browse) implemented and correct. 
- ✅ :PKMTags — tag picker; on selection opens browse('tag:'..x). Index-backed.
     Kept as a secondary shortcut.
== Views ==
- ✅ Project view system — named saved filters, sidecar `views.json`, full CRUD commands
- ✅ Subproject hierarchy — table-valued view entries with `parent`/`filter`; composes AND chain
- ✅ `:PKMViewNew` — Create a new view
- ✅ `:PKMViewUpdate` — Update an existing view
- ✅ `:PKMViewLast` — reopen the last activated view (session-scoped)
- ✅ `:PKMViewSidebar` — persistent split buffer listing view notes; navigable tree header
- ✅ `:PKMViews` — tree-structured picker showing all views in parent-child hierarchy with note counts
- ✅ `:PKMViewSidebar` two-mode (overview + detail) with navigation history,
     header hints, `<BS>`/`<C-b>` navigation, `/` scoped search
- ✅ Scoped note search within sidebar (`/`) and from views tree (`<C-f>`)
- ✅ `views.get_last_view()` — active view context for consumer features
- ✅ `:PKMExportView [name]` — export named view's notes, skips filter form
- ✅ `:PKMBuffers` — persistent bottom buffer-list panel with auto-refresh

**Known limitations:**
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support

**Metadata notes:**
- The `status` field has been **removed** from frontmatter. Do not reintroduce it.
- Citation structure is grouped: `cites: {notes: [], bib: []}` and `cited_by: {notes: [], bib: []}`.
  Whether non-flat (hierarchical) citations will be added is undecided; do not change this
  structure without discussion.
- The `title` field is free-form and never overwritten by the system after creation.
  Filename changes are explicit only, via `:PKMRenameNote`.

---

## File Structure

```
pkm.nvim/
├── lua/pkm/
│   ├── init.lua        # Orchestration only: calls setup on all modules, wires commands/keymaps/autocmds
│   ├── config.lua      # Default config table and resolution logic (pure data, no side effects)
│   ├── utils.lua       # Shared cross-platform utilities: path joining, OS flags, notify
│   ├── commands.lua    # All :PKM* command registration (handlers require modules lazily)
│   ├── keymaps.lua     # All keymap wiring (receives resolved config as parameter)
│   ├── yaml.lua        # YAML frontmatter parsing and generation — complex, handle carefully
│   ├── timestamp.lua   # Timestamp creation, parsing, formatting
│   ├── citations.lua   # Bidirectional citation engine, tag indexing, citable item map
│   ├── notes.lua       # Note creation, conversion, promotion, linking, filename-YAML sync
│   ├── journal.lua     # Journal entry creation, journal-specific filename-YAML sync
│   ├── ui.lua          # Fallback UI: stats window, tag browser, search (no Telescope)
│   ├── telescope.lua   # Telescope pickers: search, tags, citations, tag merge
│   ├── templates.lua   # Template application to notes
│   ├── export.lua      # Note filtering and copy utility (read-only, no setup() needed)
│   ├── filter.lua      # Filter expression parser and evaluator (pure logic, no I/O)
│   ├── index.lua       # In-memory note index with incremental invalidation
│   ├── views.lua       # Named project views: sidecar file, CRUD, activate, list
│   └── bench.lua       # Benchmarking and load-testing utilities (infrastructure)
├── plugin/pkm.lua      # Auto-load marker
├── doc/
│   ├── pkm.txt         # Vim help documentation
│   ├── PKM_ROADMAP.md  # This file
│   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
│   └── CHANGELOG.md    # Session history
├── test/               # Test files
└── README.md
```

---

## Module Responsibilities

**init.lua** — pure orchestration. Calls `setup()` on every module, then calls
`commands.register()`, `keymaps.register(config)`, and `setup_sync_autocmds()`.
Also holds `delete_note_safely()` and `setup_sync_autocmds()` as these need
direct access to `M.config`.

**config.lua** — pure data. Holds the default config table and `resolve(user_config)`,
which merges defaults with user input, resolves paths, validates, and injects author
into templates. No side effects. Contains a `projects` table for named view definitions.

**utils.lua** — shared utilities. `utils.join(...)`, `utils.sep`, `utils.normalize(path)`,
`utils.ensure_dir(path)`, `utils.is_windows`, `utils.is_wsl`. No setup() needed.

**commands.lua** — registers all `:PKM*` user commands. Handlers use lazy `require`
inside each callback. References to `init.lua` functions go through `require('pkm')`.

**keymaps.lua** — registers all `<leader>` keymaps. Receives `config` as a parameter
to `register(config)` because it needs keymap strings at registration time.

**yaml.lua** — parse and generate YAML frontmatter. Contains a non-trivial parser
handling nested empty structures. **Do not modify without strong justification.**

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses existing timestamps.

**citations.lua** — bidirectional citation sync; `get_all_tags()`, `get_file_tags(path)`,
`get_citable_items_map()`, `merge_tags(sources, target)`.

**notes.lua** — all note file operations: create, convert, promote, import, link,
follow link, backlinks. Title field is free-form; filename changes are explicit
via M.rename_note(), which prompts, sanitizes, renames on disk, and propagates
to citations.

**journal.lua** — journal creation (auto-timestamped by default); journal-specific filename-YAML sync.

**ui.lua** — fallback UI for stats, search, and tag browsing when Telescope is absent.

**telescope.lua** — all Telescope pickers. Checks availability at call time (not load
time — critical for Lazy.nvim).

**export.lua** — filter notes by frontmatter fields and body text; copy matches to a
destination folder. No `setup()`. Never modifies note files. Delegates filter
evaluation to `filter.lua` and file collection to `index.lua`.

**filter.lua** — pure logic, no I/O. Parses filter expression strings into ASTs and
evaluates them against note data tables. Grammar: AND/OR/NOT over tag/title/text/filename
predicates with parentheses and quoted values. `from_legacy()` converts old
`{tags_any, tags_all, title, text}` tables for backward compatibility.

**index.lua** — in-memory note index. Entry shape: `{path, filename, title, tags, body, mtime}`.
Lazy build on first `get_all()` call. Incremental invalidation via `BufWritePost` autocmd
and explicit `invalidate(path)` calls after every programmatic file write or delete.
Title: free-form YAML `title` if non-empty, otherwise filename stem with underscores
replaced by spaces. `filename`: stem without extension, used by the `filename:` predicate.

**views.lua** — named project views. Reads from `views.json` (sidecar at PKM root)
and `config.projects`; sidecar wins on collision. Supports both string values
(simple views) and table values `{parent, filter}` (subprojects — effective filter
composes parent chain via AND, with cycle detection and depth limit of 8).
`setup()` registers BufWritePost autocmd to reload on sidecar save. Full CRUD.
Telescope picker with exact-substring prompt and file preview; float fallback.
`:PKMViews` opens a separate tree-structured picker (`list_views()`) showing
the full hierarchy with note counts; uses `build_tree_entries()` for depth-first
ordering. Internal helpers: `get_view_parent`, `get_view_children`,
`build_tree_entries`. Sidebar features and `get_last_view`.
Persistent sidebar (`open_sidebar`) with navigable tree header showing parent and
children. Last-view tracking (`open_last`). Telescope picker with exact-substring prompt and file preview; float fallback.

**bench.lua** — developer benchmarking and load-testing. Not user-facing, no commands.
Four-phase suite: raw scan, index build, index query, filter eval. Self-cleaning
(synthetic files deleted after run). `baseline()` times real corpus read-only.

**markdown.lua** — general markdown editing utilities. No setup() needed.
`append_next_header`: duplicate current header with trailing counter +1, append at EOF.
`shift_header_level(direction, start, end)`: shift `#`-level in range.
`renumber_sequence(start, end)`: renumber ordered-sequence items in line range.
`renumber_at_cursor()`: renumber sequence in paragraph around cursor.

---

## Configuration Reference

```lua
require('pkm').setup({
  root_path = vim.fn.expand('~/Notes'),  -- required

  folders = {
    scratchpad   = "01-Scratchpad",
    journal      = "02-Journal",
    consolidated = "03-Consolidated",
    templates    = "templates",
  },

  sync = {
    enabled           = true,
    auto_sync_on_save = true,
  },

  timestamp = {
    default_format = "full",  -- "full" | "date_time" | "date_only"
    auto_timestamp = true,
  },

  user = {
    name        = "",
    email       = "",
    institution = "",
  },

  -- Optional: define views declaratively. Prefer :PKMViewNew / views.json
  -- for views that change frequently. Sidecar (views.json) wins on collision.
    projects = {
      "rpg":    "tag:rpg AND (title:ringforge OR text:ringforge)",
      "ringforge-mechanics": {
        "parent": "ringforge",
        "filter": "tag:mechanics"
      }
      clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
    }

  sidebar_width = 40,  -- width of the :PKMViewSidebar window

  -- Buffer-local symbol abbreviations and insert-mode keymaps.
  -- trigger (iabbrev) and key (insert-mode keymap) are both optional;
  -- expansion is required. Registered per-buffer on BufReadPost.
  symbols = {
    { trigger = 'emdash', key = '<M-->', expansion = '—' },
    { trigger = 'sect',   key = '<M-s>', expansion = '§' },
    { trigger = 'ordm',   key = '<M-o>', expansion = 'º' },
  },

  keymaps = {
    -- Note operations
    new_note        = "<leader>nn",
    new_journal     = "<leader>nj",
    new_scratchpad  = "<leader>ns",
    rename_note     = "<leader>nr",
    insert_citation = "<leader>nc",
    goto_citation   = "<leader>ng",
    delete_note     = "<leader>nd",
    link_note       = "<leader>nl",
    follow_link     = "gf",
    backlinks       = "<leader>nb",
    import_note     = "<leader>ni",
    convert_note    = "<leader>nx",
    promote_note    = "<leader>np",
    transpose_note  = "<leader>nT",
    change_note_type = "<leader>nC",
    -- Views
    view_last    = "<leader>nV",
    view_list    = "<leader>nv",
    view_sidebar = "<leader>nS",
    view_buffers = "<leader>vb",
    -- Search and browsing
    browse       = "<leader>nf",   -- :PKMBrowse — primary, unified search bar
    browse_tags  = "<leader>nt",   -- :PKMTags  — secondary, quick tag entry
    -- search (:PKMSearch) removed — see Next Steps §2
    -- Markdown editing
    ---- Headers
    next_header        = "<leader>Mh",
    header_level_up    = "<leader>M^",
    header_level_down  = "<leader>M_",
    renumber_list      = "<leader>Mr",
  },
```

---

## Development Roadmap

### Active

No items currently in active development. Navigation system complete through Step 3.

---

### Implementation phases

A sequencing layer over the Next-Steps and Near-term items. The lists record
WHAT; this records IN WHAT ORDER and WHY. Rules: (1) bugs before features built
on the same subsystem; (2) shared foundations before their consumers;
(3) measure before optimising (the bench.lua rule). An item may be scheduled
earlier than its heading suggests — the heading is its category, the phase is
its turn.

**(Complete) Phase 0 — Bug triage (small, unblock everything).**
- `:PKMBrowse` arg parsing: `nargs='?'` → `nargs='*'` (needed so the §2
  command-line shortcut `:PKMBrowse <expr>` accepts multi-token expressions).
- Cross-citation write-through to open buffers (Near-term §4) — DATA LOSS;
  scheduled here despite its filing.
- Buffer-panel `E32` on `w`, and the phantom-window-on-last-buffer bug
  (Next Steps §5, "Fix").

**(Complete) Phase 1 — Core search + small self-contained features.**
- §2 Unified filter-as-you-type search: extend `filter.lua` with the default
  "any" predicate, rewrite the picker to evaluate the live prompt, delete
  `:PKMSearch`, repoint `<leader>nf`. High-value; several items below browse
  through it.
- §1 Metadata commands (`:PKMSetTitle` / `:PKMAddTag` / `:PKMRemoveTag`).
- §4 `:PKMOrphans`.
- §6 `:PKMViewUpdate` rename / reparent.
- Near-term §2 `:PKMBrowseRecent`.
- Near-term §1 filter autocomplete (after the §2 grammar lands and the nargs
  fix; complements the search bar).
- §9 conventions SPEC only (implementation is Phase 4).

**(Currently here) Phase 2 — Foundations for the explorer UI.**
- Near-term §4 per-tab-page window state — prerequisite for the unified UI,
  not a late polish item; promoted here.
- §4 Sidebar readability improvements.
- §7 `bench.views_suite` — measure before any match_all-caching lands.
- §5 notes-navigator sidebar.

**Phase 3 — Larger features.**
- §5 unified, toggleable explorer UI + auto-on/off policies.
- §3 improved renumbering (nested / quoted / emphasis families).

**Phase 4 — Markdown presentation (one workstream; decide mechanism first).**
- §3 syntax mechanism decision (consolidate Vimscript `after/syntax` vs migrate
  to bundled tree-sitter queries).
- §3 frontmatter folding / conceal.
- §3 context-aware highlighting + its two bugs.
- §3 `**1.**`-style ordered-list indent recognition.
- §9 conventions IMPLEMENTATION.

**Phase 5 — Last changes, fi feasible.**
- §8 deleted-note trash (tombstone-manifest caveat). (if too complex or
  performance intensive, defer. Otherwise, implement).
- preview.lua, persistent index, review queue, `_match_cache` (only if §7
  proves it necessary, otherwise defer).

-- Current update plan finishes here --

After finishing phases and reaching this point, and only then, do:
1. Review ROADMAP and check if all steps were successfully completed. 
2. Reincorporate deferred (see below, and also if you defer any items from
   Phase 5) items into their designed stops (e.g. Distant additions, potential
   additions, near-term, etc.).
3. Rewrite the plan from Next Steps up to distant and potential additions. 
4. Update other relevant ROADMAP sections.
5. Update pkm.txt, README.md, and any other pertinent docs (e.g.
   LLM_Context.md, if necessary).

**Deferred:**
- Explorer UI customisation: moved from near-term to distant.
- ASCII / text diagrams: moved from near-term to distant

### Next Steps

**3. Improved and new markdown features:**

- Improved renumbering with `:PKMRenumberlist`: 
   - add support for other structures: lists containing nested elements,
     numberings inside quotes, as well as numbered headers and bolder/italiscized
     numbers.

     ```
     1. a
       2. c
       1. x
     3. a
     2. 3
     ```
     
     becomes
     
     ``
     1. a
       1. c
       2. x
     2. a
     3. 3
     ```

     ```
     *1*. a
       *2*. c
       *1*. x
     *3*. a
     *2*. 3
     ```
     
     becomes
     
     ```
     *1*. a
       *1*. c
       *2*. x
     *2*. a
     *3*. 3
     ```

     ```Ordered list inside citation/quotation.
     > 1. a
     >   2. c
     >   1. x
     > 3. a
     > 2. 3
     ```
     
     becomes
     
     ```Ordered list inside citation/quotation.
     > 1. a
     >   1. c
     >   2. x
     > 2. a
     > 3. 3
     ```

     ``` ((numbered header with text aligned with margin, without following
     indent))
     ## 1. <text>
        
     <more text>
     
     ## 3. <text>
     <more text>
     ```
     
     becomes
     
     
     ``` ((numbered header with text aligned with the list indentation level))
     ## 1. <text>
        
     <more text>
     
     ## 2. <text>
     <more text>
     ```

     ``` ((numbered header with text aligned with text indented according to
     the header))
     ## 1. <text>
        
        <more text>
     
     ## 3. <text>
        <more text>
     ```
     
     becomes
     
     
     ``` ((numbered header with text aligned with text indented according to
     the header))
     ## 1. <text>
        
        <more text>
     
     ## 2. <text>
        <more text>
     ```

- A command to convert unordered list to ordered and the other way around (
if there are multiple levels, the user should be prompted about how deep to convert. Note that converting mixed lists should ignore the part that is already as intended, e.g. if converting unordered to ordered, any numbers in the selected
range should be kept as they are. 

- Improved recognition of indenting when list prefixes are surrounded by `*`
  and other markers. Currently `1. <text>` autoindents as a first level list,
  but not `**1. <text>**`.

- Add PKM related context-aware syntax highlighting: 
    - **Ship the highlighting from inside the plugin, and choose its mechanism.**
     The runtime syntax file is Vimscript, not Lua: Neovim sources
     `after/syntax/markdown.vim` (and `syntax/markdown.vim`) from every
     'runtimepath' entry, and lazy.nvim puts the plugin on 'runtimepath'. So
     moving the existing syntax file into the repo at
     `after/syntax/markdown.vim` is enough to consolidate it — there is no
     `.lua` syntax-loader path to overwrite. For Lua-driven setup, use an
     `ftplugin`/autocmd, not a `syntax/*.lua` file.
     DECIDE FIRST, because the items below diverge sharply by mechanism:
       (i) consolidate the current Vimscript `syntax` rules into the plugin, or
       (ii) migrate Markdown highlighting to bundled tree-sitter queries
            (`queries/markdown*/highlights.scm`, plus `injections.scm` to parse
            the frontmatter AS YAML and optionally math as LaTeX).
     Path (ii) turns most goals below (frontmatter-as-YAML, citation
     highlighting, suppressing 4-space indented code, 4th-level list prefixes,
     and conceal) from brittle regex into declarative queries. Record the choice
     in CHANGELOG before coding.
    - Currently missing or unsupported:
      - YAML frontmatter: current syntax highlighting treats YAML metadata as
        typical markdown text. 
      - in-text citations: currently without any highlighting.
      - Marker highlighting or "preview": there is no font change or highlight of
      italics or bold as of yet.
      - Stop four-space indented text from highlighting as code blocks (in
        green). Only text marked as code with one or three \` should be
        considered as code. Four-space indented text should follow highlighting
        for standard text, including that for nested lists, if applicable.
      - Consider highlighting text inside quotation marks as well, or maybe just
       the quotation marks, and only when both surround some text. This point
       is optional and should be added only if it doesn't cause the
       highlighting to be excessive or distracting.
    - Related bugs: 
      - prefixes for lists from the 4th level and beyond (both ordered and
      unordered) are not being highlighted, despite recent attempts in this
      behalf.
      - Text just before a separator `---` highlights differently from other
      texts (in bold blue). Check if this is intended.
      - Underscores between letters highlight in red (e.g `a_a`). Check if this
      is intended, otherwise fix.
- **Frontmatter folding and conceal (in-file metadata readability).** The
  primary in-file remedy for heavy YAML frontmatter and long citation lists —
  no sidecar separation required (see "Metadata system review" under Potential
  goals). Two complementary mechanisms:
  - Folding: collapse the `---`…`---` block (and optionally long
    `cites`/`cited_by` sub-lists) by default, via a buffer-local
    `foldmethod=expr` + `foldexpr` set in a PKM-scoped ftplugin/autocmd, or via
    fold markers. Keep folds opt-out so the raw block is one keystroke away.
  - Conceal: hide noisy syntax (wiki-link brackets, citation link fields)
    behind `conceallevel`/`concealcursor`, so the rendered note reads cleanly
    while the underlying text is untouched. Conceal is implemented through the
    mechanism chosen above (Vimscript `syntax conceal` or tree-sitter
    `@conceal`), so build it together with the §3 syntax decision. This is the
    deliverable the metadata-separation decision gate (Potential goals → D)
    requires us to try before considering any sidecar redesign.

---

**5. PKM "note explorer:"** 
- Notes sidebar: Add sidebar to navigate in the main notes folder, to and from
  each note subfolder (e.g.: consolidated).

- Integrate all bars into a main "UI" that can be toggled on or off. The user
  can set a default configuration for the UI (decide if the UI toggles on or
  off automatically when opening neovim, or when entering the pkm folder, or
  when opening a note contained in the pkm folder, or a combination, or
  manually only). 
 
  The UI should have a base configuration, e.g. a left sidebar which is divided
  horizontally between notes and views sidebars and a bottom bar for the
  buffers. Modifiability of this UI is set as a near term addition.
 
  With this, we effectively have a "note explorer submodule/subplugin" for our
  pkm system.

- Sidebar readability: show the filename of files under the cursor in a
  horizontal neovim "infobar", to allow readability of filenames that are too
  long for the sidebar. If the text is too long for the "infobar", it can be
  wrapped (carefully as to not obstruct text in other infobars or in open buffers.

- Sidebar navigability: there should be a quick way to go from any window to
  the sidebar. This is especially important if the  user is working with
  multiple vertical windows.

---

**7. Performance: views and sidebar at scale**

*Motivation:* The sidebar tree header calls `M.match_all()` for the parent and
every child to display note counts. Each `match_all` call does a full index scan
+ filter eval. At small scales (< 50 views, < 10k notes) this is negligible,
but it has not been measured at realistic scale.

**Benchmark plan:**

Add `bench.views_suite(n_views, branching_factor, opts?)` to `bench.lua`:
- Generate `n_views` synthetic views with the given branching factor
  (e.g. branching_factor=3 → each root has 3 children, each child has 3 grandchildren)
- Time `views.list()`, `views.match_all(name)`, and `views.open_sidebar(name)`
  across 50 / 100 / 300 / 1000 views

Expected bottleneck: `sidebar_build_lines` calls `match_all` for parent + all
direct children. At 20 children × 10k notes, this is ~200k filter evals per
sidebar open.

**Potential optimisation:** Add `_match_cache = {}` to `views.lua` module state —
cached path arrays per view name, invalidated alongside `_tree_cache` in
`invalidate()`. `match_all()` would populate this cache; `open_sidebar()` and
tree header builds would read from it on repeat accesses without re-scanning.
Should not be implemented before benchmarking confirms it is necessary.

---

**8. Deleted note retriavability** deleted notes go either into the OS's trash
or at a dedicated "notes trash" that conserves them temporarily for retrievability
via a specific command or a general "undo" command in the "notes explorer".

---

**9. Note-taking format standardization**

The note-taking conventions are defined in `doc/CONVENTIONS.md`.
That document is the authoritative reference; update it directly when
conventions change.

Remaining implementation work (Phase 4):
- Syntax highlighting for `((...))` meta-comments and `[text]` citation
  markers.
- `formatlistpat`/ftplugin recognition for emphasis-wrapped ordinals like
  `**1.**`.
- Template hints or snippets for the citation formats.

---

### Near-term additions


**4. Potential bugs to investigate before next major version:**
- **Sidebar + tab pages:** `_sidebar_win` tracks one window globally. If the
 user has multiple tab pages, opening a sidebar in a second tab would
 conflict with the first tab's state. Mitigation: track sidebar state per
 tab page (`vim.api.nvim_get_current_tabpage()`).

---

### Distant Additions (mid-term to long-term)

- Customization of the "explorer" UI:  
  - positions, width and length of each bar;
  - options for when the UI should automatically turn on or off (by terminal
    folder, by neovim working folder, by buffer (the buffer pertains to a PKM
    file)), or any combination of those, or none); as well as 
  - other important options that we predict users may need.

- **`lua/pkm/preview.lua`** Browser-based live preview: Markdown + LaTeX
  (MathJax), WebSocket live updates on save, cross-platform browser opening,
  terminal fallback (glow/mdcat).

- **Persistent index** Serialize the in-memory index to disk (msgpack or JSON)
  with mtime-based incremental updates on startup. Needed only if startup scan
  time becomes unacceptable at very large corpus sizes (likely >50k notes).
  Evaluate other solutions for speed at >10k notes before committing to this.
  Run `bench.baseline()` on the real corpus first.

- **`_match_cache` in views.lua** Cache the matched path arrays alongside the
  filter trees. Would make repeated `match_all` calls (e.g. sidebar tree header
  builds) O(1) until the next cache invalidation. Implement only after
  benchmarking shows it is necessary.

- **Note review queue.** Enables the user to select and keep track of notes intended
  for review. Might include organizers, separators, or interact with filters to
  enable the user to categorize such notes according to priority, subject, etc.

-*5. Alternative diagram and imaging methods to allow enhancement of notes
without dependence on external image files: e.g. ASCII (text-based) art.

((All features under this item should be examined for readability (AI, machine,
and human) and portability before further detailing and implementation)).
- Add support or consider already supported methods, with emphasis on human and
  AI readability and general portability, and, as a secondary goal, easyness of
  use.
- Standardize methods for human and AI usage, in order to aid correct usage
  of such graphics and their understanding by any user.

---

### Potential but not guaranteed goals (do not design toward)

- **Alternative PKM modes:** Obsidian-style backlink graph, pure Zettelkasten ID-based
  linking, etc. Would be selectable configurations, not the default.

- **Image and visualization support:** embed images with normalized paths, Mermaid
  diagram support in preview, possibly inline rendering (kitty/iTerm2 protocols).

- **`:PKMViewStats`** — show a table of all views with their note counts and
  subproject depth. Provides an overview of how the knowledge base is
  organised. Implementation: iterate `views.list()`, call `match_all()` for
  each, format as a notification or float.

- **Metadata system review (in-file vs separated metadata).** Recorded for
  future reconsideration only — not designed toward. The decision gate (D)
  requires the cheaper in-file mitigations to be exhausted first.

  A. Current state — in-file metadata.
     Positive: easy export; immediate coupling with content during AI/RAG
       contextualisation; one-hop navigation to cited notes.
     Negative: complex buffer management for cross-citation of open files (the
       root cause of the Near-term §4 data-loss bug); long citation lists bloat
       the frontmatter and hurt readability; metadata is hard to protect from
       accidental edits.
     Mixed: title lives in metadata — no first-level header required, but
       readers must look to the frontmatter to find it.

  B. Alternative — separated metadata (sidecar).
     Positive: cross-citation only ever writes the sidecar, never a note body
       the user may have open → removes the data-loss failure mode entirely;
       long citation lists leave the note body, so they cannot hurt its
       readability; metadata can be guarded independently (separate, optionally
       read-only file).
     Negative: export becomes two files per note and must associate them;
       AI/RAG must recognise and attach the sidecar (true cost depends on the
       consumer's RAG implementation); navigating to cited notes needs full
       in-text links or extra indirection; cross-citation must open/edit a
       separate file (cost depends on implementation/perf).
     Mixed: requires a first-level header or accepting the filename as a
       surrogate title; if title stays in metadata, a sync mechanism between the
       user-set title and the sidecar is needed.

  C. Other: a metadata FOOTER within the note, if viable.

  D. Decision gate — do not design toward separation yet.
     - The one concrete pain motivating B (in-file "complex buffer management")
       is exactly the Near-term §4 bug, which has a LOCAL fix (write-through to
       open buffers). Do not justify a cross-cutting redesign (yaml, citations,
       index, notes, export, templates all change) by a bug with a local fix.
     - The other real pain (long-metadata readability) is largely solved
       in-file by frontmatter folding/conceal — now a Next Step (§3).
     - Separation also trades against stated principles: "easy export" becomes
       two files; "immediate AI/RAG coupling" becomes consumer-dependent.
     - Criterion: revisit separation ONLY IF, after (1) the buffer
       write-through fix and (2) frontmatter folding/conceal, the in-file
       approach is still unacceptable in daily use.

---

### Unlikely goals, nongoals, or out of consideration (do not design toward)

- **Multi-wiki:** multiple independent note namespaces with separate counters and citation
  permission rules. Superseded by the project-view system for all realistic use cases.
  The single global counter is a guarantee of note uniqueness; do not break it.
  Could be revisited only if physical namespace isolation becomes a concrete requirement.
- **Non-flat citations:** hierarchical or categorized citation structure beyond the current
  `notes`/`bib` grouping. Undecided; the current structure may be permanently sufficient.

## Critical Rules for LLM Assistants

### Never do this

| Rule | Reason |
|---|---|
| Modify `yaml.lua` without strong justification | Complex, carefully fixed bugs; any regression corrupts files |
| Check Telescope availability at module load time | Lazy.nvim defers loading; always check at call time with `pcall(require, 'telescope')` |
| Use `generic_sorter` for exact-match contexts | It uses fzy (subsequence matching); use `finders.new_dynamic` with `string.find(..., 1, true)` |
| Reintroduce the `status` field | Intentionally removed |
| Use deprecated Neovim APIs | Use `nvim_set_option_value`, `vim.keymap.set` |
| Assume path separator | Always use `utils.sep` or `package.config:sub(1, 1)` |
| Design toward multi-wiki | Superseded by project views; not a current goal |
| Physically separate notes for project organisation | Projects are views, not folders; all notes share one namespace |
| Optimize `collect_files` without first running `bench.lua` | Optimizing blind; baseline measurements are required first |

### Always do this

- File-level header block
```lua
-- =============================================================================
-- pkm.module — One-line description
-- =============================================================================
-- Dependencies : modules this file requires
-- Consumed by  : modules that require this file
--
-- Public API:
--   function_name(params) → return description
-- =============================================================================
```

- `local M = {}` and module-level locals


- Section separators** between logical groups:
```lua
-- =============================================================================
-- SECTION: Section name
-- =============================================================================
```

- Cross-platform paths
```lua
local path = utils.join(dir, file)
local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)
```

- Exact substring matching (never fzy)
```lua
if haystack:lower():find(needle:lower(), 1, true) then ... end
```

- Telescope at call time
```lua
local ok = pcall(require, 'telescope')
if ok then ... else ... end
```

- Option setting (Neovim 0.10+)
```lua
vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
vim.keymap.set('n', 'q', fn, { noremap = true, silent = true, buffer = buf })
```

### OS detection

```lua
utils.is_windows  -- boolean
utils.is_wsl      -- boolean
```

### YAML citation structure — do not change

```yaml
cites:
  notes:
    - identifier: note-0042
      title: "Note Title"
      link: "[[0042_note_Note_Title]]"
  bib: []
cited_by:
  notes: []
  bib: []
```

---

## Environment

| Item | Value |
|---|---|
| OS | Windows 10 + WSL (Ubuntu) |
| Editor | Neovim 0.11.3 |
| Plugin manager | Lazy.nvim |
| Plugin path | `P:/Active/pkm-nvim/` (Windows) · `/mnt/p/Active/pkm-nvim/` (WSL) |
| Notes path | `P:/Notes` (Windows) · `/mnt/p/Notes` (WSL) |
| Config path | `~/AppData/Local/nvim/` (Windows) · `~/.config/nvim/` (WSL) |

---

## Debugging Quick Reference

```vim
:lua print(vim.inspect(require('pkm').config))
:messages
:PKMStats
:lua require('pkm.yaml').validate_frontmatter()
```

---

## Git Conventions

**Commit format:**
```
<type>: <summary>

- detail
- detail
```
Types: `feat` `fix` `docs` `refactor` `test` `chore`

**Branches:** `feat/<name>`, `fix/<name>`

---

## Knowledge Base

- Neovim docs: https://neovim.io/doc/
- Lua docs: https://www.lua.org/docs.html
- LuaRocks style guide: https://github.com/luarocks/lua-style-guide
- LaTeX docs: https://www.latex-project.org/help/documentation/

---

*Update this document when the project state changes.*
