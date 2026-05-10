# PKM.nvim — Project Roadmap for LLM Assistants

**Purpose:** Comprehensive guide for AI assistants continuing development across sessions.
Read LLM_CONTEXT.md first for the fast summary. Read this for planning and architecture.

---

## What This Project Is

PKM.nvim is an integrated note-taking and knowledge management plugin for Neovim, built
around the author's own workflow — not an implementation of Obsidian, Zettelkasten, or any
other established PKM theory.

The core concept is a structured note flow:

    Scratchpad  →  capture ideas quickly, no friction
        ↓
    Journal     →  timestamped daily entries, personal log
        ↓
    Consolidated →  permanent numbered knowledge base

Notes are plain markdown files with YAML frontmatter. Consolidated notes carry structured
citations that create bidirectional links automatically. The system is local-first,
cross-platform, and Vim-native.

Alternative PKM modes and multi-wiki support are **distant future ideas** — not current
goals. Do not design toward these unless explicitly asked.

---

## Current State

**Working features:**
- ✅ Three folder types: Scratchpad, Journal, Consolidated
- ✅ Note creation with automatic numbering (`0042_note_Title.md`)
- ✅ Note types within Consolidated: `note`, `bib` (bibliography), `agg` (aggregate)
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
- ⚠️ Single wiki only (multi-wiki is distant future)
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support
- ⚠️ Export filter groups are AND-only across fields (no cross-field OR)

---

## File Structure

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
    │   └── export.lua      # Note filtering and copy utility (read-only, no setup() needed)
    ├── plugin/pkm.lua      # Auto-load marker
    ├── doc/
    │   ├── pkm.txt         # Vim help documentation
    │   ├── PKM_ROADMAP.md  # This file
    │   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
    │   └── CHANGELOG.md    # Session history
    ├── tests/              # Test files
    └── README.md

---

## Module Responsibilities

**init.lua** — pure orchestration. Calls `setup()` on every module, then calls
`commands.register()`, `keymaps.register(config)`, and `setup_sync_autocmds()`.
Also holds `delete_note_safely()` and `setup_sync_autocmds()` as these need
direct access to `M.config`.

**config.lua** — pure data. Holds the default config table and `resolve(user_config)`,
which merges defaults with user input, resolves paths, validates, and injects author
into templates. No side effects.

**utils.lua** — shared utilities. `utils.join(...)`, `utils.sep`, `utils.normalize(path)`,
`utils.ensure_dir(path)`, `utils.is_windows`, `utils.is_wsl`. No setup() needed.

**commands.lua** — registers all `:PKM*` user commands. Handlers use lazy `require`
inside each callback. References to `init.lua` functions go through `require('pkm')`.

**keymaps.lua** — registers all `<leader>` keymaps. Receives `config` as a parameter
to `register(config)` because it needs keymap strings at registration time.

**yaml.lua** — parse and generate YAML frontmatter. Contains a non-trivial parser
handling nested empty structures. **Do not modify without strong justification.**

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses existing
timestamps.

**citations.lua** — bidirectional citation sync; `get_all_tags()`, `get_file_tags(path)`,
`get_citable_items_map()`, `merge_tags(sources, target)`.

**notes.lua** — all note file operations: create, convert, promote, import, link,
follow link, backlinks, filename-YAML sync.

**journal.lua** — journal creation (auto-timestamped by default); journal-specific
filename-YAML sync.

**ui.lua** — fallback UI for stats, search, and tag browsing when Telescope is absent.
`show_stats()` is the implementation behind `:PKMStats`.

**telescope.lua** — all Telescope pickers. Checks availability at call time (not load
time — critical for Lazy.nvim).

**export.lua** — filter notes by frontmatter fields and body text; copy matches to a
destination folder. No `setup()`. Never modifies note files.

---

## Development Roadmap

### Next: Code Quality (In Progress)

- [ ] Module API header blocks (one per file)
- [ ] LuaDoc annotations on all exported functions
- [ ] Section separators inside large files (citations.lua, notes.lua)

### Phase 1: Multi-Wiki System (Future)

Support multiple independent wikis with citation permissions. Not a current goal.

### Phase 2: Preview System (Future)

Browser-based live preview with LaTeX and Markdown rendering. Not a current goal.

---

## Environment

| Item | Value |
|---|---|
| OS | Windows 10 + WSL (Ubuntu) |
| Editor | Neovim 0.11.3 |
| Plugin manager | Lazy.nvim |
| Plugin path | `P:/Active/pkm-nvim/` (Windows) · `/mnt/p/Active/pkm-nvim/` (WSL) |
| Notes path | `P:/Notes` (Windows) · `/mnt/p/Notes` (WSL) |

---

## Git Conventions

Commit format:

    <type>: <summary>

    - detail
    - detail

Types: `feat` `fix` `docs` `refactor` `test` `chore`

Branches: `feat/<name>`, `fix/<name>`

---

## Knowledge Base

- Neovim docs: https://neovim.io/doc/
- Lua docs: https://www.lua.org/docs.html
- LuaRocks style guide: https://github.com/luarocks/lua-style-guide
