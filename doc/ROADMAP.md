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
│   ├── PKM_ROADMAP.md  # This file
│   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
│   ├── PHILOSOPHY.md   # Design principles (non-negotiable constraints)
│   └── CHANGELOG.md    # Version history
├── test/               # Test files
└── README.md
```

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
  -- Prefer :PKMViewNew / views.json for views that change frequently.
  projects = {
    clinic = 'tag:medicine AND tag:protocol AND NOT tag:draft',
    -- Subproject example:
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
      sidebar  = true,    -- open sidebar on activation
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

v1.6.0 implementation underway — see "v1.6.0 Implementation Plan" below.

---

### v1.6.0 Implementation Plan

#### Operating principles for this release

1. **One pass per file per phase.** A phase may touch many files, but never the
   same file twice. When a feature would require two passes over one file, it
   is split along a seam where each part still functions independently, and the
   parts land in different phases. Different phases *may* re-touch the same file
   — the constraint is per-phase, not global.

2. **A phase groups by safe co-modification, not by category.** If several
   items can be applied to a file in one coherent, low-risk pass, they share a
   phase even if one is a bugfix and another a feature. The per-file rule is a
   *ceiling*, not a mandate to cram unrelated work together: where combining
   would bloat a review or mix unrelated regions of a file, the items are kept
   in separate phases instead.

3. **Each phase fits one response.** Implementation of a phase is delivered as a
   single message containing every modification that phase needs. The
   views-panel phase (E) is the heaviest; it is delivered file-by-file *within
   one response*, never split across messages.

4. **Critical path is short.** Only the panel phases depend on each other
   (C → D, C → E). Every other phase floats and may be reordered freely.

```
A  bugfixes + view-layer completeness ─┐  (no deps)
B  deep export ────────────────────────┤  (no deps)
C  panel infra + buffer-panel port + tag panel
        │
        ├─→ D  trash-restore panel
        └─→ E  views panels + sidebar window navigation
