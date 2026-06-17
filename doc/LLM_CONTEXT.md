# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read PKM_ROADMAP.md for architecture detail.
Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its principles
are non-negotiable constraints on all architectural decisions.

---

## Current State (v1.5.3, as of 2026-06-17)

All implementation phases (0–5) are complete. No items are in active development.

**What was completed across all phases:**
- Phases 0–2: bug triage; live filter browser (`:PKMBrowse`); metadata commands;
  `:PKMOrphans`, `:PKMBrowseRecent`; per-tabpage sidebar and bufpanel state;
  performance benchmarking; view rename/reparent
- Phase 3: unified explorer UI (`:PKMMode`, `:PKMExplorer`); improved renumber_sequence
  (nested lists, blockquotes, emphasis families, `list_bold_line`)
- Phase 4: tree-sitter syntax (frontmatter folding, citation/meta-comment highlights,
  suppressed 4-space code, list marker depth fix); §9 conventions implementation
- Phase 5: soft-delete trash system; `:PKMConvertList`; `type:` filter predicate;
  sidebar `<C-t>` type filter; `<C-s>` no-op in sidebar; note numbering skips trash

**Established decisions:**
- Trash is isolated to `.pkm-trash/` inside PKM root (not OS trash)
- Note numbers skip trashed entries permanently (gaps are intentional)
- `UndoPost` event does NOT exist in Neovim ≤ 0.11.x — never register it
- Persistent index: deferred (not warranted at current scale; ~125 ms at 500 notes)
- `_match_cache`: deferred (bench shows 3.1 ms/view at 10k notes; not warranted)

---

## Module Map

| File | Role |
|---|---|
| `init.lua` | Orchestration — setup, delete_note_safely (trash-aware), sync autocmds |
| `config.lua` | Pure data — defaults (incl. pkm_mode, trash), path resolution |
| `utils.lua` | Path join, OS flags, ensure_dir |
| `commands.lua` | All `:PKM*` commands — handlers lazy-require; browse_complete for filter DSL |
| `keymaps.lua` | All keymaps — receives `config` as parameter to `register(config)` |
| `yaml.lua` | YAML parse/generate — complex; do not touch without strong justification |
| `timestamp.lua` | Timestamp formats, filename generation |
| `citations.lua` | Bidirectional citation sync, tag index, add_tag/remove_tag (buffer-only) |
| `notes.lua` | Note CRUD, conversion, promotion, linking; set_title (buffer-only); get_next_note_number (checks trash manifest) |
| `journal.lua` | Journal creation; sync_filename_on_save |
| `ui.lua` | Fallback UI (no Telescope): browse, tags, recent, orphans, bufpanel |
| `telescope.lua` | All Telescope pickers — checked at call time via pcall, never load time |
| `templates.lua` | Template application |
| `export.lua` | Filter + copy notes — read-only, no setup(), export_direct for views |
| `filter.lua` | Filter DSL: tag/title/text/filename/type/any fields; any=bare-word/unknown-field |
| `index.lua` | In-memory index: {path, filename, note_type, title, tags, body, mtime, has_citations} |
| `views.lua` | Named views; two-mode sidebar with per-tabpage _tabs, type_filter; sidebar_build_lines(name, paths, total_count) |
| `mode.lua` | PKMMode: activate/deactivate/toggle/is_active; BufReadPost + DirChanged triggers |
| `syntax.lua` | Tree-sitter syntax: enable/disable per buffer; foldexpr/foldtext; matchadd highlights |
| `trash.lua` | Soft-delete: manifest.json, trash_note/restore_note/empty/purge_old; setup schedules purge_old via defer_fn |
| `markdown.lua` | Headers, renumber_sequence (nested/blockquote/emphasis), convert_list, symbols |
| `bench.lua` | Developer benchmarking suite — not user-facing |

---

## Non-Negotiable Rules

