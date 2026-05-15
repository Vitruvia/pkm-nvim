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
- ✅ Note conversion between types within folder (:PKMConvertNote)
- ✅ Note transposition between folders (:PKMTranspose)
- ✅ Note type change within consolidated folder (:PKMChangeType)
- ✅ Import existing files into PKM structure
- ✅ Citation cleanup (removes stale references when notes are deleted)
- ✅ Tag merging across all notes
- ✅ Telescope integration: note search, tag browser, citation picker, tag merge
- ✅ Export utility: filter notes by tag/title/body text, copy to folder (:PKMExport)
- ✅ Statistics window (:PKMStats)
- ✅ Cross-platform: Windows, WSL, Linux, macOS

**Known limitations:**
- ⚠️ Single wiki only
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support
- ⚠️ Export filter groups AND-only across fields (no cross-field OR yet)
- ⚠️ quick_capture keymap unreachable (mapped to wrong command)

---

## File Structure

    pkm.nvim/
    ├── lua/pkm/
    │   ├── init.lua        # Orchestration only: setup, commands, keymaps, autocmds
    │   ├── config.lua      # Default config table and resolution logic (pure data)
    │   ├── utils.lua       # Shared cross-platform utilities
    │   ├── commands.lua    # All :PKM* command registration (lazy handlers)
    │   ├── keymaps.lua     # All keymap wiring (receives resolved config)
    │   ├── yaml.lua        # YAML frontmatter parsing and generation — handle carefully
    │   ├── timestamp.lua   # Timestamp creation, parsing, formatting
    │   ├── citations.lua   # Bidirectional citation engine, tag indexing
    │   ├── notes.lua       # Note creation, conversion, promotion, navigation
    │   ├── journal.lua     # Journal entry creation, filename-YAML sync
    │   ├── ui.lua          # Fallback UI: stats, tag browser, search (no Telescope)
    │   ├── telescope.lua   # Telescope pickers: search, tags, citations, tag merge
    │   ├── templates.lua   # Template application to notes
    │   └── export.lua      # Note filtering and copy utility (read-only)
    ├── plugin/pkm.lua      # Auto-load marker
    ├── doc/
    │   ├── pkm.txt         # Vim help documentation
    │   ├── PKM_ROADMAP.md  # This file
    │   ├── LLM_CONTEXT.md  # Fast-read session brief for LLMs
    │   └── CHANGELOG.md    # Version history and known bugs
    ├── tests/
    └── README.md

---

## Module Responsibilities

**init.lua** — pure orchestration. Calls `setup()` on every module, registers commands
and keymaps, sets up sync autocmds. Holds `delete_note_safely()` and
`setup_sync_autocmds()` which need direct access to `M.config`.

**config.lua** — pure data. Default config table and `resolve(user_config)`. No side
effects.

**utils.lua** — shared utilities. `join()`, `sep`, `normalize()`, `ensure_dir()`,
`is_windows`, `is_wsl`. No setup() needed.

**commands.lua** — registers all `:PKM*` user commands. Handlers use lazy `require`.
References to init.lua functions go through `require('pkm')`.

**keymaps.lua** — registers all `<leader>` keymaps. Receives `config` as parameter
to `register(config)` because it needs keymap strings at registration time.

**yaml.lua** — parse and generate YAML frontmatter. Contains a non-trivial parser.
**Do not modify without strong justification.**

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses existing
timestamps.

**citations.lua** — bidirectional citation sync; tag indexing; `get_citable_items_map()`;
`merge_tags()`.

**notes.lua** — all note file operations: create, convert, transpose, change type,
promote, import, link, follow link, backlinks, filename-YAML sync.

**journal.lua** — journal creation; journal-specific filename-YAML sync.

**ui.lua** — fallback UI for stats, search, tag browsing when Telescope is absent.

**telescope.lua** — all Telescope pickers. Checks availability at call time (critical
for Lazy.nvim). Returns empty module if Telescope unavailable at load time (known issue).

**templates.lua** — template application to notes. Template picker is currently a stub.

**export.lua** — filter notes by frontmatter fields and body text; copy to destination.
No `setup()`. Never modifies note files.

---

## Development Roadmap

### Near Term (queued bugs and improvements)

Bugs and improvements queued for the next development cycle are tracked in
`doc/CHANGELOG.md` under Known Bugs and Dead Code. Check there before starting
any session.

Current priority items:
- Fix rename-from-inside-note requiring manual `e!`
- Fix greedy timestamp pattern in journal.lua querying functions
- Add Telescope fallback to PKMSearch and PKMTags
- Fix quick_capture keymap calling wrong command
- Fix telescope.lua load-time Telescope check
- Fix templates.lua silent failure when Telescope is loaded
- Remove identified dead code

### Export improvements
- Two filter groups connected by OR (cross-field OR queries)
- Tag picker in the export form (select from existing tags via Telescope)

### Preview system (mid-term)
Browser-based live preview with Markdown + LaTeX (MathJax) rendering. WebSocket
live updates on save. Cross-platform browser opening. Terminal fallback (glow/mdcat).
**Not a current goal — do not design toward it until explicitly asked.**

### Image and visualization support (mid-term)
Embed images in notes with normalized paths. Possibly inline rendering in terminal
(kitty/iterm2 protocols). Mermaid diagram support in preview.
**Not a current goal.**

### Multi-wiki support (distant future)
Multiple independent note collections with configurable citation permissions between
them. Would be added as an opt-in configuration layer without breaking the
single-wiki default. The current architecture (single `root_path`, module-level
`config` tables) would need refactoring to support multiple configs simultaneously.
**Not a current goal — do not design toward it until explicitly asked.**

### Alternative PKM modes (distant future)
Selectable workflow configurations: Obsidian-style (backlink graph focus),
pure Zettelkasten (ID-based linking), etc. Would not change the default behavior.
**Not a current goal.**

### Non-flat citation structure (undecided)
The current flat grouped structure (`cites: {notes, bib, journal, scratch}`) may be
sufficient permanently. Hierarchical or categorized citations are a possible future
direction. **Do not change the citation structure without explicit discussion.**

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

### Primary sources
- Neovim docs: https://neovim.io/doc/
- Lua manual: https://www.lua.org/manual/5.4/
- Programming in Lua: https://www.lua.org/pil/

### Others
- LuaRocks style guide: https://github.com/luarocks/lua-style-guide