F  picker polish (relative splits, handoff flash) ─┐ (no deps)
G  header navigation motions ──────────────────────┤ (no deps)
H  note-taking conventions spec (docs only) ───────┘ (no deps, optional)
```

---

#### Standing bug-prevention design rules (apply to every phase)

- **`winfixbuf` safety net.** Every PKM panel window (sidebar, buffer panel,
  and every panel built on `panel.lua`) sets `winfixbuf = true` immediately
  after its buffer is assigned. This converts the entire class of "a file
  opened inside the panel" bugs (`:Ex`, `:edit`, `:PKMViewEdit` invoked while a
  panel holds focus) from a *silent hijack that destroys the panel* into a
  *loud, harmless error*. PKM's own open/create commands additionally redirect
  through `focus_main_win()` for a smooth UX; `winfixbuf` catches everything
  not explicitly guarded, including built-ins PKM cannot intercept.
- **Pure-logic-first.** Any non-trivial logic (deep-export traversal,
  case-rename identity test, citation-edge extraction, header targeting,
  window-slot arithmetic) is written as a pure function taking explicit inputs
  and returning explicit outputs, with no editor or filesystem side effects in
  the core. This is what the per-phase test file exercises; the command/UI layer
  is a thin wrapper.
- **Reuse, don't reimplement.** Resolve citation identifiers through
  `citations.get_citable_items_map()`; redirect panel focus through the existing
  `focus_main_win()`; refresh sidebars through `views.refresh_sidebar_if_open()`.
  No parallel implementations of solved problems.
- **Invariants restated per phase.** Each phase's spec lists the project
  invariants it must not break (e.g. *never* `index.invalidate` from
  buffer-only metadata commands; *never* strip backlinks in `trash_note()`;
  *never* register `UndoPost`; *never* run `git gc`; always `utils.join` /
  `utils.normalize` for paths; Telescope checked at call time). A phase that
  cannot satisfy an invariant is wrong as specified and is re-scoped, not
  forced.

---

#### Standing verification protocol (apply to every phase)

Every phase is verified in this order before its commit:

1. **Headless sandbox run.** Execute the phase's new/changed code paths in
   headless Neovim against a disposable scratch corpus, never the live `Notes`
   tree. Pattern:
   `nvim --headless -u test/min_init.lua -c "luafile test/test_<phase>.lua" -c "qa!"`.
   Empirical execution precedes any claim that a fix works.
2. **Per-phase test file.** Each phase ships `test/test_<phase>.lua` asserting
   the pure-logic outputs (success and failure cases, boundary conditions,
   cycle/empty/nil inputs). Pure functions make this possible without a live
   editor.
3. **Static pass.** `luacheck lua/pkm/<changed files>` for undeclared globals,
   shadowed/duplicate locals, and unused variables. Plus the project's recurring
   issue checklist: string-concatenated paths, cross-module `M.` references,
   load-time Telescope checks, greedy timestamp patterns, missing
   `update_references_on_rename`, double declarations, template-key/config-key
   mismatches.
4. **Cross-platform spot-check.** Any path-touching change is exercised against
   a Windows-style drive path (`P:/Notes/...`) and a WSL mount path
   (`/mnt/p/Notes/...`) at least in the test fixture.
5. **Manual smoke checklist.** The phase spec names the exact `:PKM*` commands
   to run by hand and the expected outcome of each.

**Review protocol for returned modifications.** When the applied changes are
pasted back, each is checked against six points: (a) the edit landed in the
named function/region and nowhere else; (b) file-header, section-separator, and
LuaDoc discipline preserved; (c) no second pass introduced on any file already
touched this phase; (d) no forbidden pattern reintroduced (see invariants);
(e) the phase's test and verification artefacts are present and pass; (f) the
observable behaviour matches the spec. Discrepancies are reported with the root
cause before any follow-up edit is proposed.

---

#### Distant Additions triage for v1.6.0

Folded in (implementable now, backward-compatible, independently functional):

- **Phase G — header navigation motions** (a scoped subset of *Distant
  Additions 1.2*). Same-level and any-level header jumps only. List-component
  and block navigation are **deferred**: they depend on the list-prefix and
  block conventions in *Distant Additions 1.3 / 2.1*, which are not yet settled.
- **Phase H — note-taking conventions specification** (the documentation
  portion of *Distant Additions 1.1*). Doc-only, zero code risk; it serves the
  AI-facilitation principle by giving collaborators a written convention.
  Optional and lowest priority — may slip to v1.7.0 without affecting anything
  else.

Deferred, with reason:

- *DA 1.3 / 1.4 / 1.5 / 1.6, 2.1, 4* (extended list prefixes, table formatter,
  custom autowrap, table motion, markdown conventions that drive syntax) —
  interdependent and unsettled; require the conventions spec (H) to land first
  and a syntax-mechanism decision. Out of scope for v1.6.0.
- *DA 7, 9.1* (broaden markdown features to non-PKM files; on/off toggles) —
  PHILOSOPHY §7 requires customisation to be designed *after* defaults are
  stable; the syntax/markdown defaults are still new (v1.5.x). Defer.
- *DA 8.2* (config-aware global help panel) — depends on the customisation
  surface above. The discoverability gap it targets is partially closed by the
  helpline audit in Phase A.
- *DA 2, 3, 5, 6, 8.1* (preview, persistent index, review queue, ASCII diagrams,
  explorer layout customisation) — already long-term in this roadmap; unchanged.

---

#### Phase A — Bugfixes and view-layer completeness

*Folds in Next Steps 2, 4, 5, and the former Phase 1/Phase 5. No new
infrastructure. Highest priority: every item is an active defect or a small
completeness gap.*

| File | Single-pass changes |
|---|---|
| `notes.lua` | `rename_note()`: permit case-only renames. Robust form: when `filereadable(new)==1`, treat it as the same file (not a collision) iff `new` and `old` are the **same on-disk object** — compare `vim.loop.fs_stat` `dev`+`ino` when available, falling back to `utils.normalize`-lowercased equality only on case-insensitive filesystems (`is_windows`, or WSL on a `/mnt/<drive>` mount). Distinct files that merely differ in case on a case-sensitive FS still collide correctly. |
| `views.lua` | (1) After successful view creation (`M.save` / `M.save_subproject` success path, and/or the `:PKMViewNew` handler's completion) call `M.refresh_sidebar_if_open()`, then restore focus to the window active before the command ran. (2) In `rename_view_prompt` and `reparent_view_prompt`, before completing, scan `config.projects` for any entry whose `parent == old_name`; if found, emit an advisory `WARN` (never block). (3) `open_sidebar`: set `winfixbuf = true` on the sidebar window, after `nvim_win_set_buf`, alongside the existing `winfixwidth` block. (4) Helpline/`?` help-float audit: add every registered-but-undocumented key — at minimum `T` (filename/title toggle); add whatever the audit turns up. (5) **Verify** whether residual flat `_sidebar_*` globals/helpers coexist with the per-tab `_tabs` state; if confirmed dead, remove in this same pass (clean removal over leaving latent code). |
| `ui.lua` | (1) Buffer panel (`toggle_bufpanel`): set `winfixbuf = true` after the panel buffer is assigned. (2) Header-hint audit for the fallback browse/recent/orphans panels — match hints to keys actually registered. |
| `commands.lua` | Audit every PKM open/create command registered here for `focus_main_win()` coverage; add it to any that open a buffer and currently lack it. (The `winfixbuf` net in `views.lua`/`ui.lua` is the structural fix for un-guardable cases such as `:Ex`; this pass only ensures PKM's own commands additionally redirect smoothly.) |
| docs | `CHANGELOG` (Fixed + Changed). `ROADMAP` Configuration Reference: replace the `projects` comment block with the config.lua-views caveat (cannot be renamed/deleted via PKM commands; subprojects discouraged there), and annotate the `ringforge` example as a discouraged pattern rather than deleting it. `LLM_CONTEXT` if any invariant phrasing changes. |

Verification specifics: `test/test_phaseA.lua` unit-tests the rename identity
predicate (same-inode → allow; different file same-case-fold → block; exact
equal → no-op). Smoke: rename `prazos`→`Prazos`; create a view and confirm the
sidebar updates with focus returned; from the sidebar run `:Ex` and confirm a
harmless error (not a hijack); confirm `T` appears in `?` help.

Invariants in play: paths via `utils.normalize`/`utils.join`; no
`index.invalidate` added to buffer-only paths; `winfixbuf` set *after*
`nvim_win_set_buf`.

Commit:

```
fix: case-only rename, panel buffer hijack, and view-create refresh

