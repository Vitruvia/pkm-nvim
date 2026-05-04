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

Alternative PKM modes (Obsidian-style, pure Zettelkasten, etc.) are a **distant future idea** — not a current goal. Multi-wiki support is similarly distant. Do not design toward these unless the user explicitly asks.

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
- ✅ Telescope integration: note search, tag browser, citation picker
- ✅ Export utility: filter notes by tag/title/body text, copy to folder (`:PKMExport`)
- ✅ Cross-platform: Windows, WSL, Linux, macOS

**Known limitations:**
- ⚠️ Single wiki only (multi-wiki is distant future)
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support
- ⚠️ Export filter groups AND-only across fields (no cross-field OR)

**Metadata notes:**
- The `status` field has been **removed** from frontmatter. Do not reintroduce it.
- Citation structure is grouped: `cites: {notes: [], bib: []}` and `cited_by: {notes: [], bib: []}`. Whether non-flat (hierarchical) citations will be added is undecided; do not change this structure without discussion.

---

## File Structure

```
pkm.nvim/
├── lua/pkm/
│   ├── init.lua        # Entry point, setup(), command registration, keymaps
│   ├── yaml.lua        # YAML frontmatter parsing and generation (complex — handle carefully)
│   ├── timestamp.lua   # Timestamp creation, parsing, formatting
│   ├── citations.lua   # Bidirectional citation engine; get_all_tags(), get_file_tags()
│   ├── notes.lua       # Note creation, conversion, promotion, linking
│   ├── journal.lua     # Journal entry creation and sync
│   ├── ui.lua          # Fallback UI (stats window, tag browser without Telescope)
│   ├── telescope.lua   # Telescope pickers: search, tags, citations
│   ├── templates.lua   # Template application to notes
│   └── export.lua      # Note filtering and copy utility (READ-ONLY)
├── plugin/pkm.lua      # Auto-load marker
├── doc/pkm.txt         # Vim help documentation
├── tests/              # Test files
└── README.md
```

---

## Module Responsibilities

**init.lua** — configuration, module initialization, all `:PKM*` command registration, keymap setup, sync autocmds.

**yaml.lua** — parse and generate YAML frontmatter. Contains a non-trivial parser that handles nested empty structures correctly. **Do not modify without strong justification.** Critical fixed bug: empty nested arrays must serialize as `[]`, not as corrupted YAML.

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses existing timestamps.

**citations.lua** — bidirectional citation sync; `get_all_tags()` returns all tags across all notes; `get_file_tags(path)` returns tags for one file; `get_citable_items_map()` returns all notes indexed by identifier.

**notes.lua** — all note file operations: create, convert, promote, import, link, follow link, backlinks, filename-YAML sync.

**journal.lua** — journal creation (auto-timestamped by default); journal-specific filename-YAML sync.

**ui.lua** — fallback UI for stats and tag browsing when Telescope is not available.

**telescope.lua** — Telescope pickers for note search, tag browser, citation insertion. **Checks Telescope availability at call time**, not module load time (critical for Lazy.nvim).

**export.lua** — filter notes by frontmatter attributes and body text; copy matching files to a destination folder. No `setup()` needed; reads config lazily. Never modifies note files.

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
    auto_sync_on_save = true,  -- updates last_updated_on and citations on write
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

  keymaps = {
    new_note      = "<leader>nn",
    new_journal   = "<leader>nj",
    new_scratchpad = "<leader>ns",
    quick_capture = "<leader>nq",
    convert_note  = "<leader>nx",
    promote_note  = "<leader>np",
    insert_citation = "<leader>nc",
    goto_citation = "<leader>ng",
    link_note     = "<leader>nl",
    follow_link   = "gf",
    backlinks     = "<leader>nb",
    search        = "<leader>nf",
    browse_tags   = "<leader>nt",
    import_note   = "<leader>ni",
    delete_note   = "<leader>nd",
  },
})
```

---

## Development Roadmap

### Near-Term

**Export filter improvements**
- Two filter groups connected by OR (cover cross-field OR queries)
- Tag picker in the form (select from existing tags via Telescope instead of typing)

### Mid-to-Long Term

**Preview system** (`lua/pkm/preview.lua`)
- Browser-based live preview: markdown + LaTeX (MathJax)
- WebSocket live updates on save
- Cross-platform browser opening
- Terminal fallback (glow/mdcat)

**Image and visualization support**
- Embed images in notes with normalized paths
- Possibly inline rendering in terminal (kitty/iterm2 protocols)
- Mermaid diagram support in preview

### Distant Future (not a current goal — do not design toward)

- **Multi-wiki**: multiple independent note collections with citation permissions between them. Could be added as an opt-in configuration layer without breaking the single-wiki default.
- **Alternative PKM modes**: Obsidian-style (backlink graph), pure Zettelkasten (ID-based linking), etc. Would be selectable configurations, not the default.
- **Non-flat citations**: hierarchical or categorized citation structure. The current flat grouped structure (`notes`/`bib`) may be sufficient permanently; this is undecided.

---

## Critical Rules for LLM Assistants

### Never do this

| Rule | Reason |
|---|---|
| Modify yaml.lua without strong justification | Complex, carefully fixed bugs; any regression corrupts files |
| Check Telescope availability at module load time | Lazy.nvim defers loading; always check at call time with `pcall(require, 'telescope')` |
| Use `generic_sorter` for exact-match contexts | It uses fzy (subsequence matching); use `finders.new_dynamic` with `string.find(..., 1, true)` |
| Reintroduce the `status` field | It has been intentionally removed |
| Use deprecated Neovim APIs | Use `nvim_set_option_value` not `nvim_buf_set_option`; use `vim.keymap.set` not `nvim_buf_set_keymap` |
| Assume path separator | Always `package.config:sub(1, 1)` |
| Design toward multi-wiki without being asked | Not a current goal |

### Always do this

```lua
-- Cross-platform paths
local sep = package.config:sub(1, 1)
local path = table.concat({dir, file}, sep)

-- Exact substring matching (never fzy)
if haystack:lower():find(needle:lower(), 1, true) then ... end

-- Telescope at call time
local ok = pcall(require, 'telescope')
if ok then ... else ... fallback ... end

-- Option setting (Neovim 0.10+)
vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

-- Buffer-local keymaps
vim.keymap.set('n', 'q', fn, { noremap = true, silent = true, buffer = buf })
```

### OS detection

```lua
local is_windows = vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1
local is_wsl     = vim.fn.has('wsl') == 1
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

*Update this document when the project state changes. Provide it to any LLM assistant working on PKM.nvim.*
