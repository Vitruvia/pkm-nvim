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
- ✅ Filename ↔ YAML title synchronization
- ✅ Note promotion: scratchpad → consolidated or journal
- ✅ Note conversion between types
- ✅ Import existing files into PKM structure
- ✅ Citation cleanup (removes stale references when notes are deleted)
- ✅ Tag merging across all notes
- ✅ Telescope integration: note search, tag browser, citation picker
- ✅ Export utility: filter notes by tag/title/body text, copy to folder (`:PKMExport`)
- ✅ Statistics window (`:PKMStats`)
- ✅ Cross-platform: Windows, WSL, Linux, macOS
- ✅ Boolean filter system — full DSL over tag/title/text (AND, OR, NOT, parentheses)
- ✅ In-memory note index with incremental invalidation (~290× faster than per-query scan)
- ✅ Project view system — named saved filters, sidecar `views.json`, full CRUD commands

**Known limitations:**
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support

**Metadata notes:**
- The `status` field has been **removed** from frontmatter. Do not reintroduce it.
- Citation structure is grouped: `cites: {notes: [], bib: []}` and `cited_by: {notes: [], bib: []}`. Whether non-flat (hierarchical) citations will be added is undecided; do not change this structure without discussion.

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
follow link, backlinks, filename-YAML sync.

**journal.lua** — journal creation (auto-timestamped by default); journal-specific filename-YAML sync.

**ui.lua** — fallback UI for stats, search, and tag browsing when Telescope is absent.

**telescope.lua** — all Telescope pickers. Checks availability at call time (not load
time — critical for Lazy.nvim).

**export.lua** — filter notes by frontmatter fields and body text; copy matches to a
destination folder. No `setup()`. Never modifies note files. Delegates filter
evaluation to `filter.lua` and file collection to `index.lua`.

**filter.lua** — pure logic, no I/O. Parses filter expression strings into ASTs and
evaluates them against note data tables. Grammar: AND/OR/NOT over tag/title/text
predicates with parentheses and quoted values. `from_legacy()` converts old
`{tags_any, tags_all, title, text}` tables for backward compatibility.

