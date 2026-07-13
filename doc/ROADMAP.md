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

**Current version:** v1.5.9. There is no separate release/dev split — all
work happens directly on `dev`; `main` holds periodic stable backups of
`dev`, not an independently maintained release line. The upcoming work is
organised under **Release Plan** below.

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
- ✅ `after/syntax/markdown.vim` — Vimscript fallback active when PKMMode is off
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

## File Structure

```
pkm.nvim/
├── lua/pkm/
│   ├── init.lua        # Orchestration: setup, delete_note_safely, sync autocmds
│   ├── config.lua      # Default config table and resolution logic (pure data)
│   ├── utils.lua       # Shared cross-platform utilities: path join, OS flags
│   ├── commands.lua    # All :PKM* command registration (handlers lazy-require)
│   ├── keymaps.lua     # All keymap wiring (receives resolved config)
│   ├── yaml.lua        # YAML frontmatter parsing and generation — handle carefully
│   ├── timestamp.lua   # Timestamp creation, parsing, formatting
│   ├── citations.lua   # Bidirectional citation engine, tag indexing, add/remove tag
│   ├── notes.lua       # Note CRUD, conversion, promotion, linking; set_title
│   ├── journal.lua     # Journal entry creation, filename sync
│   ├── ui.lua          # Fallback UI (no Telescope): browse, tags, bufpanel
│   ├── telescope.lua   # Telescope pickers: browse, tags, citations, tag merge
│   ├── templates.lua   # Template application to notes
│   ├── export.lua      # Note filtering and copy utility (read-only, no setup)
│   ├── filter.lua      # Filter DSL parser and evaluator (pure logic, no I/O)
│   ├── index.lua       # In-memory note index with incremental invalidation
│   ├── views.lua       # Named views: sidecar, CRUD, two-mode sidebar, type filter
│   ├── mode.lua        # PKMMode: session context toggle, syntax enable/disable
│   ├── syntax.lua      # Tree-sitter syntax management: highlights, folding, matches
│   ├── trash.lua       # Soft-delete: manifest, trash/restore/empty/purge_old
│   ├── markdown.lua    # Markdown editing: headers, renumber, convert_list, symbols
│   └── bench.lua       # Benchmarking utilities (developer, not user-facing)
├── queries/markdown/
│   ├── highlights.scm  # PKM tree-sitter captures: indented code, list markers
│   └── injections.scm  # YAML injection into frontmatter (minus_metadata nodes)
├── after/syntax/
│   └── markdown.vim    # Vimscript fallback syntax (non-PKMMode); two rules retained
├── plugin/pkm.lua      # Auto-load marker
├── doc/
│   ├── pkm.txt         # Vim help documentation
│   ├── ROADMAP.md  # This file
│   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
│   ├── PHILOSOPHY.md   # Design principles (non-negotiable constraints)
│   └── CHANGELOG.md    # Version history
├── test/               # Test files
└── README.md
```

> Planned new module `lua/pkm/panel.lua` (generic panel infrastructure) is
> introduced in v1.6.0; it is not present yet and so is absent from the tree
> above. Planned new doc `doc/CONVENTIONS.md` is tracked under Distant
> Additions 1.1.

---

## Module Responsibilities

**init.lua** — pure orchestration. Calls `setup()` on every module, registers commands
and keymaps, sets up sync autocmds. Holds `delete_note_safely()` (uses trash if enabled,
permanent delete otherwise) and `setup_sync_autocmds()` (BufWritePre for `last_updated_on`,
BufWritePost for citation sync + silent reload + TS restart).

**config.lua** — pure data. Default config table and `resolve(user_config)`. Contains
`projects`, `pkm_mode`, `trash`, all keymap defaults. No side effects.

**utils.lua** — `utils.join(...)`, `utils.sep`, `utils.normalize(path)`,
`utils.ensure_dir(path)`, `utils.is_windows`, `utils.is_wsl`.

**commands.lua** — registers all `:PKM*` commands. Handlers use lazy `require`.
Contains `browse_complete` (filter DSL autocomplete for `:PKMBrowse`).

**keymaps.lua** — `register(config)`. Receives resolved config; keymap strings
needed at registration time. Registers both normal and visual mode bindings for
range commands (`renumber_list`, `convert_list`, header level shift).

**yaml.lua** — YAML frontmatter parse and generation. **Do not modify without
strong justification.** Contains the non-trivial nested-empty-structure parser.

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses timestamps.

**citations.lua** — bidirectional citation sync (`manage_backlink`, `update_references`,
`update_references_on_rename`, `cleanup_deleted_note`); `get_all_tags()`,
`get_citable_items_map()`; `merge_tags(sources, target)`;
`add_tag(tag?)` / `remove_tag(tag?)` — buffer-only frontmatter mutation.

**notes.lua** — note CRUD: `create_new_note`, `create_scratchpad`, `promote_note`,
`do_convert`, `convert_note`, `change_note_type`, `transpose_note`, `rename_note`,
`link_to_note`, `follow_link`, `show_backlinks`, `import_note`.
`set_title()` — buffer-only title mutation (no `index.invalidate`).
`get_next_note_number()` — checks both consolidated folder AND trash manifest.

**journal.lua** — journal creation (auto-timestamped); `sync_filename_on_save`.

**ui.lua** — fallback UI (no Telescope): `browse`, `browse_paths`, `browse_recent`,
`browse_tags`, `insert_citation_ui`, `merge_tags_ui`, `show_stats`.
`toggle_bufpanel()` — per-tabpage bottom buffer-list panel.
`is_bufpanel_open()`.

**telescope.lua** — all Telescope pickers. Checked at call time via `pcall`.
`browse`, `browse_paths`, `browse_recent`, `browse_tags`, `insert_citation_picker`,
`merge_tags_picker`.

**export.lua** — filter + copy notes. No setup. Read-only. Delegates to filter.lua
and index.lua. `export_direct(label, paths)` skips the filter form.

