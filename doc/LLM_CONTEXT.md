# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read PKM_ROADMAP.md for architecture detail.

Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its
principles are non-negotiable constraints on all architectural decisions.

---

## Current State (as of 2026-06-06)

Stable. All planned features through the views sidebar tree header are complete.
Active development is paused; next item is metadata commands.

**Last sessions:**
- Completed Phase 1: `filter.lua`, `bench.lua`, `index.lua`, `views.lua`
- 1.2.1: Multiple bug fixes; removed `quick_capture`, various dead code
- Added `markdown.lua`: `append_next_header`, `shift_header_level`, emphasis
  wrapping, `setup_symbols`, `goto_heading`
- Title decoupling: `title` is free-form; `sync_filename_on_save` and
  `sync_yaml_on_rename` removed; `:PKMRenameNote` added; `filename:` predicate
  added to `filter.lua`; `filename` field added to index entries
- `PKMBrowse`: unified note browser via index+filter; `PKMTags` now uses
  index+filter (ripgrep removed from tag browsing)
- `PKMViewLast`, `PKMViewSidebar` (flat list), subproject hierarchy in
  `get_tree()`, sidebar tree header with `<CR>` navigation and `<BS>` parent nav
- Deleted `journal.sync_yaml_on_rename`

**Active next steps:**
1. Metadata commands: `:PKMSetTitle`, `:PKMAddTag`, `:PKMRemoveTag` (buffer-only)
2. `:PKMViewNewSub` — create subprojects from a command
3. Performance benchmarks: `bench.views_suite()` for 50/100/300/1000 views
4. Investigate potential bugs: sidebar + tab pages, stale sidebar on delete,
   external file deletion in sidebar

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
| `notes.lua` | Note CRUD, conversion, promotion, transposition, linking; free-form title |
| `journal.lua` | Journal creation; timestamp-based filename sync |
| `ui.lua` | Fallback UI (no Telescope): stats, search, tags, browse, merge |
| `telescope.lua` | All Telescope pickers — checked at call time, never load time |
| `templates.lua` | Template application |
| `export.lua` | Filter + copy notes — read-only, no setup() |
| `filter.lua` | Filter expression parser/evaluator — tag/title/text/filename fields |
| `index.lua` | In-memory note index — {path, filename, title, tags, body, mtime} |
| `views.lua` | Named views — sidecar, CRUD, subproject hierarchy, sidebar, PKMViewLast |
| `bench.lua` | Developer benchmarking suite — not user-facing, no commands |
| `markdown.lua` | Markdown editing utilities — headers, emphasis, symbols, navigation |

---

## Non-Negotiable Rules

| Rule | Reason |
|---|---|
| Never modify `yaml.lua` without strong justification | Complex fixed bugs; regression corrupts note files |
| Check Telescope at call time, not load time | Lazy.nvim defers loading; `package.loaded` is wrong at module load |
| Never use `generic_sorter` for exact-match contexts | It applies fzy matching; use `finders.new_dynamic` with `string.find(..., 1, true)` |
| Never reintroduce `status` field | Intentionally removed |
| Never use deprecated Neovim APIs | Use `nvim_set_option_value`, `vim.keymap.set` |
| Never reference `M` from another module | Each file's `M` is its own table; cross-module calls use `require` |
| Commands calling `init.lua` must use `require('pkm')` | `M` in `commands.lua` is not `init.lua`'s `M` |
| Never physically separate notes for project organisation | Projects are views, not folders; all notes share one namespace |
| Never optimize `collect_files` without benchmarking first | Baseline measurements required before any performance work |

---

## Patterns to Use

Cross-platform paths:

    local utils = require('pkm.utils')
    local path  = utils.join(dir, file)
    local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)

Telescope availability (at call time only):

    local ok = pcall(require, 'telescope')
    if ok then ... else ... fallback ... end

Calling init.lua functions from commands.lua:

    require('pkm').delete_note_safely()

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