**index.lua** — in-memory note index. Lazy build on first `get_all()` call.
Incremental invalidation via `BufWritePost` autocmd and explicit `invalidate(path)`
calls after every programmatic file write or delete. Path keys are normalized
(`\` → `/`) for cross-platform lookup consistency.

**views.lua** — named project views. Reads from `views.json` (sidecar at PKM root)
and `config.projects`; sidecar wins on collision. `setup()` registers a
`BufWritePost` autocmd to reload on sidecar save. Full CRUD via `save()`, `delete()`.
Telescope picker with exact-substring prompt and file preview; float fallback.

**bench.lua** — developer benchmarking and load-testing. Not user-facing, no commands.
Four-phase suite: raw scan, index build, index query, filter eval. Self-cleaning
(synthetic files deleted after run). `baseline()` times real corpus read-only.

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
    rpg     = 'tag:rpg AND (title:ringforge OR text:ringforge)',
    clinic  = 'tag:medicine AND tag:protocol',
    physics = '(tag:mechanics OR tag:thermodynamics) AND NOT tag:draft',
  },

  keymaps = {
    new_note         = "<leader>nn",
    new_journal      = "<leader>nj",
    new_scratchpad   = "<leader>ns",
    quick_capture    = "<leader>nq",
    convert_note     = "<leader>nx",
    promote_note     = "<leader>np",
    insert_citation  = "<leader>nc",
    goto_citation    = "<leader>ng",
    link_note        = "<leader>nl",
    follow_link      = "gf",
    backlinks        = "<leader>nb",
    search           = "<leader>nf",
    browse_tags      = "<leader>nt",
    import_note      = "<leader>ni",
    delete_note      = "<leader>nd",
    transpose_note   = "<leader>nT",
    change_note_type = "<leader>nC",
  },
})
```

---

## Development Roadmap

### Active

**1. `markdown.lua`** — general markdown editing utilities.
Functions: `append_next_header`, `shift_header_level`, `wrap_with_marker`,
`_wrap_operator`, `_wrap_visual`. No setup() needed.

---

### Next Steps

**1. Unified note browser (`PKMBrowse`) — consolidate PKMSearch and PKMTags**

*Motivation:* PKMSearch and PKMTags both answer the same question ("find a note to open") but bypass `filter.lua`, the structured query engine the project already owns. PKMTags uses `grep_string` (full-text ripgrep), which produces false positives and duplicate results instead of matching against frontmatter. PKMSearch uses `live_grep`, which cannot be combined with tag or title constraints. PKMExport already does this correctly via `index.lua` + `filter.lua` and is the model to follow; it is kept separate because its purpose (batch file export) is categorically different from interactive browsing.

**Design:**

`:PKMBrowse [filter_expr]` — open a Telescope picker over all PKM notes, optionally pre-filtered by an expression in the `filter.lua` grammar (`tag:math AND title:fourier`, etc.). Empty input shows all notes.

- Uses `index.get_all()` + `filter.eval()` for evaluation — same pipeline as `export.lua`.
- Picker uses `finders.new_dynamic` with exact substring filtering on the display string and a pass-through sorter, same as `telescope_results_picker` in `export.lua`. This prevents fzy from contaminating structured results.
- `PKMTags` becomes a thin wrapper: pick a tag from the list, then open `PKMBrowse` pre-filtered to `tag:<selected>`.
- `PKMSearch` (`live_grep`) may be retained as a power-user shortcut for incremental streaming text search — the one case where ripgrep's live feedback is a genuine UX advantage over the index. If retained, it must be clearly scoped to "raw text search only" and documented accordingly. Otherwise it is deprecated in favour of `PKMBrowse text:<query>`.
- `ui.lua` gets a matching `M.browse(filter_expr)` fallback using `vim.ui.select` with the same index + filter pipeline.

**Keymap:** `browse_tags` (`<leader>nt`) points to `PKMBrowse`; optionally a new `browse` key replaces it or the same key is reused. The filter expression language is the same as `PKMView`, so users work with one syntax everywhere.

**Dependency:** `index.lua` invalidation (already reliable post-refactor). No new infrastructure needed.

---

**2. Subproject hierarchy for views**

Views can declare a parent view; the subproject's effective filter is the parent
filter AND-ed with its own constraints. Sibling subprojects can overlap freely
since all notes remain in the flat namespace.

**Design:**

`views.json` is extended with an optional `parent` field. String values remain
simple views (backward compatible); table values with a `parent` field are
subprojects:

```json
{
  "ringforge": "tag:ringforge",
  "ringforge-mechanics": {
    "parent": "ringforge",
    "filter": "tag:mechanics"
  },
  "ringforge-references": {
    "parent": "ringforge",
    "filter": "tag:reference"
  }
}
```

The effective filter for `ringforge-mechanics` resolves to:
`tag:ringforge AND tag:mechanics`

Resolution walks the parent chain at query time and composes trees using
`filter.lua`'s existing AND node. No new parser work needed.

**Depth:** unbounded in principle; enforce a practical limit of ~8 levels during
validation with a clear error message. Cycles are detected by tracking visited
names during resolution.

**UI — Phase 1 (initial):** a keymap inside the view picker cycles between the
active view and its sibling subprojects, each opening a new picker.

**UI — Phase 2 (future):** dedicated subproject picker — see Potential Additions.

---

**3. `:PKMViewLast` — reopen last active view**

*Motivation:* After the Search Merge, `:PKMView <name>` requires recalling and
typing the view name each invocation. There is no equivalent of Neovim's
alternate-buffer (`<C-6>`) for views.

**Design:**

A module-level variable `_last_view` in `views.lua` is set whenever `M.open()`
activates a view successfully. `:PKMViewLast` calls `M.open(_last_view)` if
set, or notifies that no view has been activated yet.

- New command `:PKMViewLast` in `commands.lua`.
- New keymap key `view_last` (suggested default: `<leader>nV`) in `config.lua`
  and `keymaps.lua`.
- No new infrastructure. `_last_view` is session-scoped; it does not persist
  across Neovim restarts, which is intentional — a restart implies a context
  change.

**Dependency:** None. Implement immediately after Search Merge.

---

**4. Views sidebar — persistent split buffer for view navigation**

*Motivation:* Both `:PKMView` and `:PKMViewLast` are modal and one-shot: the
picker closes when a note is opened. There is no way to stay inside a view's
scope while editing — to glance at the view's note list, open a note, return to
the list, open another. The sidebar solves this the same way the QuickFix window
solves it for compiler errors: a persistent, non-modal result list that stays
open alongside the editing area.

**Design:**

`:PKMViewSidebar [name]` opens a vertical split on the left (configurable side)
containing a scratch buffer. The buffer lists the active view's notes, one per
line, prefixed with their index. Navigation keymaps in the buffer:

- `<CR>` — open note under cursor in the main window (not a new split)
- `r` — refresh (re-run the view's filter against the current index)
- `q` / `<Esc>` — close the sidebar
- `<Tab>` (with subprojects) — cycle to a sibling or child view

The sidebar is toggled: a second `:PKMViewSidebar` call with the same view
closes it; with a different view name, it replaces the contents.

Window management follows the nvim-tree convention: one sidebar window per
Neovim instance, tracked by window ID in module state. If the window is closed
externally (`:q`), the state is cleared on next toggle.

**Relationship to the tree UI:**

Without subproject hierarchy, the sidebar shows a flat sorted list of the
current view's notes. This is already useful: it is the persistent-context
version of `views.open()`.

With subproject hierarchy implemented, the same buffer gains a tree header
showing the view's position in the hierarchy and its children:

```
▼ ringforge (14)
▶ ringforge-mechanics (6)
▶ ringforge-references (8)
──────────────────────────────
note_0042_Damage_Systems.md
note_0051_Spell_Targeting.md
...
```

The tree header is navigable: `<CR>` on a child view reloads the sidebar for
that view; `<BS>` navigates to the parent view.

**Dependency:** The flat list version has no dependencies beyond Search Merge
and `:PKMViewLast`. The tree header requires subproject hierarchy (item 2).
Implement the flat version first; extend to the tree when subprojects land.


### Near-term additions

**Unified note browser (`PKMBrowse`)**

**Enhanced markdown support**: see Active.

Examples:
- Automating `:%s/^#\(#*\)/\1/g` and `'<,'>s/^#\(#*\)/\1` to decrease the level
  of all headers in the file or in a selection.

### Potential Additions (mid-term to long-term)

**`lua/pkm/preview.lua`**
Browser-based live preview: Markdown + LaTeX (MathJax), WebSocket live updates
on save, cross-platform browser opening, terminal fallback (glow/mdcat).

**Persistent index**
Serialize the in-memory index to disk (msgpack or JSON) with mtime-based
incremental updates on startup. Needed only if startup scan time becomes
unacceptable at very large corpus sizes (likely >50k notes). Evaluate other
solutions for speed at >10k notes before committing to this.

---

### Distant Future (not a current goal — do not design toward)

- **Alternative PKM modes:** Obsidian-style backlink graph, pure Zettelkasten ID-based
  linking, etc. Would be selectable configurations, not the default.
- **Image and visualization support:** embed images with normalized paths, Mermaid
  diagram support in preview, possibly inline rendering (kitty/iTerm2 protocols).
- **Review queue**. Enables the user to select and keep track of notes intended
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

---

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