- notes: allow case-only renames via same-object identity check, case-sensitive
  filesystems still collide on distinct files
- views: winfixbuf on sidebar; autorefresh + focus restore on view creation;
  advisory warning when a config.lua subproject's parent is renamed/reparented;
  helpline audit (T toggle et al.)
- ui: winfixbuf on buffer panel; fallback-panel hint audit
- commands: complete focus_main_win coverage on panel-invoked open commands
- docs: config-reference caveat for config.lua-defined views; changelog
```

---

#### Phase B — Deep export

*Next Steps 3. Fully independent: pure traversal in `export.lua` plus a depth
prompt in `commands.lua`. No change to the copy mechanism — the union path list
feeds the existing `export_direct()`.*

| File | Single-pass changes |
|---|---|
| `export.lua` | (1) `read_citation_edges(path)` — pure: read frontmatter via the existing `get_file_data`, return `{ cites = {ids…}, cited_by = {ids…} }` unioning all four groups (`notes`, `bib`, `journal`, `scratch`) in each direction. (2) `collect_deep(seed_paths, opts)` — pure BFS with **separate per-direction depth counters** (`cites_depth` default 2, `cited_by_depth` default 0; 0 = do not traverse that direction), **cycle detection** via a visited-set (citation graphs are not guaranteed acyclic), resolving identifiers→paths through `require('pkm.citations').get_citable_items_map()`. Returns the deduplicated, sorted union (seeds always included). (3) A deep-export entry that prompts for mode and the two depths, then hands the union to `export_direct(label, paths)`. |
| `commands.lua` | Extend the `:PKMExport` flow (or add a sibling command) to offer **simple vs deep**, and on deep, the two depths — using native `vim.ui.select`/input for this short fixed choice set (per Next Steps 1: small fixed sets stay native UI). |
| docs | `CHANGELOG` (Added). `ROADMAP` mark Next Steps 3 done; note defaults 2/0. |

Verification specifics: `test/test_phaseB.lua` builds the roadmap's worked
example (Note 1 cites 2/4/5; 5→7; 7→8; 1 cited_by 2/3/6) as a fixture and
asserts the default run yields {1,2,4,5,7} and not {3,6,8}; plus a 2-node cycle
terminates; plus `cited_by_depth>0` pulls citers; plus all four group types are
followed. Smoke: deep-export a note with citations across journal/bib types.

Invariants: `export.lua` stays read-only — never writes a note; only `require`s
`citations`/`yaml`, never edits them.

Commit:

```
feat: deep export across the citation graph

- export: pure BFS over cites/cited_by with per-direction depth limits
  (cites=2, cited_by=0 by default) and cycle detection; identifier resolution
  reuses citations.get_citable_items_map; all four citable groups traversed
- commands: simple-vs-deep choice and depth selection in the export flow
- test: worked-example traversal, cycle termination, multi-type edges
- docs: changelog, roadmap
```

---

#### Phase C — Panel infrastructure, buffer-panel port, and tag panel

*Next Steps 1 (foundation). **Recommended Option A** (shared `panel.lua`).
Validates the abstraction by porting the existing buffer panel onto it, then
proves it again by building the first new panel (tag) on it.*

> **If Option B is chosen instead:** drop `panel.lua`; this phase becomes the
> tag panel alone, modelled as a copy-and-adapt of the buffer panel, and the
> later panels (D, E) each carry their own skeleton. Phase boundaries and
> commits are otherwise unchanged.

| File | Single-pass changes |
|---|---|
| `panel.lua` *(new)* | `panel.create({ name, build_lines, keymaps, filetype, … }) → { open, close, toggle, refresh, is_open }`. Encapsulates per-tab state (`_tabs`/`get_tab()`), a scoped augroup, refresh-on-event, a buffer-local keymap set, the `ensure_main_window()` layout guard, and `winfixbuf = true` on the panel window. Full module header, section separators, LuaDoc per export. |
| `ui.lua` | Port `toggle_bufpanel` onto `panel.create` (behaviour-preserving). Add the **tag panel**: searchable, scrollable tag list replacing the current `vim.ui.select`/`input` flow for `:PKMAddTag` (and `:PKMRemoveTag`). Selection mutates the **current buffer's** frontmatter only, via the existing `citations.add_tag`/`remove_tag` — i.e. **no `index.invalidate`** (buffer-only contract preserved). |
| `commands.lua` | Route `:PKMAddTag` / `:PKMRemoveTag` through the tag panel. |
| docs | `CHANGELOG` (Added). `ROADMAP` module map gains `panel.lua`. |

Verification specifics: `test/test_phaseC.lua` asserts the buffer panel's
observable behaviour is unchanged after the port (open/close/toggle/refresh,
per-tab isolation) and that the tag panel's selection calls the buffer-only
mutation without touching the index. Smoke: open the buffer panel in two
tabpages; `:PKMAddTag` from a note, confirm frontmatter changes and the index is
re-read only on the next `:w`.

Invariants: buffer-only metadata commands never call `index.invalidate`;
`winfixbuf` baked into the panel; Telescope (if used by a panel) checked at call
time.

Commit:

```
feat: shared panel infrastructure with buffer-panel port and tag panel