| Rule | Reason |
|---|---|
| Never modify `yaml.lua` without strong justification | Complex fixed bugs; regression corrupts note files |
| Check Telescope at call time, not load time | Lazy.nvim defers loading; `pcall(require, 'telescope')` at call site |
| Never use `generic_sorter` for exact-match contexts | Applies fzy; use `finders.new_dynamic` + `sorters.empty()` with `string.find(..., 1, true)` |
| Never reintroduce `status` field | Intentionally removed |
| Never use deprecated Neovim APIs | Use `nvim_set_option_value`, `vim.keymap.set` |
| Never reference `M` from another module | Each file's `M` is its own table; cross-module calls use `require` |
| Commands calling `init.lua` must use `require('pkm')` | `M` in `commands.lua` is not `init.lua`'s `M` |
| Never physically separate notes for project organisation | Projects are views, not folders; all notes share one namespace |
| Never optimize without benchmarking first | Baseline measurements required; `bench.lua` is the gate |
| Never register `UndoPost` autocmd | Event does not exist in Neovim ≤ 0.11.x; tree-sitter tracks buffer changes via on_bytes |
| Never call `index.invalidate` from buffer-only metadata commands | No disk write occurred; re-index happens on user's next `:w` |
| Never strip backlinks in `trash_note()` | Backlinks preserved for restoration; `cleanup_deleted_note` only in `empty()` / `purge_old()` |
| Never run `git gc` on this repo | Google Drive sync causes object-directory deletion conflicts |

---

## Key Patterns

Cross-platform paths:
```lua
local utils = require('pkm.utils')
local path  = utils.join(dir, file)
local files = vim.fn.glob(dir .. utils.sep .. "*.md", false, true)
```

Telescope availability (at call time only):
```lua
local ok = pcall(require, 'telescope')
if ok then ... else ... fallback ... end
```

Calling init.lua functions from commands.lua:
```lua
require('pkm').delete_note_safely()
```

Neovim API (0.10+):
```lua
vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
vim.keymap.set('n', 'q', fn, { noremap = true, silent = true, buffer = buf })
```

Per-tabpage state (used in views.lua and ui.lua):
```lua
local _tabs = {}
local function get_tab()
  local id = vim.api.nvim_get_current_tabpage()
  if not _tabs[id] then _tabs[id] = { win=nil, buf=nil, ... } end
  return _tabs[id]
end
-- setup(): register TabClosed autocmd to prune _tabs entries for closed tabs.
```

Buffer-only frontmatter mutation (no disk write, no index.invalidate):
```lua
local yaml_m = require('pkm.yaml')
local lines, content_start = yaml_m.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
-- modify frontmatter table
yaml_m.save_frontmatter(frontmatter, content_start)   -- Case A: buffer only
-- BufWritePost handles re-indexing on next :w
```

---

## Index Entry Shape

```lua
{
  path          : string    -- absolute path (normalized / separator)
  filename      : string    -- stem without extension
  note_type     : string    -- 'note'|'agg'|'bib'|'journal'|'scratch'|'other'
  title         : string    -- fm.title if set; else filename with _ → space
  tags          : string[]  -- lowercased frontmatter tags, or {}
  body          : string    -- note body joined with "\n"
  mtime         : number    -- vim.fn.getftime() at index time
  has_citations : boolean   -- true when any cites/cited_by group is non-empty
}
```

---

## YAML Citation Structure — Do Not Change

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

## Trash Manifest Entry Shape

```lua
{
  filename          : string  -- file name in .pkm-trash/ (may differ from original on collision)
  original_path     : string  -- absolute path before deletion; used for restore + numbering
  title             : string  -- frontmatter title at deletion time; picker display
  deleted_at        : string  -- ISO 8601 UTC string; display only
  deleted_timestamp : number  -- os.time(); used for autoclear comparison
}
```

---

## Debugging

```vim
:lua print(vim.inspect(require('pkm').config))
:lua print(vim.inspect(require('pkm.trash').list()))
:messages
:PKMStats
:PKMMode on
:lua require('pkm.yaml').validate_frontmatter()
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

## Git Conventions

```
<type>: <summary>

- detail
```

Types: `feat` `fix` `docs` `refactor` `test` `chore`
Branches: `feat/<name>`, `fix/<name>`
**Do not run `git gc`** — Google Drive sync conflict. `pkm-merge` alias handles `dev→main`.

---

*Update this document when the project state changes.*
