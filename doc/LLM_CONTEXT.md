# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read `doc/ARCHITECTURE.md` for the
architecture reference (layout, module responsibilities, config shape).
Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its principles
are non-negotiable constraints on all architectural decisions.

---

## Current version: **v1.10.1** (released, tagged) · **v1.11.0** code complete on `dev`, untagged

The canonical version is the top released entry in `doc/CHANGELOG.md`; this line
mirrors it. Everything under `[Unreleased]` there is on `dev` and awaiting a tag.
The v1.8.0 entry also carries what never got a release of its own: the counting
path planned as v1.6.1 Ph3, the index build of v1.6.2 Ph1, and deep export plus
the relative note (v1.7.0 Ph1–Ph2). Those two numbers were planning labels and
have no tag; nothing is missing between v1.6.1 and v1.8.0.
Remaining work is tracked in `doc/ROADMAP.md` § **Release Plan**; the standing
rules for executing it live in `doc/PRINCIPLES.md`.

---

## Module Map

Full module-by-module detail (role, key functions, invariants) is owned by
`doc/ARCHITECTURE.md` § **Module Responsibilities** — read there for anything beyond
quick orientation. Module list: `init, config, utils, commands, keymaps, yaml,
timestamp, citations, notes, journal, ui, telescope, templates, export, filter,
index, views, panel, mode, syntax, trash, markdown, bench, tags, picker, actions,
rename, bufsync, vault`.

`vault` (v1.11.0) owns the registry `vaults.json` — which vaults exist, and
which one a path belongs to. Nothing in it is required: a `root_path` with no
registry beside it answers an empty list and a nil vault, which is the state
every test file and `min_init` runs in.

The last five are the bulk-operation stack (v1.8.0): `tags` and `rename` hold the
rules and the writes, `picker` owns every selection screen, `actions` is the
registry every panel's `<C-a>` opens, and `bufsync` keeps open buffers in step
with what a batch wrote.

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
| Never physically separate notes for project organisation | Projects are views, not folders; all notes share one namespace **within a vault**. Vaults (v1.11.0) are separate namespaces that never communicate — not a way to organise projects |
| Never compare a vault path with a Lua pattern | Every vault folder is `NN - Name`; as a pattern the `-` is a lazy quantifier, so `00 - Alpha` matches `00 Alpha` and *not* `00 - Alpha`. Always `find(..., 1, true)` |
| Never switch the active vault without dropping what the old root produced | The index and **both** `views` caches — `views.json` lives *inside* the root, so a stale sidecar resolves one vault's views against another's notes |
| Never move or switch away from a vault with a modified buffer under it | The buffer would name a file in a folder that is gone; `:w` recreates the folder and resurrects the vault as a ghost. `vault.select` and `move_folder` both refuse |
| Never store an absolute vault path in the registry | `vaults.json` holds `{ number, name }`; the folder `NN - Name` is derived. Storing it is what makes a rename a search-and-replace |
| Never optimize without benchmarking first | Baseline measurements required; `bench.lua` is the gate |
| Never register `UndoPost` autocmd | Event does not exist in Neovim ≤ 0.11.x; tree-sitter tracks buffer changes via on_bytes |
| Never call `index.invalidate` from buffer-only metadata commands | No disk write occurred; re-index happens on user's next `:w` |
| Never strip backlinks in `trash_note()` | Backlinks preserved for restoration; `cleanup_deleted_note` only in `empty()` / `purge_old()` |
| Never run `git gc` on this repo | Google Drive sync causes object-directory deletion conflicts |
| Never touch a file twice within one phase | Each phase edits every file it touches in a single pass; see `doc/PRINCIPLES.md` § Execution for how to split work that doesn't fit one pass |
| Never call `vim.fn.confirm` / `input` right after closing a picker without `inputsave()` | They read the typeahead: the `<CR>` that closed the picker answers the dialog before it is drawn, and it vanishes unseen (v1.8.0 Ph7) |
| Never scan the vault per note in a batch | `citations.propagate_title` / `update_references_on_rename` glob and read three folders *per call*; use the batched form or it is quadratic |
| Never give a command both a count and a numeric argument | Vim reads a leading number in the arguments **as** the count: `:PKMHeaderNext 6` is six headers ahead, never level six. Spell such arguments non-numerically (`h6`) |
| Never verify a keymap with `normal!` | The bang skips mappings, so the check exercises the built-in keys and reports the feature broken (or working) for the wrong reason; use `normal` |
| Never write an assertion where the wrong behaviour gives the same answer | Name the reading it must exclude, then pick an input where the two diverge — see `doc/PRINCIPLES.md` § What a check has to prove |
| Never store an absolute path in vault state | The vault gets copied, moved and (soon) switched. `.pkm-trash/manifest.json` records `original_path` relative to the root; read it with `trash.resolve_original`. An absolute path in vault state is a pointer at whichever vault happened to be open when it was written |
| Never assert on an option a ftplugin also writes | Neovim's markdown ftplugin ends with `setlocal … shiftwidth=4` and runs after modelines, so `shiftwidth` reports 4 from `markdown.vim` whether or not the thing under test happened. Probe `numberwidth`, which no ftplugin touches, or assert the source `:verbose` names |
| Never give one path two jobs | `cleanup_deleted_note` used one argument as both the note's identity and the place to read its text; for a trashed note those differ, and `readfile` threw E484 on a path the note had already left (v1.10.1 Ph5) |

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

