# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read PKM_ROADMAP.md for architecture detail.

---

## Current State (as of 2026-05-09)

Stable. All core features work. A structural refactor was just completed.

**Last session:** Extracted `config.lua`, `utils.lua`, `commands.lua`, `keymaps.lua`
from `init.lua`. All commands and keymaps verified working.

**Active next steps:** Module API headers, LuaDoc annotations, section separators.
These are additive — no behavior changes.

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
| `notes.lua` | Note CRUD, conversion, promotion, linking |
| `journal.lua` | Journal creation, filename-YAML sync |
| `ui.lua` | Fallback UI (no Telescope): stats, search, tags |
| `telescope.lua` | All Telescope pickers |
| `templates.lua` | Template application |
| `export.lua` | Filter + copy notes — read-only, no setup() |

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
| Commands that call `init.lua` functions must use `require('pkm')` | `M` in `commands.lua` is not `init.lua`'s `M` |

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
    if ok then ... else ... end

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