**filter.lua** — pure logic, no I/O. Grammar:
`field = tag | title | text | filename | type | any`.
`any`: bare words and unknown-field tokens; case-insensitive substring over all fields.
`type`: exact match against `entry.note_type`. `tag`: exact (case-insensitive).
`from_legacy(tbl)` converts `{tags_any, tags_all, title, text}`.

**index.lua** — in-memory note index. Entry shape:
`{path, filename, note_type, title, tags, body, mtime, has_citations}`.
`note_type`: `note|agg|bib|journal|scratch|other`. `has_citations`: true when
any cites/cited_by group is non-empty.
Lazy build on first `get_all()`. Incremental invalidation via BufWritePost autocmd
and explicit `invalidate(path)` after every programmatic write or delete.
**Must NOT be called from buffer-only metadata commands** — no disk write occurred.

**views.lua** — named project views. Sidecar `views.json` + `config.projects`.
Two-mode sidebar (overview + detail); per-tabpage `_tabs` state including `type_filter`.
`sidebar_build_lines(name, paths, total_count)` — builds detail lines; callers
pre-filter by type and pass `#all_paths` as total for "N of M" display.
`refresh_sidebar_if_open()` — iterates all tabpages, applies per-tab type filter.
`edit_view(name?)` — action picker: edit filter / rename / reparent.

**mode.lua** — `M.activate()`, `M.deactivate()`, `M.toggle()`, `M.set(arg)`,
`M.is_active()`. Manages PKMMode session state: triggers index prebuild, opens
sidebar + bufpanel, enables syntax on all PKM buffers. `setup(config)` registers
BufReadPost (open_note trigger) and DirChanged (enter_dir trigger) autocmds.
Idempotent in both directions.

**syntax.lua** — per-buffer tree-sitter activation. `M.enable(bufnr)`: starts
markdown TS parser, defines HL groups, registers per-window matchadd highlights
(PKMCitation, PKMMetaComment) and window opts (foldmethod=expr, foldtext).
`M.disable(bufnr)`: stops TS, clears matches, restores opts, runs `syntax on`.
`M.foldexpr(lnum)`, `M.foldtext()`.
**UndoPost does not exist in Neovim ≤ 0.11.x** — do not register it.

**trash.lua** — soft-delete system. Trash folder: `{root}/.pkm-trash/`.
Manifest: `manifest.json` array of `{filename, original_path, title, deleted_at,
deleted_timestamp}`. `trash_note(filepath)` — moves file, does NOT strip backlinks.
`restore_note(entry)` — moves back, re-indexes; backlinks intact, no reconstruction.
`empty()` — permanent delete + `cleanup_deleted_note` for each entry.
`purge_old()` — auto-purge entries older than `max_age_days`.
`setup(cfg)` — stores config, schedules `purge_old()` via `vim.defer_fn(fn, 5000)`.

**markdown.lua** — `append_next_header`, `shift_header_level`, `setup_symbols`,
`renumber_sequence` (per-level counter stack; list/list_emph/list_bold_line/
hdr_prefix/hdr_suffix families; blockquote-aware),
`renumber_at_cursor`, `convert_list(start, end, direction?)`,
`convert_list_at_cursor(direction?)`.

**bench.lua** — developer benchmarking. Not user-facing. Four-phase suite: raw scan,
index build, index query, filter eval. `views_suite(opts?)` — scaling bench for
O(V × N) sidebar path. Self-cleaning; `baseline()` times real corpus read-only.

---

## Configuration Reference

```lua
require('pkm').setup({
  root_path = vim.fn.expand('~/Notes'),  -- required; defaults to ~/Notes

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
    name  = "",
    email = "",
  },

  -- Named project views (declarative). Sidecar views.json wins on collision.
  -- Views defined here CANNOT be renamed or deleted through PKM's own commands
  -- (:PKMViewUpdate's Rename, :PKMViewDelete) — the plugin cannot safely rewrite
  -- this file's Lua source. Use :PKMViewNew / views.json for any view you intend
  -- to manage through PKM's commands; reserve config.lua for views you commit to
  -- maintaining by hand. Subprojects (entries with a `parent` field) are NOT
  -- recommended here even for hand-maintained views: if the parent lives in the
  -- sidecar and is renamed through the UI, this entry's `parent` goes silently
  -- stale (from v1.5.4 the rename emits an advisory warning, but cannot fix it).
  projects = {
    clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
    -- Subproject example (discouraged here — see note above):
    -- ringforge = 'tag:ringforge',
    -- ["ringforge-mechanics"] = { parent = "ringforge", filter = "tag:mechanics" },
  },

  sidebar_width = 40,

  -- Buffer-local insert-mode keymaps registered on BufReadPost for PKM notes.
  -- trigger and key are both optional; expansion is required.
  symbols = {
    { trigger = 'emdash', key = '<M-->', expansion = '—' },
    { trigger = 'sect',   key = '<M-s>', expansion = '§' },
    { trigger = 'ordm',   key = '<M-o>', expansion = 'º' },
  },

  -- PKM Mode behaviour
  pkm_mode = {
    triggers = {
      open_note = true,   -- activate on BufReadPost for any PKM file
      enter_dir = false,  -- activate on DirChanged to/from PKM root
    },
    layout = {
      sidebar  = false,    -- open sidebar on activation
      bufpanel = true,    -- open buffer panel on activation
    },
    index = {
      prebuild = true,    -- eagerly rebuild index on first activation
    },
    syntax = {
      enabled = true,     -- enable tree-sitter syntax highlighting
    },
  },

  -- Soft-delete trash
  trash = {
    enabled      = true,   -- true = trash; false = permanent delete (old behaviour)
    max_age_days = 60,     -- auto-purge after N days on startup; 0 = disable
  },

  
  keymaps = {
    -- Note operations
    new_note         = "<leader>nn",
    new_journal      = "<leader>nj",
    new_scratchpad   = "<leader>ns",
    rename_note      = "<leader>nr",
    insert_citation  = "<leader>nc",
    goto_citation    = "<leader>ng",
    delete_note      = "<leader>nd",
    link_note        = "<leader>nl",
    follow_link      = "gf",
    backlinks        = "<leader>nb",
    import_note      = "<leader>ni",
    convert_note     = "<leader>nx",
    promote_note     = "<leader>np",
    transpose_note   = "<leader>nT",
    change_note_type = "<leader>nC",
    set_title        = false,
    add_tag          = false,
    remove_tag       = false,
    -- Navigation
    view_last    = "<leader>vl",
    view_list    = "<leader>va", -- va = view all
    view_sidebar = "<leader>vs",
    view_buffers = "<leader>vb",
    toggle_file_explorer = "<leader>ts",   -- ts = toggle sidebar
    focus_sidebar = false,   -- jump focus directly to sidebar window
    -- PKMMode
    toggle_mode   = false,   -- :PKMMode toggle
    -- Search and browsing
    browse          = "<leader>nf",
    browse_tags     = "<leader>nt",
    -- Markdown editing
    ---- Headers ----
    next_header        = "<leader>Mh",
    header_level_up    = "<leader>M^",
    header_level_down  = "<leader>M_",
    renumber_list      = "<leader>Mr",
    convert_list = false,   -- :PKMConvertList (range or paragraph at cursor)
  },
})
```

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