- panel: generic create() — per-tab state, scoped augroup, refresh-on-event,
  buffer-local keymaps, layout guard, winfixbuf
- ui: port buffer panel onto panel.lua; searchable tag panel (buffer-only
  frontmatter mutation, no index.invalidate)
- commands: route :PKMAddTag/:PKMRemoveTag through the tag panel
- test: buffer-panel parity after port; tag panel index contract
- docs: changelog, roadmap module map
```

---

#### Phase D — Trash-restore panel

*Next Steps 1. Depends on C. Disjoint file set from C and E.*

| File | Single-pass changes |
|---|---|
| `trash.lua` | A `panel.create`-based restore panel over the manifest: browse, search, select, and restore via a key. **No deletion key of any kind** — emptying remains exclusive to `:PKMEmptyTrash`, which keeps its typed confirmation. Restore reuses `restore_note` (backlinks already intact). |
| `commands.lua` | Route `:PKMRestoreNote` through the panel. |
| docs | `CHANGELOG` (Added). |

Verification specifics: `test/test_phaseD.lua` populates a scratch
`.pkm-trash/manifest.json`, restores an entry, asserts the file returns and the
manifest shrinks, and asserts the panel exposes no destructive key. Smoke:
delete a note, restore it from the panel, confirm backlinks survive.

Invariants: `trash_note()` never strips backlinks; cleanup stays confined to
`empty()`/`purge_old()`.

Commit:

```
feat: trash-restore panel

- trash: browse/search/restore panel over the manifest; no deletion key
  (empty stays exclusive to :PKMEmptyTrash with typed confirmation)
- commands: route :PKMRestoreNote through the panel
- test: restore round-trip; panel exposes no destructive key
- docs: changelog
```

---

#### Phase E — Views panels and sidebar window navigation

*Next Steps 1 (views) + the sidebar half of Next Steps 1's `<C-v>`/`N<CR>`
items. Depends on C. The heaviest phase: it owns every remaining `views.lua`
sidebar/panel change so that file is touched exactly once. Delivered
file-by-file within a single response.*

| File | Single-pass changes |
|---|---|
| `views.lua` | (1) **Views panel** (extends `:PKMViews`) on `panel.create`: keys to invoke `:PKMViewNew` and `:PKMViewUpdate` from the panel; **no deletion key**. (2) **View-deletion panel** (separate, by design): browse → select → **confirm before delete**, matching the destructive-action pattern of `:PKMEmptyTrash`. (3) **Sidebar key** to open the views panel directly. (4) **`N<CR>` window targeting:** count only real editing windows (exclude `pkm-sidebar`/`pkm-bufpanel`/`netrw`/floats), left→right, anchored right of the sidebar; `N ≤ count` opens in that window; `N > count` (including zero open) creates **exactly one** new window — the next sequential slot — never more; locate the rightmost real editing window and split `rightbelow` (never `topleft`, which could land left of the sidebar). The sidebar stays leftmost. (5) **`<C-v>` repurposed** (not removed): insert one new window immediately right of the sidebar, shifting existing windows right — the insert-before complement to `N<CR>`'s go-to-or-append. No `<C-CR>` binding (terminal keycode reliability). |
| `commands.lua` | Route `:PKMViews` and `:PKMViewDelete` through their panels; retain `:PKMViewNew`/`:PKMViewDelete` as residual commands with optional arguments. |
| `config.lua` | Default keymap for "open views panel in sidebar" (default `false`, opt-in). |
| `keymaps.lua` | Wire that keymap if set. |
| docs | `CHANGELOG` (Added). `ROADMAP` mark the relevant Next Steps 1 sub-items done. |

Verification specifics: `test/test_phaseE.lua` unit-tests the pure window-slot
arithmetic (the "9 with one window open behaves like 2" case; the zero-windows
case; the exclude-panels filter) on a synthetic window list, separate from any
live split. Smoke: from the sidebar, `2<CR>` then `9<CR>` (no eight-window
explosion); `<C-v>` inserts left-adjacent to existing editors with the sidebar
still leftmost; open and use the views panel and the deletion panel (confirm the
delete prompt).

Invariants: never `topleft` for the second split; sidebar leftmost invariant
preserved; deletion always confirmed.

Commit:

```
feat: views panels and sidebar window navigation

- views: views panel (create/update keys, no delete key); separate
  view-deletion panel with confirm-before-delete; sidebar key to open the
  views panel; N<CR> opens or creates exactly the Nth editing window
  (rightbelow, never topleft); <C-v> inserts a window right of the sidebar
