# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read PKM_ROADMAP.md for architecture detail.

Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its
principles are non-negotiable constraints on all architectural decisions.

---

## Current State (as of 2026-05-16)

Stable. All core features work. Refactor complete. Phase 1 design decisions made.

**Last sessions:**
- Extracted `config.lua`, `utils.lua`, `commands.lua`, `keymaps.lua` from `init.lua`
- Added `PKMTranspose`, `PKMChangeType`, cross-folder backlinks, `PKMMergeTags`
- Decided: project organisation via **views** (saved filter definitions), not multi-wiki
- Decided: filter system needs full boolean DSL (AND/OR/NOT over tag/title/text)
- Decided: in-memory index required before filter system is performant at scale
- `doc/ROADMAP.md` is a stale duplicate — **delete it**; `PKM_ROADMAP.md` is canonical

**Active next steps:**
1. Code quality: module API headers, LuaDoc, section separators (additive, no behavior change)
2. Phase 1: `filter.lua` → benchmarking baseline → `index.lua` → update `export.lua` → `views.lua`

---

## Module Map (one line each)

| File | Role |
|---|---|
| `init.lua` | Orchestration only — calls setup, wires everything |
| `config.lua` | Pure data — defaults, path resolution, validation |
| `utils.lua` | Shared utilities — path join, OS flags, ensure_dir |
| `commands.lua` | All `:PKM*` commands — handlers lazy-require their modules |
| `keymaps.lua` | All keymaps — receives `config` as parameter to `register(config)` |
| `yaml.lua` | YAML parse/generate — complex, do not touch lightly |
| `timestamp.lua` | Timestamp formats, filename generation |
| `citations.lua` | Bidirectional citation sync, tag index, citable item map |
| `notes.lua` | Note CRUD, conversion, promotion, transposition, linking |
| `journal.lua` | Journal creation, filename-YAML sync |
| `ui.lua` | Fallback UI (no Telescope): stats, search, tags, merge |
| `telescope.lua` | All Telescope pickers |
| `templates.lua` | Template application |
| `export.lua` | Filter + copy notes — read-only, no setup() |
| *(planned)* `filter.lua` | Filter expression parser and evaluator — pure logic, no I/O |
| *(planned)* `index.lua` | In-memory note index with BufWritePost invalidation |
| *(planned)* `views.lua` | Named project views from config; activate via :PKMView |
| *(planned)* `bench.lua` | Benchmarking and load-testing utilities |

---

## Non-Negotiable Rules

| Rule | Reason |
|---|---|
| Never modify `yaml.lua` without strong justification | Complex fixed bugs; regression corrupts note files |
| Check Telescope at call time, not load time | Lazy.nvim defers loading; `package.loaded` is wrong at module load |
| Never use `generic_sorter` for exact-match contexts | It applies fzy fuzzy matching; use `string.find(..., 1, true)` |
| Never reintroduce `status` field | Intentionally removed |
| Never use deprecated Neovim APIs | Use `nvim_set_option_value`, `vim.keymap.set` |
| Never reference `M` from another module | Each file's `M` is its own table; cross-module calls use `require` |
| Commands calling `init.lua` must use `require('pkm')` | `M` in `commands.lua` is not `init.lua`'s `M` |
| Never physically separate notes for project organisation | Projects are views over one namespace; multi-wiki is not a goal |
| Never optimize `collect_files` without benchmarking first | Baseline measurements are required before any performance work |

---

## Patterns to Use

Cross-platform paths:

    local utils = require('pkm.utils')
    local path  = utils.join(dir, file)
    local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)

OS detection:

    utils.is_windows  -- boolean
    utils.is_wsl      -- boolean

Exact substring matching (never fzy):

    if haystack:lower():find(needle:lower(), 1, true) then ... end

Telescope availability (at call time only):

    local ok = pcall(require, 'telescope')
    if ok then ... else ... fallback ... end

Calling init.lua functions from commands.lua:

    require('pkm').delete_note_safely()
    require('pkm').setup_sync_autocmds()

Neovim API (0.10+):

    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    vim.keymap.set('n', 'q', fn, { noremap = true, silent = true, buffer = buf })

---

## YAML Citation Structure — Do Not Change

    cites:
      notes:
        - identifier: note-0042
          title: "Note Title"
          link: "[[0042_note_Note_Title]]"
      bib: []
    cited_by:
      notes: []
      bib: []

---

## Debugging

    :lua print(vim.inspect(require('pkm').config))
    :messages
    :PKMStats

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

## Git Conventions

    <type>: <summary>

    - detail

Types: `feat` `fix` `docs` `refactor` `test` `chore`
Branches: `feat/<name>`, `fix/<name>`

---

*Update this document when the project state changes.*
