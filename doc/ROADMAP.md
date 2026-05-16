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

**Known limitations:**
- ⚠️ Filter system is AND-only across fixed fields (no boolean logic, no OR/NOT)
- ⚠️ No project view system (named saved filters)
- ⚠️ No in-memory index — filter queries scan all files on every call
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
│   │
│   │   -- PLANNED (Phase 1) --
│   ├── filter.lua      # Filter expression parser and evaluator (pure logic, no I/O)
│   ├── index.lua       # In-memory note index with incremental invalidation
│   ├── views.lua       # Named project views: load from config, activate, list
│   └── bench.lua       # Benchmarking and load-testing utilities (infrastructure)
├── plugin/pkm.lua      # Auto-load marker
├── doc/
│   ├── pkm.txt         # Vim help documentation
│   ├── PKM_ROADMAP.md  # This file
│   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
│   └── CHANGELOG.md    # Session history
├── tests/              # Test files
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
into templates. No side effects. Will gain a `projects` table in Phase 1.

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
destination folder. No `setup()`. Never modifies note files. In Phase 1, its filter
evaluation will delegate to `filter.lua` and its file collection will use `index.lua`.

---

### Planned Module Responsibilities (Phase 1)

**filter.lua** — pure logic, no I/O, no side effects.
- `filter.parse(expr)` → tree — parses a filter expression string into an AST
- `filter.eval(tree, note)` → boolean — evaluates a parsed tree against a note data table
- `filter.from_legacy(tbl)` → tree — converts old `{tags_any, tags_all, title, text}` tables for backward compatibility

Filter expression language (hand-rolled recursive descent parser, ~80 lines):
```
expr     = and_expr  (OR and_expr)*
and_expr = not_expr  (AND not_expr)*
not_expr = NOT? atom
atom     = "(" expr ")" | predicate
predicate= field ":" value
field    = "tag" | "title" | "text"
value    = bare_word | "quoted string"
```

Examples:
```
tag:rpg AND (title:ringforge OR text:ringforge)
tag:medicine AND tag:protocol AND NOT tag:draft
(tag:mathematics OR tag:physics) AND text:Fourier
```

**index.lua** — in-memory note index. Lazy: built on first query, not at startup.
- `index.get_all()` → array of note data tables (frontmatter + body + path)
- `index.get(path)` → single note data table
- `index.invalidate(path)` — called by BufWritePost autocmd; refreshes one entry
- `index.rebuild()` — full rescan; called on first use and on demand
- Memory cost: ~1–5 MB per 10k notes (frontmatter only, without body caching)

**views.lua** — named project views over the single note namespace.
- `views.list()` → array of view names from config
- `views.open(name)` → runs saved filter, opens results in Telescope or fallback picker
- `views.match_all(name)` → returns paths matching the named view's filter expression

**bench.lua** — benchmarking and load-testing. Not user-facing; developer tooling.
- `bench.time(fn)` → microseconds elapsed
- `bench.run_suite()` — timed suite: index build, filter query at N=100/1k/10k/100k
- `bench.gen_notes(n, dest)` — generates N synthetic notes for load testing

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

  -- PLANNED (Phase 1): Named project views.
  -- Each value is a filter expression string.
  -- Activated with :PKMView <name>.
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

### Active: Code Quality

- [ ] Module API header blocks (one per file)
- [ ] LuaDoc annotations on all exported functions
- [ ] Section separators inside large files (citations.lua, notes.lua)

These are additive — no behavior changes.

---

### Phase 1: Filter System & Project Views

**Motivation:** The current filter system (AND-only, fixed fields) cannot express
project-scoped queries. Notes should never be physically separated from the main
namespace — projects are views over a single flat note collection, not isolated
sub-wikis. This phase adds the infrastructure to define and activate those views.

**Step 1 — `filter.lua`**
Parser and evaluator for the filter expression language. Pure logic; no I/O.
Testable in isolation before any other Phase 1 work.
Also adds `filter.from_legacy()` to preserve backward compatibility with the
existing `export.lua` filter table format.

**Step 2 — Benchmarking baseline (`bench.lua`, basic)**
Before touching performance-critical code, establish a baseline:
- Measure current `collect_files` time on the real corpus
- Use `bench.gen_notes(n)` to simulate larger corpora (1k, 10k, 100k)
- Record results so post-index improvements can be validated against them

This step is not optional. Optimizing without a baseline is guesswork.

**Step 3 — `index.lua`**
In-memory note index. Eliminates the per-query full-filesystem scan.
Hooked into the existing BufWritePost autocmd for incremental invalidation.
After this step, `collect_files` goes from O(n × file-read) to O(n × table-lookup).

**Step 4 — Update `export.lua`**
- Replace internal filter evaluation with `filter.eval()`
- Replace `collect_files` scan with `index.get_all()` + filter pass
- Preserve the existing public API unchanged (backward compat via `from_legacy`)

**Step 5 — `views.lua` + commands + UI**
- Add `projects` table to `config.lua` defaults
- Implement `views.lua`
- Register `:PKMView [name]` and `:PKMViews` commands in `commands.lua`
- Wire Telescope / fallback picker for view results in `telescope.lua` / `ui.lua`

---


---

### Potential additions (not a current goal, but may be added in the mid-term)

**`lua/pkm/preview.lua`**
  - Browser-based live preview: Markdown + LaTeX (MathJax)
  - WebSocket live updates on save
  - Cross-platform browser opening
  - Terminal fallback (glow/mdcat)
- **Persistent index:** serialize the in-memory index to disk (msgpack or JSON), with
  mtime-based incremental updates on startup. Needed only if startup scan time becomes
  unacceptable at very large corpus sizes (likely >50k notes). Consider other solutions
  for speed at >10k notes, and especially at 100k notes.


### Distant Future (not a current goal — do not design toward)

- **Alternative PKM modes:** Obsidian-style backlink graph, pure Zettelkasten ID-based
  linking, etc. Would be selectable configurations, not the default.
- **Image and visualization support**
  - Embed images in notes with normalized paths
  - Mermaid diagram support in preview
- Possibly inline rendering in terminal (kitty/iterm2 protocols)

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

```lua
-- Cross-platform paths
local path = utils.join(dir, file)
local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)

-- Exact substring matching (never fzy)
if haystack:lower():find(needle:lower(), 1, true) then ... end

-- Telescope at call time
local ok = pcall(require, 'telescope')
if ok then ... else ... end

-- Option setting (Neovim 0.10+)
vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

-- Buffer-local keymaps
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
:PKMValidate
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