*This replaces the former single-version "v1.6.0 Implementation Plan". The
reorganised Next Steps are partitioned into the versions below. Discussion-only
items were moved to **Design Questions**; genuinely long-horizon items remain in
**Distant Additions**.*

```
-- NEW:
v1.5.7  PATCH  Correctness & robustness — Ph1  ✅ shipped
v1.5.8  PATCH  Correctness & robustness — Ph2  ────────┐  (no deps)
v1.5.9  PATCH  Correctness & robustness — Ph3          │
v1.6.0  MINOR  Panels & navigation                     │
        Ph1 panel infra + tag panel                    │
          ├─→ Ph2 trash-restore panel                  │
          └─→ Ph3 views panels + sidebar nav           │
              Ph4 picker polish                         │
v1.6.1  PATCH  :PKMViews open-latency (bench-driven) ───┘  (after v1.6.0)
v1.7.0  MINOR  Exportation, note creation & header nav     (no deps)
        Ph1 deep export   Ph2 relative note   Ph3 header navigation
```

Dependency summary: v1.6.0 Ph1 precedes Ph2 and Ph3 (they build on
`panel.lua`); v1.6.1 follows v1.6.0 (it tunes the reworked `:PKMViews`);
everything else floats and may be reordered.

---

#### Operating principles (apply to every version and phase)

1. **One pass per file per phase.** A phase may touch many files, but never the
   same file twice within that phase. All edits to a given file in a phase must
   be mutually compatible, low-risk, and verifiable together, so it is safe to
   apply them all before verifying. When a file would need two incompatible
   passes, the work is split along a seam where each part still functions
   independently, and the parts land in different phases (possibly different
   versions). Different phases **may** re-touch the same file.

2. **A phase groups by safe co-modification, not by category.** Items share a
   phase when their file edits combine cleanly, even if one is a bugfix and
   another a feature. The rule is a ceiling, not a mandate to cram unrelated
   work together.

3. **Each phase fits one response.** A phase is delivered as a single message
   containing every modification it needs, file-by-file, never split across
   messages.

---

#### Standing bug-prevention design rules

- **`winfixbuf` safety net.** Every PKM panel window (sidebar, buffer panel, and
  every panel built on `panel.lua`) sets `winfixbuf = true` immediately after
  its buffer is assigned. This converts the whole class of "a file opened inside
  the panel" bugs (`:Ex`, `:edit`, `:PKMViewEdit` invoked while a panel holds
  focus) from a silent hijack that destroys the panel into a loud, harmless
  error. PKM's own open/create commands additionally redirect through
  `focus_main_win()` for smooth UX; `winfixbuf` catches everything not explicitly
  guarded, including built-ins PKM cannot intercept.
- **Pure-logic-first.** Non-trivial logic (deep-export traversal, case-rename
  identity test, title-propagation diff, citation-edge extraction, header
  targeting, window-slot arithmetic, tag-set relatedness) is written as a pure
  function with explicit inputs/outputs and no editor or filesystem side effects
  in the core. The per-phase test file exercises the pure function; the
  command/UI layer is a thin wrapper.
- **Reuse, don't reimplement.** Resolve citation identifiers through
  `citations.get_citable_items_map()`; redirect panel focus through
  `focus_main_win()`; refresh sidebars through `views.refresh_sidebar_if_open()`;
  propagate identity changes through the existing rename-propagation machinery.
- **Invariants restated per phase.** Each phase names the invariants it must not
  break (e.g. never `index.invalidate` from buffer-only metadata commands; never
  strip backlinks in `trash_note()`; never register `UndoPost`; never run
  `git gc`; always `utils.join` / `utils.normalize` for paths; Telescope checked
  at call time; never optimize without a `bench.lua` baseline). A phase that
  cannot satisfy an invariant is re-scoped, not forced.

---

#### Standing verification protocol

Every phase is verified in this order before its commit:

0. **Push, then sync.** `git commit -a -m "..."` → `git push pkm-nvim dev` →
   `:Lazy sync` (or `:Lazy update`) in Neovim, then restart. Lazy.nvim
   installs this plugin from GitHub, not the local working tree — none of
   the steps below can observe a change that hasn't been pushed and pulled
   first. Tag only after step 5 passes, never before.
1. **Headless sandbox run** against a disposable scratch corpus...
   `Notes` tree:
   `nvim --headless -u test/min_init.lua -c "luafile test/test_<phase>.lua" -c "qa!"`.
   Empirical execution precedes any claim that a fix works.
2. **Per-phase test file** `test/test_<version>_<phase>.lua` asserting pure-logic
   outputs including success, failure, boundary, cycle, empty, and nil inputs.
