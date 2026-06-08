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
== Search ==
- ✅ Boolean filter system — full DSL over tag/title/text/filename (AND, OR, NOT, parentheses)
- ✅ In-memory note index with incremental invalidation (~290× faster than per-query scan)
- ✅ `:PKMBrowse [expr]` — unified note browser via index+filter; replaces PKMTags ripgrep path
- ✅ Markdown utilities — header counter, level shift, emphasis wrapping, symbol abbreviations,
     heading navigation (`goto_heading`)
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
`wrap_with_marker(marker)` + `_wrap_operator` + `_wrap_visual`: emphasis wrapping system
with toggle and replace-without-stacking behaviour.
`setup_symbols(symbols)`: register buffer-local iabbrevs and insert-mode keymaps from
user-defined `{trigger?, key?, expansion}` entries.
`goto_heading(direction)`: jump to next/previous ATX heading in buffer.

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
    search          = "<leader>nf",
    browse_tags     = "<leader>nt",
    browse = false,
    -- Markdown editing
    ---- Headers
    next_header        = "<leader>Mh",
    header_level_up    = "<leader>M^",
    header_level_down  = "<leader>M_",
    renumber_list      = "<leader>Mr",
    ---- Emphasis wrapping (motion-based in normal mode; selection in visual mode)
    wrap_italic      = "<leader>Mi",   -- "*"   italic
    wrap_bold        = "<leader>Mb",   -- "**"  bold
    wrap_bold_italic = false,   -- "***" bold + italic
    wrap_code        = false,   -- "`"   inline code
    wrap_strike      = false,   -- "~~"  strikethrough (GFM)
  },
```

---

## Development Roadmap

### Active

No items currently in active development. Navigation system complete through Step 3.

---

### Next Steps

**1. Metadata commands — edit frontmatter without opening YAML**

*Motivation:* Tags and title are currently modified by manually navigating to
and editing the YAML block. This is friction-heavy for common operations and
incompatible with future interfaces that hide frontmatter entirely.

**Design:** Buffer-only. All commands operate on the currently open note.
All call `index.invalidate(filepath)` after writing.

- `:PKMSetTitle` — prompts for a new title string, writes it to the `title`
  frontmatter field. Does not rename the file.
- `:PKMAddTag [tag]` — appends a tag to the `tags` list. Prompts if no argument.
  Silently skips if already present.
- `:PKMRemoveTag [tag]` — removes a tag. Prompts/picker if no argument.

**Implementation:** `notes.lua` gets `M.set_title()`; `citations.lua` gets
`M.add_tag()` and `M.remove_tag()`. New commands in `commands.lua`. Keymaps
`set_title`, `add_tag`, `remove_tag` in `config.lua` and `keymaps.lua` (all
default `false`).

---
**2. Performance: views and sidebar at scale**

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

### Near-term additions

1. **Filter expression autocomplete** — when typing in `:PKMBrowse` or `:PKMView`,
   autocomplete tag names (from the index) and view names (from `views.list()`)
   as the user types. Requires a custom `complete` function in `commands.lua`.

2. **`:PKMBrowseRecent [n]`** — show the `n` most recently modified notes, sorted
   by `mtime` from the index. Quick access to recent work without needing a view.
   Implementation: `index.get_all()` sorted by `mtime` descending, sliced to `n`,
   passed to `telescope.browse()` or `ui.browse()`.

3. **`:PKMOrphans`** — show notes that have no citations (neither cites nor
   cited_by), no tags, and do not match any defined view. Useful for finding
   abandoned or unfiled notes.

4. **`:PKMViewStats`** — show a table of all views with their note counts and
   subproject depth. Provides an overview of how the knowledge base is organised.
   Implementation: iterate `views.list()`, call `match_all()` for each, format
   as a notification or float.

5. **Potential bugs to investigate before next major version:**
   - **Sidebar + tab pages:** `_sidebar_win` tracks one window globally. If the
     user has multiple tab pages, opening a sidebar in a second tab would
     conflict with the first tab's state. Mitigation: track sidebar state per
     tab page (`vim.api.nvim_get_current_tabpage()`).
   - **`:PKMDeleteNote` with sidebar open:** deleted note remains visible in the
     sidebar until `r` is pressed. The index is correct; only the display is
     stale. No crash, but user confusion is likely. Mitigation: hook into
     `delete_note_safely()` to trigger a sidebar refresh if open.
   - **Stale sidebar on external file deletion:** `<CR>` on a note whose file
     has been deleted externally will attempt `:edit` on a missing path.
     Mitigation: add `vim.fn.filereadable(path)` guard in the `<CR>` handler.
   - **`checktime` and sidebar buffer:** the BufWritePost autocmd in `init.lua`
     calls `vim.cmd("checktime")` after writing frontmatter. This triggers Vim's
     modeline scanner on all open buffers, including the sidebar's `nofile`
     buffer. The sidebar buffer has no content that would match modeline patterns,
     but the call is still unnecessary overhead. This is the same `checktime`/E518
     root cause logged elsewhere; the fix (replace with `nvim_buf_set_lines`) will
     also resolve this concern.

---

### Potential Additions (mid-term to long-term)

**`lua/pkm/preview.lua`**
Browser-based live preview: Markdown + LaTeX (MathJax), WebSocket live updates
on save, cross-platform browser opening, terminal fallback (glow/mdcat).

**Persistent index**
Serialize the in-memory index to disk (msgpack or JSON) with mtime-based
incremental updates on startup. Needed only if startup scan time becomes
unacceptable at very large corpus sizes (likely >50k notes). Evaluate other
solutions for speed at >10k notes before committing to this. Run
`bench.baseline()` on the real corpus first.

**Sidebar siblings via `<Tab>`**
Cycle the sidebar between the active view and its sibling subprojects (views
sharing the same parent). Deferred from the current sidebar implementation.
Requires identifying siblings via `get_view_children(get_view_parent(name))`.

**`_match_cache` in views.lua**
Cache the matched path arrays alongside the filter trees. Would make repeated
`match_all` calls (e.g. sidebar tree header builds) O(1) until the next cache
invalidation. Implement only after benchmarking shows it is necessary.

---

### Distant Future (not a current goal — do not design toward)

- **Alternative PKM modes:** Obsidian-style backlink graph, pure Zettelkasten ID-based
  linking, etc. Would be selectable configurations, not the default.
- **Image and visualization support:** embed images with normalized paths, Mermaid
  diagram support in preview, possibly inline rendering (kitty/iTerm2 protocols).
- **Review queue.** Enables the user to select and keep track of notes intended
  for review. Might include organizers, separators, or interact with filters to
  enable the user to categorize such notes according to priority, subject, etc.

---

### Postponed or Out of Consideration

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