Exact substring matching (never fuzzy):
```lua
if haystack:lower():find(needle:lower(), 1, true) then ... end
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

Bulk write over a set of notes (disk write → invalidate → buffers → propagate):
```lua
local bufsync = require('pkm.bufsync')
bufsync.guard(paths, function()          -- asks only if a buffer is unsaved
  local applied = require('pkm.rename').apply_titles(plan)  -- writes + invalidates
  bufsync.reload(paths)                  -- unmodified buffers re-read from disk
end)
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
  original_path     : string  -- where it came from, RELATIVE to the root, '/'-separated
  title             : string  -- frontmatter title at deletion time; picker display
  deleted_at        : string  -- ISO 8601 UTC string; display only
  deleted_timestamp : number  -- os.time(); used for autoclear comparison
}
```

`original_path` is **relative since v1.10.1 Ph4** and must be read through
`trash.resolve_original(entry)`, never raw. Entries written by earlier versions
hold an absolute path, and if the tree was ever copied that path names a
different vault — which is how a restore from `NotesTeste` came to target
`P:\Notes`. `resolve_original` re-roots every form onto the current root.

---

## Debugging

```vim
:lua print(vim.inspect(require('pkm').config))
:lua print(vim.inspect(require('pkm.trash').list()))
:messages
:PKMStats
:PKMMode on
:lua require('pkm.yaml').validate_frontmatter()
:lua require('pkm.bench').baseline()
```

---

## Environment

| Item | Value |
|---|---|
| OS | Windows 10 + WSL (Ubuntu) |
| Editor | Neovim 0.11.3 |
| Plugin manager | Lazy.nvim |
| Plugin path | `P:/Active/pkm-nvim/` (Windows) · `/mnt/p/Active/pkm-nvim/` (WSL) |
| Vaults | `P:/Note-Vault/` — `01 - Vitruvia` (primary, never touched in development) · `00 - NotesTeste` (test vault; smoke notes and every experiment go here) |
| Vault paths contain spaces | `P:/Note-Vault/00 - NotesTeste`. Quote the whole flag in a shell: `-- "--root=P:/Note-Vault/00 - NotesTeste"`, or argv splits it. Verified unaffected: `vim.fn.glob`, `vim.fn.expand`, libuv scandir, and every `find(root, 1, true)` — the plugin's root comparisons all pass the plain flag |
| Config path | `~/AppData/Local/nvim/` (Windows) · `~/.config/nvim/` (WSL) |
| Git | Google Drive sync — object-DB rewrites forbidden (see Non-Negotiable Rules + Git Conventions) |

---

## Git Conventions

**Staging:** `git commit -a -m "..."` is the default — stages all modified
tracked files, no separate `git add`. If a single working session produces
multiple versions' worth of changes at once, do one `commit -a` covering
everything, then a separate `git tag -a vX.Y.Z` per version documented in
the CHANGELOG, all pointing at that same commit — not separate scoped
commits (`-a` sweeps in every modified tracked file regardless of what was
explicitly staged, so scoped multi-commit sequences don't combine with it).

**Push before test.** Neovim's Lazy.nvim pulls this plugin from GitHub, not
local files — changes have no effect on the running plugin until pushed and
pulled. Order: commit → push → `:Lazy sync` (or `:Lazy update`) + restart
Neovim → Standing Verification Protocol → only then tag → push tags.

**Commit format:**
```
<type>: <summary>

- detail
- detail
```
Types: `feat` `fix` `docs` `refactor` `test` `chore` `perf`

**Branches:** `dev` is the active development branch; `main` holds periodic stable
snapshots merged from `dev` via the `pkm-merge` alias — it is **not** an independently
maintained release line. Feature/fix work uses `feat/<name>` / `fix/<name>`.

**Versioning & tags:** see `doc/ROADMAP.md` § **Versioning Policy** — tags
(`git tag -a vX.Y.Z`) are applied only after every phase of a version has
landed and passed verification, never mid-version.

**Do not run `git gc`** on this repo — it lives on Google Drive sync, which
causes object-directory deletion conflicts. Global git config: `gc.auto 0`,
`gc.autoPackLimit 0`, `gc.autoDetach true`. The `pkm-merge` PowerShell alias
automates `dev→main` merges.

---

*Update this document as a batch after each version is completed, per the
Documentation Maintenance Cadence in the project instructions — not
continuously as project state changes.*