3. **Static pass** — `luacheck` on changed files, plus the recurring-issue
   checklist (string-concatenated paths; cross-module `M.` references; load-time
   Telescope checks; greedy timestamp patterns; missing
   `update_references_on_rename`; double declarations; template-key/config-key
   mismatches).
4. **Cross-platform spot-check** — path-touching changes exercised against a
   Windows drive path (`P:/Notes/...`) and a WSL mount path (`/mnt/p/Notes/...`)
   in the fixture.
5. **Manual smoke checklist** — the exact `:PKM*` commands to run and their
   expected outcomes.

**Review protocol for returned modifications.** When applied changes are pasted
back, each is checked for: (a) landing only in the named function/region;
(b) header/section/LuaDoc discipline; (c) no second pass on a file already
touched this phase; (d) no forbidden pattern reintroduced; (e) presence and pass
of the phase's test artefacts; (f) behaviour matching the spec. Discrepancies
are reported with root cause before any follow-up edit.

---

#### Correctness & robustness (v1.5.7 – v1.5.9+)

*All bug/completeness fixes from the former Next Steps 4 and 5, plus the view
autorefresh (former Next Steps 2). No new user-facing features. Done first so
later feature work builds on corrected behaviour. Each phase ships as its own
patch version rather than being grouped under one version number; disjoint
file sets per phase still hold — no file is re-touched even across phases.*

**Phase 1 — rename & citation-metadata correctness.** ✅ **Shipped in v1.5.7**
— see `CHANGELOG.md` for the fix descriptions.

| File | Single-pass changes |
|---|---|
| `notes.lua` | (1) `rename_note()`: permit case-only renames — when `filereadable(new)==1`, treat as the same file (not a collision) iff `new` and `old` are the same on-disk object (`vim.loop.fs_stat` `dev`+`ino`; fall back to `utils.normalize`-lowercased equality only on case-insensitive filesystems). (2) Fix the `E13: File exists` forced-write prompt in `rename_note()` and `change_note_type()` when no other edits were made: re-point the buffer to its new name without a colliding `:saveas`/`:write` (e.g. `nvim_buf_set_name` + `writefile` of current lines, then delete the old file), so an otherwise-unmodified rename never prompts. |
| `citations.lua` | Add `propagate_title(note_path)` — pure-ish: rewrite the `title` field of every entry referencing `note_path` in other notes' `cites`/`cited_by` (all four groups), **idempotently** (rewrite a file only when its stored title differs from the current one). Reuses `get_note_type_and_id`, `get_note_title`, `get_citable_items_map`, and the existing per-file write path used by `update_references_on_rename`. |
| `init.lua` | In `setup_sync_autocmds` BufWritePost, after the existing `update_references`, call `citations.propagate_title(current_path)` so a title change reaches citing/cited notes on save — regardless of whether the target notes are open in buffers (the existing modified-buffer-aware write path handles the open case). |
| docs | `CHANGELOG` (Fixed): case-rename, E13 prompt, title cross-update. |

Verification: `test/test_v154_p1.lua` unit-tests the rename identity predicate
(same-inode → allow; distinct file same-case-fold → block; exact equal → no-op)
and the title-propagation diff (no write when unchanged; correct rewrite when
changed). Smoke: rename `prazos`→`Prazos`; rename/change-type a note with no
other edits and confirm no `E13`; change a note's title, `:w`, and confirm
citing notes' metadata now shows the new title.

Invariants: `set_title()` stays buffer-only (no `index.invalidate`); title
propagation writes *other* files (like citation sync), never re-points the
current buffer's index outside the normal BufWritePost path; paths via
`utils.normalize`/`utils.join`.

Commit:

```
fix: case-only rename, E13 write prompt, and title cross-update

- notes: allow case-only renames via same-object identity check; eliminate the
  spurious E13 forced-write on unmodified rename / change-type
- citations: propagate_title() rewrites the title field in referencing notes,
  idempotently; runs on BufWritePost so title edits reach cites/cited_by
- init: trigger title propagation in the save-sync autocmd
- docs: changelog
```

**Phase 2 — panel window safety & view-layer completeness.** ✅ **Shipped
in v1.5.8** — see `CHANGELOG.md` for the fix descriptions.

| File | Single-pass changes |
|---|---|
| `views.lua` | (1) `open_sidebar`: set `winfixbuf = true` on the sidebar window after `nvim_win_set_buf`, alongside the existing `winfixwidth` block. (2) After successful view creation (`M.save`/`M.save_subproject` success path and/or the `:PKMViewNew` handler completion) call `M.refresh_sidebar_if_open()`, then restore focus to the window active before the command. (3) In `rename_view_prompt` and `reparent_view_prompt`, scan `config.projects` for any entry whose `parent == old_name`; if found, emit an advisory `WARN` (never block) — closes the "consistent view renaming" gap the plugin cannot otherwise fix (config.lua is not safely rewritable). (4) Help-float/`?` and header-hint audit: add every registered-but-undocumented key, at minimum `T` (filename/title toggle). (5) Verify whether residual flat `_sidebar_*` globals coexist with the per-tab `_tabs` state; remove if confirmed dead (clean removal over latent code). |
| `ui.lua` | (1) `toggle_bufpanel`: set `winfixbuf = true` after the panel buffer is assigned. (2) Header-hint audit: buffer panel's own header line is missing `D`/`r`/`T` (all three are live keymaps); extend to `Dforce Wclose Ttoggle` or similar. Also audit the fallback browse/recent/orphans panels. |
| `commands.lua` | Complete `focus_main_win()` coverage on every PKM open/create command registered here; the `winfixbuf` net covers un-guardable cases (`:Ex`). |
| docs | `CHANGELOG` (Fixed + Changed): panel hijack; view autorefresh; view-rename config warning; helpline audit. |

Verification: `test/test_v154_p2.lua` asserts the view-rename config-scan
detects a stale `parent` and warns without blocking. Smoke: from the sidebar
run `:Ex`/`:PKMViewEdit` and confirm a harmless error (not a hijack); create a
view and confirm the sidebar refreshes with focus returned; confirm `T` in `?`
help.