- commands: route :PKMViews/:PKMViewDelete through panels; residual optional-arg
  commands retained
- config/keymaps: opt-in sidebar→views-panel key
- test: window-slot arithmetic and panel lifecycle
- docs: changelog, roadmap
```

---

#### Phase F — Picker polish

*Next Steps 1 (picker `<C-v>` left/right; `:PKMViews`↔`:PKMBrowse` flash).
Independent of all panel phases — touches the Telescope/`vim.ui.select` layer,
not the panels.*

| File | Single-pass changes |
|---|---|
| `telescope.lua` | (1) Relative-split actions for `browse` and the views pickers via `attach_mappings` (matching the existing `<C-v>`/`<C-x>`/`<C-t>` convention): "open selection in a split right of the invocation window" and "…left." Capture `nvim_get_current_win()` **before** opening the picker; if that window is `pkm-sidebar`, disable "left" (no-op) for that invocation; if it no longer exists at selection, "right" falls back to the rightmost real editing window and "left" stays unavailable. Use plain Ctrl+letter bindings (avoid `<C-h>`/`<C-l>` and Shift+Ctrl). (2) Diagnose and fix the `:PKMViews`→`:PKMBrowse` console flash (likely a picker-to-picker handoff redraw); reproduce live, then fix. |
| `ui.lua` | `vim.ui.select` fallback equivalent for the relative-split actions (a one-line follow-up prompt after selection). |
| docs | `CHANGELOG` (Added/Fixed). |

Verification specifics: `test/test_phaseF.lua` unit-tests the invocation-window
capture and fallback resolution (sidebar → left disabled; vanished window →
right-fallback) as pure logic. Smoke: from a note window and from the sidebar,
open `:PKMBrowse`, split-right and split-left a selection; toggle
`:PKMViews`→`:PKMBrowse` and confirm no flash.

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

#### Phase G — Header navigation motions

*Distant Additions 1.2, header subset only. Self-contained and
backward-compatible. List-component and block navigation are deferred until the
markdown conventions (Phase H, then a future syntax decision) settle.*

| File | Single-pass changes |
|---|---|
| `markdown.lua` | Note that neovim already implements same-level header
                   navigation, so no special commands are needed for that. The other features will
                   be built in a compatible and intuitive manner considering the default
                   keymapping and, whenever adequate, the same logic as the native same-level
                   header. Previously, we had created a same-level command, which was dropped in favor of the native command. This was not noted, and may cause
                   confusion, so the integration of PKM with vim-native commands should be noted in appropriate locations. |
| `commands.lua` | `:PKMNextHeader`-family navigation commands. |
| `keymaps.lua` | Wire the navigation keymaps if set. |
| `config.lua` | Navigation keymap defaults — consistent with default same-level header and other existing markdown keymaps. |
| docs | `CHANGELOG` (Added). `ROADMAP` promote the DA 1.2 header subset into completed scope; restate that list/block navigation remains deferred. |

Verification specifics: `test/test_phaseG.lua` runs `find_heading_target` over a
fixture with mixed `#`-levels and asserts next/prev and same-level targets at
boundaries (first/last heading, no heading → nil). Smoke: navigate a real note's
headings up/down and same-level.

Invariants: current Neovim API only; pure targeting function; no global state.

Commit:

```
feat: header navigation motions

- markdown: neovim implements same-level header navigation. Add and any-level
  header jumps via a pure find_heading_target; ATX headings only
- commands/keymaps/config: opt-in heading-navigation commands and keymaps
- test: heading targeting over fixtures, including boundaries
- docs: changelog, roadmap (DA 1.2 header subset promoted)
```

---

#### Phase H — Note-taking conventions specification *(optional, lowest priority)*

*Documentation portion of Distant Additions 1.1. Doc-only, zero code risk.
Guides future syntax/formatting work and AI collaboration. May slip to v1.7.0.*

| File | Single-pass changes |
|---|---|
| `doc/CONVENTIONS.md` *(new)* | Written conventions: prefix/indentation spacing (including the long-prefix continuation rule), candidate extended list prefixes, table-type decision and separators, equivalent-name juxtaposition (`AI/LLM`, `não-exaustivo/não-taxativo`). Marked explicitly as *convention guidance*, not yet a syntax contract. |
| docs | Reference the new file from `PHILOSOPHY`/`ROADMAP`; `CHANGELOG` (Added, docs). |

Verification: documentation review only; no code, no test file.

Commit:

```
docs: note-taking conventions specification

- doc/CONVENTIONS.md: spacing/indentation, list-prefix candidates, table
  decisions, equivalent-name juxtaposition; guidance, not yet a syntax contract
- docs: reference from philosophy/roadmap; changelog
```

---

*Sequencing note: A and B may run in either order; C must precede D and E; F, G,
H float. Each phase ends on its commit (`git commit -a -m …`); tags are applied
only after the whole release lands.*

---

### Next Steps

