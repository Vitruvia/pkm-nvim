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

No items currently in active development. All implementation phases are complete.

---

### Next Steps

No implementation items are currently queued. All planned phases are complete.

If new items arise from daily use, add them here with enough context for an LLM
to act on them without cross-referencing the conversation history.

---

### Distant Additions (mid-term to long-term)

- **Explorer UI customisation** — positions and width of each panel; auto-on/off
  triggers by directory, CWD, or buffer type; other layout options users may need.
  Deferred from Phase 3.

- Improved help panel with main keymaps for PKM (the current panel is sidebar
  only). This panel would have to update depending on how the user customizes
  their config, so this change is related to "Explorer UI Customisation".

- **`lua/pkm/preview.lua`** — Browser-based live preview: Markdown + LaTeX (MathJax),
  WebSocket live updates on save, cross-platform browser opening, terminal fallback
  (glow/mdcat). Deferred from Phase 5.

- **Persistent index** — Serialize the in-memory index to disk (msgpack or JSON) with
  mtime-based incremental updates on startup. Needed only if startup scan time becomes
  unacceptable at very large corpus sizes (likely >50k notes). The current build cost
  is ~0.25 ms/note; at 500 notes (realistic current scale) that is ~125 ms, which is
  imperceptible. Run `bench.baseline()` on the real corpus before implementing this.
  Deferred from Phase 5.

- **`_match_cache` in views.lua** — Cache matched path arrays alongside filter trees.
  Makes repeated `match_all` calls O(1) until invalidation. Bench showed 3.1 ms/view at
  10k notes; not warranted at current scale. Revisit at ~5k notes or ~200+ views with
  observed latency. Deferred from Phase 5.

- **Note review queue** — Select and track notes intended for review. May include
  organizers, separators, or filter interactions for priority/subject categorisation.
  Deferred from Phase 5.

- **Alternative diagram and imaging methods** — ASCII/text-based art and other portable
  methods for enhancing notes without external image files. Any approach must be examined
  for human readability, AI/machine readability, and portability before implementation.
  Deferred from Phase 3.

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

*Update this document when the project state changes.*