Invariants: `winfixbuf` set after `nvim_win_set_buf`; sidebar leftmost invariant
untouched.

Commit:

```
fix: panel buffer hijack, view-create refresh, and rename consistency

- views: winfixbuf on sidebar; autorefresh + focus restore on view creation;
  advisory warning when a config.lua subproject's parent is renamed/reparented;
  helpline audit (T toggle et al.); drop residual global sidebar state if dead
- ui: winfixbuf on buffer panel; fallback-panel hint audit
- commands: complete focus_main_win coverage on panel-invoked open commands
- docs: changelog
```

**Phase 3 — multi-line highlighting.** ✅ **Shipped in v1.5.9**

| File | Single-pass changes |
|---|---|
| `syntax.lua` | `PKMMetaComment` migrated from `matchadd()` (window-scoped, hard single-line limitation — not a regex problem, a Vim/Neovim platform constraint) to buffer-scoped extmarks (`nvim_buf_set_extmark`, natively multi-line via `end_row`/`end_col`). Pure-logic scanner (`find_meta_comments`) finds `((...))` spans — including across line breaks, via Lua string patterns' `.` matching newline — with a `MAX_META_COMMENT_LINES = 50` cap bounding the blast radius of a stray unmatched `((`. Rescanned on `enable()`, on `BufWritePost`, and (debounced, 150ms) on `TextChanged`/`TextChangedI`. `PKMCitation` unchanged — inherently single-line, `matchadd()` remains correct and simpler there. |
| `keymaps.lua` | `PKMNetrwFixes` augroup (pre-existing, v1.5.1): added a `FileType netrw` guard detecting netrw loading into a `winfixbuf`-protected PKM panel window (sidebar/buffer panel) via the `winfixbuf`+`winfixwidth`/`winfixheight` option signature — `winfixbuf` alone doesn't block netrw's initial takeover of an unmodified buffer's window (confirmed via netrw's own docs: "the browsing window will take over that window" when unmodified), only its *subsequent* internal navigation, which is too late. Correction is deferred via `vim.schedule` rather than run synchronously, since the guard fires nested inside netrw's own still-executing command — synchronous mutation there was corrupting netrw's in-flight setup (empty listings) and, as a downstream consequence, briefly resurfacing the buffer-panel sole-window bug. |
| docs | `CHANGELOG` (Fixed). |

Not applicable, contrary to original plan:
- `queries/markdown/highlights.scm` — meta-comment highlighting was never
  tree-sitter-query-based; it's pure Lua/API. No query changes needed.
- ATX/setext headers — already correctly span multiple lines natively, since
  tree-sitter node spans were never subject to `matchadd()`'s single-line
  limitation in the first place (confirmed via the file's own pre-existing
  "Known behaviour" comment on setext headings). No fix was ever needed here.
- `after/syntax/markdown.vim` — multi-line meta-comments are PKMMode-only by
  decision (matching citations, which were also always PKMMode-only); the
  Vimscript fallback's two existing rules (parenthesis-list markers, indented
  blockquotes) are unrelated and untouched.

Verification: pure-logic scanner tested standalone (single-line match,
two-line span, three-line span ending exactly at end-of-line, two separate
comments, no-comment case, unmatched-`((`-capped-by-MAX_LINES, within-cap
multi-line still matches — 7/7 passing). Smoke: open a note with a
multi-line `((...))` comment under PKMMode and confirm it highlights
immediately on open (not just after an edit or save); confirm a stray
unmatched `((` doesn't paint the rest of the document.

Invariants: `PKMCitation`'s `matchadd()` mechanism untouched; tree-sitter
`parser:parse()` still called synchronously in `TextChanged`/`TextChangedI`
(the meta-comment rescan added to that same autocmd is separately debounced,
not synchronous, to avoid the O(n)-per-keystroke cost the injection override
was written to prevent).

(Also: telescope_scoped_search_picker/float_scoped_search, added as a
standalone fix before this phase, target M.list_views() directly for their
back-navigation — repoint or replace once the views panel lands.)

Commit:

```
fix: multi-line meta-comment highlighting via extmarks

- syntax: PKMMetaComment migrated from window-scoped matchadd() (hard
  single-line limitation) to buffer-scoped extmarks (natively multi-line);
  pure-logic scanner with a stray-unmatched-(( blast-radius cap; rescanned
  on enable/save/debounced-text-change
- confirmed unnecessary: highlights.scm query changes (mechanism was never
  query-based), header multi-line support (already correct natively via
  tree-sitter node spans), after/syntax/markdown.vim changes (meta-comments
  are PKMMode-only by decision, matching citations)
- test: pure-logic scanner, 7 cases including multi-line boundary and
  blast-radius cap
- docs: changelog
```

---

#### v1.6.0 (MINOR) — Panels & navigation

*The interface overhaul from the former Next Steps 1. Introduces the shared
panel infrastructure and every panel/sidebar-navigation feature. **Recommended
Option A** — a shared `panel.lua`, validated by porting the existing buffer
panel onto it before new panels are built. If Option B (per-panel copies) is
chosen, drop `panel.lua`; Phase 1 becomes the tag panel alone and Phases 2–3
each carry their own skeleton — phase boundaries and commits are otherwise
unchanged.*

**Phase 1 — panel infrastructure, buffer-panel port, and tag panel.**

| File | Single-pass changes |
|---|---|
| `panel.lua` *(new)* | `panel.create({ name, build_lines, keymaps, filetype, … }) → { open, close, toggle, refresh, is_open }`. Encapsulates per-tab state (`_tabs`/`get_tab()`), a scoped augroup, refresh-on-event, buffer-local keymaps, the `ensure_main_window()` layout guard, and `winfixbuf`. Full module header, section separators, LuaDoc per export. |
| `ui.lua` | Port `toggle_bufpanel` onto `panel.create` (behaviour-preserving). Add the **tag panel**: searchable, scrollable tag list replacing the `vim.ui.select`/`input` flow for `:PKMAddTag`/`:PKMRemoveTag`; selection mutates the current buffer's frontmatter only via `citations.add_tag`/`remove_tag` — **no `index.invalidate`**. |
| `commands.lua` | Route `:PKMAddTag`/`:PKMRemoveTag` through the tag panel. |
| docs | `CHANGELOG` (Added). Module map + File Structure gain `panel.lua`. |