1.  **Improved PKM interface and navigation:** Use UI panels for displaying note
    and view lists, leaving simple native Neovim UI for short and fixed sets of
    choices (like the exportation types described in Next Steps 3)
    -   `:PKMAddTag`: improve UI to show a panel where tags can be chosen and
        searched (similar to the existing browse panels).
    -   Trash: improve `:PKMRestoreNote`'s UI to show a panel where previously
        deleted notes can be browsed and searched (similar to the existing
        browse panels). This panel should allow the user to select notes and
        then press a key to restore them. To avoid any accidental losses,
        deleting notes or recycling the whole trashbin should not be possible
        in this UI for now (that feature remains confined to `:PKMEmptyTrash`,
        which should always prompt the user for confirmation before executing).
    -   `:PKMViewNew` and `:PKMUpdateView` should be incorporated into the
        views panel (`:PKMViews`), which should now also open UI panels similar
        to other browsing and searching panels, but now with a key combination
        for creating and updating views / subviews (that is, for calling
        `PKMViewNew` and `PKMUpdateView`. As a safety measure, do not add a key
        for view deletion in those panels for now.
    -   `:PKMViewDelete` should have its own UI panel, similar to the other
        browsing and searching panels described here. 
    -   `:PKMViewDelete` and `:PKMViewNew` can persist as residual commands
        with an optional arguments.
    -   Add a key to open `:PKMViews` in the sidebar.
    -   `:PKMViews` and `:PKMSearch` toggle: toggling from the first to the
        second is not smooth (a console shows during the transition), make it
        smoother if possible. Helplines are missing for some already
        functioning commads (such as `T` for toggling between title and
        filename display).
    -   using `<c-v>` on a note title/filename on the sidebar correctly opens
        the note on a new vertical buffer. however, by default it creates a
        split on the right. change it to create a split on the left, or create
        a keymap to allow the user to do so, if you think preserving the choice
        on the left is adequate.
    -   Using `#<CR>`, where `#` is a number, correctly opens a file on the #th
        window. However, it only does so if that window already exists.
        Consider allowing it to create that window, if it doesn't exist,
        effectively replacing `<C-v>` and allowing the user to choose between
        any window when opening a file in a new split (this would solve the
        issue presented in the previous point).

2. **PKM new view autorefresh sidebar:** currently, adding a new view with
   `:PKMViewNew` does not autorefresh the sidebar. The new view appears only
   after navigating to another view and back or pressing `r` in the sidebar to
   refresh it. With this change, the new view should appear immediately after
   being added (it should autorefresh the sidebar and return to the previously
   active window, which may or not be the sidebar itself).

3.  **Deep exportation:** modify `export.lua` and any other files related to
    exportation with the goal to enable "deep exportation". Deep exportation is
    defined here as an exportation of all selected notes plus the notes they
    depend on. To do so, the system must, for each note selected for
    exportation, check each note that it cites (and this includes any types
    such as journal, agg, bib, or note). If the cited note is not also included
    in the exportation list, then the system should include it. Deep
    exportation does not replace simple exportation, it is an extra option.
    Notes to be exported in deep exporation are those selected by the user and
    those cited by them, and the ones that cite them. The depth should be
    selectable at every function call, with a default of 0 for "cited by" and 2
    for "cites". This means that, by default, no notes that cite the selected
    notes (and therefore are listed in the "cited_by" metadata will be
    selected, and that notes cited by the selected note, as well as notes that
    these note cite will be selected.
    Example:

    ```
    Note 1 is selected for exportation, and:
    -   Note 1 cites Notes 2, 4, 5 (cites - depth 1); 
    -   Notes 2 and 4 cite no other notes, 
    -   Note 5 cites Note 7 (cites - depth 2); 
    -   Note 7 cites Note 8 (cites - depth 3). 
    -   Note 1 is cited by Notes 2, 3, 6, (cited by - depth 1). 

    By the default configuration, deep export will export Notes 1, 2, 4, 5,
    (cites - depth 1) and 7 (cites - depth 2), but not Notes 3, 6, since those
    two are cited neither by Note 1 nor by any note that Note 1 cites
    directly).
    ```

4. **Consistent view renaming:** `:PKMUpdateView` should ensure that any
   renamed views are also renamed in places that reference them (e.g. subviews
   that register them as a parent, any relevant index entry, etc.)

5.  **Bugfixes:**
    - Files can still open in the sidebar panel via `:PKMViewAll` and other
      commands. `:Ex` still opens explorer mode in the sidepanel, if used when
      the sidebar is the active window, so does `:PKMViewEdit`. This should
      have been fixed in previous versions.
    - `:PKMRenameNote` is not case sensitive (e.g. renaming a file from
      "prazos" to "Prazos" is not allowed triggers and error `[pkm] cannot
      rename: target already exists: 0142_agg_Prazos.md`)

---

### Distant Additions (mid-term to long-term)

1.  **Markdown improvements:**
    1.  Establish our own conventions for markdown, in order to provide a
        guideline for consistent and high-quality note-taking, reviewing, and
        editing, as well as LLM/AI collaboration. Some of these conventions may drive
        syntax highlighting and formatting, while others are simply meant to guide the
        user in using consistent notation and terminology. Examples (non-exhaustive):
        -   spacing: github's guidelines suggest using two spaces after number
            prefixes and 3 spaces after simple symbol prefixes to reach a 4
            space indentation, but what about symbols 4 character-large or more
            and numbers 3 character-large or more (the numbers are followed by
            an additional separator character and each prefix is followed by at
            least one space, so we would have to deal with an indentation level
            of 5). A possible solution is to allow text to start 1 space after
            the prefix (counting the separator for number prefixes) but then
            start at the correct indentation level from the second line
            onwards;
        -   evaluate cost-benefit of extending possible list prefix to any
            alphanumeric symbol + a separator from a standard separators list
            (e.g. `-`, `.`, `)`, `:`). Consider the same for symbol sequences.
            This would allow things such as `text:`, `I -`, `I)`, and many
            others to be highlighted and to provide a basis for text wrapping
            and indentation;
        -   tables: 
            -   decision on table types to support (markdown, csv, tsv, etc.);
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

        -   juxtaposing equivalent names like `AI/LLM` or `não-exaustivo/não-taxativo`.
    2.  Improved editor navigation: add keymapped commands to allow navigating
        between:
        -   Same level list component;
        -   Different level headers (same level headers is already implemented
            by standard neovim);
        -   Diferent level list components;
        -   Blocks of the same type (code blocks, lists, citation);
    3.  Extended list prefixs recognition. This needs to be analyzed in conjunction with Distant
        Additions 2.1. and with the current syntax highlighting constraints, as
        well as with any other conflicts that may arise from using these
        symbols as such (note that they would only have this effect if located
        at the beginning of a line and at the correct identation level, just
        like default lists prefixes).
    4.  A markdown table formatter, accoring to our conventions.
    5.  A custom autowrap that will correctly work with the elements of a PKM
        note, like YAML frontmatter, code blocks, headers (no autowrapping
        headers with text that imediately precedes or follows them), tables,
        etc.
    6. Improved motion inside tables (quickly move to next cell, column or
       line, including if it is not filled yet. This should make editing
       easier).
    7. Consider expanding our custom syntax highlighting and commands to all
       files outside PKM, this is not specific to PKM, but we can create a
       config to enable a broader reach of the markdown highlight and of the
       markdown functions as an option. Since this is something that I may find
       beneficial, we can implement it before the customization options for users (that is,
       this feature does not break the philosophy guidelines that instructs postponing
       customization, because it is something that I want to test and might want to keep
       always on if I find it useful (e.g. the default behavior of having
       4-space indented text highlight as code, even when prefixed as list, is
       distracting and does not serve any purpose).

2. **`lua/pkm/preview.lua`** — Browser-based live preview: Markdown + LaTeX (MathJax),
  WebSocket live updates on save, cross-platform browser opening, terminal fallback
  (glow/mdcat).

3. **Persistent index** — Serialize the in-memory index to disk (msgpack or JSON) with
  mtime-based incremental updates on startup. Needed only if startup scan time becomes
    1.  Every metadata modification, even automatic timestamp updating in
  unacceptable at very large corpus sizes (likely >50k notes). The current build cost
  is ~0.25 ms/note; at 500 notes (realistic current scale) that is ~125 ms, which is
  imperceptible. Run `bench.baseline()` on the real corpus before implementing this.

4.  **`_match_cache` in views.lua** — Cache matched path arrays alongside
    filter trees. Makes repeated `match_all` calls O(1) until invalidation.
    Bench showed 3.1 ms/view at 10k notes; not warranted at current scale.
    Revisit at ~5k notes or ~200+ views with observed latency.

5.  **Note review queue** — Select and track notes intended for review. May
    include organizers, separators, or filter interactions for priority/subject
    categorisation.

6.  **Alternative diagram and imaging methods** — ASCII/text-based art and
    other portable methods for enhancing notes without external image files.
    Any approach must be examined for human readability, AI/machine
    readability, and portability before implementation.

7.  **Improved contextual search/browse and citations:** improve the context
    detection algorithm, but only if it does not significantly impair
    performance, this context detection should enable notes to be ordered due
    to relevance both on search and on the panels (buffer and sidebar). E.g.
    notes related to the view, notes with similar citations, recently modified
    notes, recently opened notes. We should define a rationale for the criteria
    priority and consider algorithms used in popular tools to rank the
    relevance of files, urls, etc (like google's). This should make note
    navigation much more intuitive both during edition and when starting a new
    session.

    Example 1: `0035_bib_Constituição_da_República_Federativa_do_Brasil_1988.md`
    was not tagged as "direito-constitucional", so it was not captured as a
    contextual note when trying to cite it in other notes within the "Direito
    Constitucional" view. However, its name already suggest it is related to
    the subject, and it is cited by many other notes in the "Direito
    Constitucional" view or with the "direito-constitucional" tag. 

    We should analyze if there is a reasonable way to detect this, and perhaps
    even to rank what appears first depending on a combination of context, last
    opened/edited, frequently opened together, etc., and implement whatever is
    reasonable within our capabilities and neovim's/lua constraints, also
    keeping in mind that maintenability, compatibility with future vim's
    version, compatibility with pre-existing and future PKM features, and
    performance are all very important. This is a UX feature and it is
    important, however, discard part of or all of it if it cannot be
    implemented while also protecting or enhancing the points listed at the end
    of the previous sentence.

    Example 2: notes in the sidebar should be ordered according to relevance
    (e.g. last opened within that view/subview).

8.  **Explorer UI customisation:**
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


9.  **System customization:**
    1. Turn on/off our markdown features, to allow the user to use external
       markdown plugins if they prefer.

---

### Potential but not guaranteed goals (do not design toward)

- **Alternative PKM modes:** Obsidian-style backlink graph, Zettelkasten ID-based
  linking, etc. Would be selectable configurations, not the default.

- **Image and visualization support:** embedded images, Mermaid diagram support in
  preview, inline rendering (kitty/iTerm2 protocols).

- **`:PKMViewStats`** — table of all views with note counts and subproject depth.
  Implementation: iterate `views.list()`, call `match_all()` for each, format as
  notification or float.

- **Metadata system review (in-file vs. sidecar).** Recorded for future reconsideration
  only. Decision gate: revisit ONLY IF, after (1) the modified-buffer write-through fix
  and (2) frontmatter folding/conceal, the in-file approach remains unacceptable in
  daily use.

---

### Unlikely goals, nongoals, or out of consideration

- **Multi-wiki** — multiple independent namespaces with separate counters. Superseded
  by the view system. The single global counter guarantees uniqueness; do not break it.
- **Non-flat citations** — hierarchical structure beyond `notes`/`bib`. Undecided;
  current structure may be permanently sufficient.

---

## Critical Rules for LLM Assistants

### Never do this

| Rule | Reason |
|---|---|
| Modify `yaml.lua` without strong justification | Complex, carefully fixed bugs; any regression corrupts note files |
| Check Telescope availability at module load time | Lazy.nvim defers loading; use `pcall(require, 'telescope')` at call time |
| Use `generic_sorter` for exact-match contexts | Applies fzy scoring; use `finders.new_dynamic` + `sorters.empty()` with `string.find(..., 1, true)` |
| Reintroduce the `status` field | Intentionally removed |
| Use deprecated Neovim APIs | Use `nvim_set_option_value`, `vim.keymap.set` |
| Assume path separator | Always use `utils.sep` or `utils.join(...)` |
| Design toward multi-wiki | Superseded by project views; not a current goal |
| Physically separate notes for project organisation | Projects are views, not folders |
| Optimize `collect_files` without first running `bench.lua` | Baseline measurements required before any performance work |
| Register `UndoPost` autocmd | This event does not exist in Neovim ≤ 0.11.x; `vim.treesitter` tracks changes via `on_bytes` automatically |
| Call `index.invalidate` from buffer-only metadata commands | No disk write occurred; the index re-reads correctly on the user's next `:w` |
| Strip backlinks in `trash_note()` | Backlinks are preserved for clean restoration; `cleanup_deleted_note` is called only in `empty()` and `purge_old()` |

### Always do this

File-level header block before `local M = {}`:
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

Section separators between logical groups:
```lua
-- =============================================================================
-- SECTION: Section name
-- =============================================================================
```

Cross-platform paths:
```lua
local path = utils.join(dir, file)
local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)
```

Exact substring matching (never fzy):
```lua
if haystack:lower():find(needle:lower(), 1, true) then ... end
```

Telescope at call time:
```lua
local ok = pcall(require, 'telescope')
if ok then ... else ... end
```

Option setting (Neovim 0.10+):
```lua
vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
vim.keymap.set('n', 'q', fn, { noremap = true, silent = true, buffer = buf })
```

Per-tabpage state pattern:
```lua
local _tabs = {}
local function get_tab()
  local id = vim.api.nvim_get_current_tabpage()
  if not _tabs[id] then _tabs[id] = { ... } end
  return _tabs[id]
end
-- In setup(): register TabClosed autocmd to prune dead entries.
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
| Git | `git gc` is disabled on this repo (Google Drive sync conflict); `gc.auto 0` |

---

## Debugging Quick Reference

```vim
:lua print(vim.inspect(require('pkm').config))
:lua print(vim.inspect(require('pkm.trash').list()))
:messages
:PKMStats
:PKMMode on
:lua require('pkm.yaml').validate_frontmatter()
:lua require('pkm.bench').baseline()
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

**Do not run `git gc`** on this repo — it lives on Google Drive sync which causes
object-directory deletion conflicts. Global git config: `gc.auto 0`,
`gc.autoPackLimit 0`, `gc.autoDetach true`. The `pkm-merge` PowerShell alias
automates `dev→main` merges.

---

## Knowledge Base

- Neovim docs: https://neovim.io/doc/
- Lua docs: https://www.lua.org/docs.html
- LuaRocks style guide: https://github.com/luarocks/lua-style-guide

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

*Update this document when the project state changes.*