Verification: `test/test_v160_p1.lua` asserts buffer-panel parity after the port
(open/close/toggle/refresh, per-tab isolation) and that tag selection performs a
buffer-only mutation (index re-read only on next `:w`). Smoke: buffer panel in
two tabpages; `:PKMAddTag` from a note.

Commit:

```
feat: shared panel infrastructure, buffer-panel port, and tag panel

- panel: generic create() — per-tab state, scoped augroup, refresh-on-event,
  buffer-local keymaps, layout guard, winfixbuf
- ui: port buffer panel onto panel.lua; searchable tag panel (buffer-only
  frontmatter mutation, no index.invalidate)
- commands: route :PKMAddTag/:PKMRemoveTag through the tag panel
- test: buffer-panel parity; tag-panel index contract
- docs: changelog, module map
```

**Phase 2 — trash-restore panel.**

| File | Single-pass changes |
|---|---|
| `trash.lua` | A `panel.create`-based restore panel over the manifest: browse, search, select, restore. **No deletion key of any kind** — emptying stays exclusive to `:PKMEmptyTrash` (typed confirmation retained). Restore reuses `restore_note` (backlinks intact). |
| `commands.lua` | Route `:PKMRestoreNote` through the panel. |
| docs | `CHANGELOG` (Added). |

Verification: `test/test_v160_p2.lua` restores an entry from a scratch manifest
and asserts the file returns, the manifest shrinks, and no destructive key is
bound. Smoke: delete then restore a note; confirm backlinks survive.

Invariants: `trash_note()` never strips backlinks.

Commit:

```
feat: trash-restore panel

- trash: browse/search/restore panel over the manifest; no deletion key
  (empty stays exclusive to :PKMEmptyTrash with typed confirmation)
- commands: route :PKMRestoreNote through the panel
- test: restore round-trip; no destructive key
- docs: changelog
```

**Phase 3 — views panels and sidebar window navigation.**

| File | Single-pass changes |
|---|---|
| `views.lua` | (1) **Views panel** (extends `:PKMViews`) on `panel.create` with keys to invoke `:PKMViewNew`/`:PKMViewUpdate`; **no deletion key**. (2) **View-deletion panel** (separate by design): browse → select → **confirm before delete**. (3) **Sidebar key** to open the views panel. (4) **`N<CR>`** — ✅ already correct as shipped; no change. Counts only
real editing windows, left→right, opens in the Nth when it exists. `N`
beyond the count warns ("no window N, only M") rather than auto-creating —
deliberately kept over the original auto-create plan: this is a
high-frequency action, and silently altering the window layout on a
miscounted N is worse than a no-op with a clear message. `<C-v>` (item 5)
remains the explicit, deliberate way to add a window.(5) **`<C-v>` repurposed**: insert one new window immediately right of the sidebar, shifting existing windows right — the insert-before complement to `N<CR>`. No `<C-CR>` binding (terminal keycode reliability). |
| `commands.lua` | Route `:PKMViews`/`:PKMViewDelete` through the panels; retain `:PKMViewNew`/`:PKMViewDelete` as residual optional-arg commands. |
| `config.lua` | Default keymap for "open views panel in sidebar" (default `false`). |
| `keymaps.lua` | Wire that keymap when set. |
| docs | `CHANGELOG` (Added). |

Verification: `test/test_v160_p3.lua` unit-tests the window-slot arithmetic (the
"`9<CR>` with one window behaves like `2<CR>`" case; zero-windows; exclude-panels
filter). Smoke: from the sidebar, `2<CR>` then `9<CR>` (no window explosion);
`<C-v>` inserts left-adjacent to editors with the sidebar still leftmost; use the
views and deletion panels (confirm the delete prompt).

Invariants: never `topleft` for the second split; sidebar leftmost; deletion
always confirmed.

Commit:

```
feat: views panels and sidebar window navigation

- views: views panel (create/update keys, no delete key); separate
  view-deletion panel with confirm-before-delete; sidebar key to open it;
  N<CR> opens or creates exactly the Nth editing window (rightbelow, never
  topleft); <C-v> inserts a window right of the sidebar
- commands: route :PKMViews/:PKMViewDelete through panels; residual commands kept
- config/keymaps: opt-in sidebar→views-panel key
- test: window-slot arithmetic; panel lifecycle
- docs: changelog
```

**Phase 4 — picker polish.**

| File | Single-pass changes |
|---|---|
| `telescope.lua` | (1) Relative-split actions for `browse` and the views pickers via `attach_mappings` (matching the existing `<C-v>`/`<C-x>`/`<C-t>` convention): open the selection in a split right or left of the invocation window. Capture `nvim_get_current_win()` **before** opening the picker; if it is `pkm-sidebar`, disable "left"; if it no longer exists at selection, "right" falls back to the rightmost real editing window and "left" stays unavailable. Plain Ctrl+letter bindings only (avoid `<C-h>`/`<C-l>` and Shift+Ctrl). (2) Diagnose and fix the `:PKMViews`→`:PKMBrowse` console flash (reproduce live first). |
| `ui.lua` | `vim.ui.select` fallback for the relative-split actions (a one-line follow-up prompt after selection). |
| docs | `CHANGELOG` (Added + Fixed). |

Verification: `test/test_v160_p4.lua` unit-tests invocation-window capture and
fallback (sidebar → left disabled; vanished window → right-fallback). Smoke:
split-right and split-left a `:PKMBrowse` selection from a note window and from
the sidebar; toggle `:PKMViews`→`:PKMBrowse` and confirm no flash.

Commit:

```
feat: relative-split picker actions and smoother picker handoff

- telescope: open selection in a split left/right of the invocation window
  (sidebar disables left; vanished-window fallback for right); fix the
  :PKMViews->:PKMBrowse console flash
- ui: vim.ui.select fallback split mechanism
- test: invocation-window capture and fallback logic
- docs: changelog
```

---

#### v1.6.1 (PATCH) — `:PKMViews` open latency

*Former Next Steps 6. Bench-gated performance fix, placed after v1.6.0 so it
tunes the reworked `:PKMViews` rather than code about to be replaced. If
diagnosis reveals a root cause independent of the views picker (e.g. a cold
index build on first activation), the fix may be pulled forward as a standalone
patch instead.*

| File | Single-pass changes |
|---|---|
| `bench.lua` | If needed, a targeted bench for the views-open path (reuse `views_suite`/`baseline`). Developer-only. |
| `views.lua` **or** `index.lua` | The fix, chosen **after** measurement. Candidates: pre-warm/reuse the index so the first `:PKMViews` does not pay a cold build; memoise `match_all` per view within an open (the `_match_cache` idea, Distant Additions 4) if the bench attributes the cost there. Exactly one of these files is touched, per the diagnosis. |
| docs | `CHANGELOG` (Fixed/Changed) with the measured before/after; `bench.baseline()` numbers recorded. |

Verification: run `bench.baseline()` and the views-open bench on the real corpus
**before** any edit (mandatory — never optimize blind), then again after, and
record both. Smoke: open `:PKMViews`/`<leader>va` on the ~600-note corpus and
confirm sub-perceptible latency.

Invariants: no correctness change to view results; measurement precedes
optimization.

Commit:

```
perf: eliminate :PKMViews first-open latency

- bench: measured the views-open path on the real corpus (before/after recorded)
- <views|index>: <the diagnosed fix — pre-warm index / memoise match_all>
- docs: changelog with benchmark numbers
```

---

#### v1.7.0 (MINOR) — Exportation, note creation, and header navigation

*Three independent features from the former Next Steps 1 and 3 and Distant
Additions 1.2, across disjoint primary files. Grouped into one minor because
each is small and self-contained; they may equally ship as separate minors if
preferred.*

**Phase 1 — deep export.**

| File | Single-pass changes |
|---|---|
| `export.lua` | (1) `read_citation_edges(path)` — pure: read frontmatter via `get_file_data`, return `{ cites = {ids…}, cited_by = {ids…} }` unioning all four groups. (2) `collect_deep(seed_paths, opts)` — pure BFS with separate per-direction depth counters (`cites_depth` default 2, `cited_by_depth` default 0; 0 = no traversal), cycle detection, identifiers→paths via `citations.get_citable_items_map()`; returns the deduplicated, sorted union (seeds included). (3) A deep-export entry that prompts for mode + depths, then hands the union to `export_direct`. |
| `commands.lua` | Extend the `:PKMExport` flow with a simple-vs-deep choice and the two depths, using native `vim.ui.select`/input (small fixed choice set stays native). |
| docs | `CHANGELOG` (Added); note defaults 2/0. |

Verification: `test/test_v170_p1.lua` builds the worked example (1 cites 2/4/5;
5→7; 7→8; 1 cited_by 2/3/6) and asserts the default run yields {1,2,4,5,7} and
not {3,6,8}; plus 2-node cycle termination; plus `cited_by_depth>0` pulls citers;
plus all four groups followed. Smoke: deep-export a note citing across
journal/bib types.

Invariants: `export.lua` stays read-only; only `require`s `citations`/`yaml`.

Commit:

```
feat: deep export across the citation graph

- export: pure BFS over cites/cited_by with per-direction depth limits
  (cites=2, cited_by=0) and cycle detection; id resolution reuses
  citations.get_citable_items_map; all four citable groups traversed
- commands: simple-vs-deep choice and depth selection in the export flow
- test: worked-example traversal, cycle termination, multi-type edges
- docs: changelog
```

**Phase 2 — relative note (new note sharing the current note's tags).**

| File | Single-pass changes |
|---|---|
| `notes.lua` | `create_relative_note()` — create a new consolidated note pre-seeded with the current note's `tags` (so it lands in the same view when one exists). Reuses `create_new_note`'s numbering/template path; only the tag seeding is new. A "relative" note, since tags — not a rigid view — define the relationship (see Design Questions: note relationships). |
| `commands.lua` | `:PKMNewRelative` (or equivalent) invoking it. |
| `keymaps.lua` | Wire the keymap when set. |
| `config.lua` | Default keymap (default `false`). |
| docs | `CHANGELOG` (Added). |

Verification: `test/test_v170_p2.lua` asserts the new note's frontmatter carries
exactly the source note's tags. Smoke: from a tagged note, create a relative
note and confirm it appears in the same view.

Commit:

```
feat: create a relative note sharing the current note's tags

- notes: create_relative_note() seeds the new note with the source tags so it
  falls within the same view when one exists
- commands/keymaps/config: :PKMNewRelative and opt-in keymap
- test: tag inheritance
- docs: changelog
```

**Phase 3 — header navigation.**

| File | Single-pass changes |
|---|---|
| `markdown.lua` | Add **any-level** header navigation (jump to next/prev ATX heading regardless of level) via a pure `find_heading_target(lines, cursor, opts) → lnum?`. Neovim already provides **same-level** header motion natively, so PKM adds only the any-level complement; document the native integration. Update the module Public-API header and LuaDoc. *(Optional bundling: Distant Additions 1.8's "global next_header" also lives in `markdown.lua` and could ride this same pass if promoted.)* |
| `commands.lua` | `:PKMNextHeader`-family navigation commands. |
| `keymaps.lua` | Wire navigation keymaps when set. |
| `config.lua` | Navigation keymap defaults — consistent with the native same-level motion and existing markdown keymaps (default `false`). |
| docs | `CHANGELOG` (Added). Record the PKM↔Neovim native-motion integration and note that a previously-created same-level command was dropped in favour of the native one. Promote the "different/any-level header" bullet of Distant Additions 1.2 into completed scope; restate that list-component and block navigation remain deferred pending the markdown conventions. |

Verification: `test/test_v170_p3.lua` runs `find_heading_target` over a
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

1. **Note relationship protocol.** There is no model for rigid relations such as
   "parent" note: because notes cite each other freely, a "parent" can be cited
   by a note its "child" cites, so hierarchy is ill-defined and possibly cyclic.
   A rigid nomenclature is likely unnecessary. A cheap, well-defined alternative
   is **tag-set relatedness** — notes sharing more tags are more related (e.g. a
   Jaccard or overlap measure over tag sets), with exact-tag-set matches most
   related. This is attractive because it is pure, cheap, and feeds directly
   into the relevance-ranking ideas in Distant Additions 9 (ordering search
   results and sidebar entries). Recorded as a design framework, not a plan; the
   "relative note" feature (v1.7.0) already embodies the tag-relatedness view of
   relationship at creation time.

2. **A note type for describing other notes.** Some notes describe the rationale
   and usage of other notes — the author's markdown consensus is part of the
   *system*, but a user may want their own consensuses per project/view, or a
   guide explaining what a "question bank" note type is for. Adding a genuine new
   frontmatter `type` is a **major conceptual change** (it touches templates, the
   `type:` filter predicate, `index.note_type`, syntax, and the citation
   groups), even if the code delta is small. **Recommendation:** do *not* add a
   new type initially. Model these as an existing type (`note` or `agg`)
   distinguished by convention — a `role`/`meta`/`guide` tag or a naming
   convention — and only promote to a real type if the convention proves
   insufficient in daily use. This keeps the type system minimal (Philosophy §2,
   §7) and is fully reversible. Discussion-only; no implementation.

3.  **Exportation improvements:**
    -   AI exportation context protocol: A way to ship files that tell an
        AI/LLM how to interpret a set of notes (the markdown conventions being
        one example; per-view or ad-hoc directives being others).
        **Recommendation:** for the per-view case, the author suggests using a
        subview for "meta files" (e.g. named "_meta"). The user can decide
        whether to create it or not. All we need to do is ensure that exporting
        a view also exports all its subviews (which is already expected
        behavior). The default (general) exportation should also allow the user
        to select (or write) which views they want to export, which tags, and
        which titles or title parts, thus allowing for a "composed" export. With this,
        we only need a specific export command that gives the user the options: "export current note, export
        current view, customized export".
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
    3.  Sidebar: Now has a keymap that switches it into the current "bookmark
        bar" (for the active window). There should be a keymap to do so within
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
4.  **Misc** (currently set to be done in the active development's Phase X, meaning
the LLM assistant should decide when it is best to implement them):
    -   Pressing `zE` to expand folds makes the system no longer detect the yaml
        fold in a note. Saving the note resumes normal behavior. `za` and `zm` do
        not cause issues (but they are affected until a new save or a note reopen
        if the fold stops being detected due to `zE`).
    -   Pressing `gf` on a note citation only follows the link when such citation
        is the "full citation" (present in the yaml citation block). The
        "shortened" citation ([note xxxx]) that shows in text does not allow link
        following. There should be a way to follow a link without having to go up
        to the metadata manually before doing so.
    
    -   Pressing `u` on normal mode to undo has been fixed to correctly alter the
        timestamp while also reverting the modification made. However, the cursor
        ends up on the timestamp, making it hard to follow the changes (that is,
        the user needs to manually search for whatever was undone). The cursor
        should land on the last-undone part (e.g. a text that was regenerated,  an
        empty character/line that was left after undoing an input, and so on).
    
    -   Being cited by another note while open on a buffer will sometimes create
        the need for a forced save, even if nothing else has been changed (check if
        this is mentioned already in some existing version/phase).
    
    -   The files opened in the buffer panel (`<leader>vb`) should display in the following
    order:
        1. First, the files currently open on the lowest-numbered window (w1 on top, then w2, etc.).
        2. As for the rest, the last-opened files. An example of the expecte
           behavior is that opening the first file on w1 will put it on top, then
           opening a second file on w2 will put it on the second place, then
           opening a third file on w1 will put it on top and make the previous
           top-place occupant ("file 1", previously opened on w1) go to the third
           place (which is the first place among the "recently opened, but not
           currently opened in any window"). Then, opening a fourth file on w1 will
           put that on top and cause "file 3", which had been placed at w1, to go
           to the third place, and the previous occupant of the third place ("file
           1") to move to the fourth place (this is the second place among
           "recently opened, but not currently opened in any window) since "file 1"
           was the first file to be opened, meaning "file 3" was opened more
           recently than it.
        3. Reopening any files (by pressing `<CR>` on their buffers or any other
           means) should reorder them accordingly.
        
        The final result is a sequence of opened buffers per window, followed by a
        sequence of opened buffers that are not on any window, ordered from the
        most recently opened to the last recently opened, with a dynamic behavior
        that will change the list as the user interacts with those files. This idea
        is meant to improve user experience, since the more relevant (currently / recently opened)
        files will be on top, and since the user will know to look for files that have
        not been recently opened at the bottom of the list.
    
        This is a per-session behavior. It is not meant to store "recently opened" across
        sessions. Such behavior is more complex and, if we decide to implement it, it will
        not be based on the buffer panel, since the buffer panel is meant to be used
        to organize the current session only.
    
    -   The final confirmation before creating a view/subview is unecessary. We
        should either remove it or change it to a single keypress (`<CR>`)
        instead of making the user type `yes`. Leave such multistep processes
        with confirmations for dangerous tasks (views are safe to create and
        the process can easily be reverted by deleting the view, if it was
        created by accident, or by updating it, if it was created with a wrong
        parameter).

    -   bugfix: syntash highlighting recognizes numbers that start any line as
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
    Bench showed 3.1 ms/view at 10k notes; not warranted at current scale.
    Revisit at ~5k notes or ~200+ views with observed latency. **Note:** the
    v1.6.1 latency investigation may adopt this if the bench attributes the
    `:PKMViews` cost to repeated `match_all`.

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
