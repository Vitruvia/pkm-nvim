# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read `doc/ARCHITECTURE.md` for the
architecture reference (layout, module responsibilities, config shape).
Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its principles
are non-negotiable constraints on all architectural decisions.

---

## Current version: **v1.26.1** (code-complete on `dev`) — patch: keymap-help panel fixes

*v1.26.1 (patch, author-reported, interactive surface — needs a real-config smoke):
closing a Telescope picker's `?` help now **resumes the picker** instead of dropping
to the editor (a `telescope_help` helper closes the picker cleanly, shows the float,
resumes on close; split/sidebar help was already fine), and the help float's width
fits the longest line up to the editor width (was hard-capped at 60, overflowing the
sidebar help). Code in `lua/pkm/views.lua` (`show_keymap_help` + the three Telescope
`?` handlers). Sits on v1.26.0, which completed the retrieve-before-working surface
(§ 11.6) with one call.*

*v1.26.0 completes the retrieve-before-working surface (§ 11.6) with one call.
**`api.context(term, opts?)`** composes the two reads: it `find`s the top
`opts.seeds` (default 3, relevance-ranked, active vault), expands each by its
citation `neighborhood` (`cites_depth`/`cited_by_depth`, default 1 each), then
merges, de-duplicates, and annotates — every note carries `relation` (`'seed'` for a
search hit, `'linked'` for a graph pull-in), seeds first by score then linked by
title, and a note reached both ways stays a `seed` with no duplicate row. Returns
`{ ok, query, seeds, notes }`; pure composition of `find` + `neighborhood`,
single-vault. The retrieval thread is now substantially complete: `find` · `find_all`
· relevance ranking · `read` · `neighborhood` · `context`. `test_v1260_p1`;
**re-run `:PKMAgentProtocol install`** for the skill. It sits on v1.25.0, step 3
(the RAG/OKF navigation reads):*

*v1.25.0 is step 3 of the retrieval thread (ROADMAP Area 1): the protocol's
"retrieve before working" (§ 11.6) becomes two API reads over the citation graph.
**`api.read(ref)`** returns one note in full — its body plus its **resolved**
citation edges (`cites`/`cited_by`, each `{ ref, title, path, note_type }`) — the
retrieval atom, accepting a path or a citation reference (with a direct-parse
fallback for a note the active index does not hold). **`api.neighborhood(ref,
opts?)`** returns the citation-connected cluster around a note as readable entries,
walking `export.collect_deep` to `cites_depth`/`cited_by_depth` (default 1 each),
seed excluded. Both single-vault (the graph never crosses vaults). The skill now
names them as the retrieve-before-working mechanisms; **re-run `:PKMAgentProtocol
install`**. `test_v1250_p1` (a Referrer→Hub→{two sources} graph). It sits on
v1.24.0 (relevance ranking), step 2 of the retrieval thread:*

*v1.24.0 is step 2 of the retrieval thread (ROADMAP Area 1): `find`/`find_all` now
surface the closest match first. Each matched note carries a `score` and the `notes`
list is ordered best-first — tiers, strongest first: exact title (100), prefix (70),
word-boundary mid-title (50), substring mid-word (35), filename prefix (25)/substring
(15); an earlier position adds a small within-tier bonus, a matching tag boosts
(exact +15, partial +5, only lifting a note already matched by title/filename), and
recency (mtime) breaks ties. `tags` lead with the exact match. Shared `score_note` /
`ranked_notes` / `ranked_tags` helpers back both (`query`, a boolean filter, is not
ranked). It also **fixed** a `find_all` bug from v1.23.0: the no-registry active-root
fallback read `require('pkm.config').root_path` (always nil — resolved config is at
`require('pkm').config`), so `find_all` returned no vaults when none were registered;
registered-vault sweeps were unaffected. `test_v1240_p1`. Also this session, a
**persistent-index decision** (docs+bench, unversioned): weighed for interop —
headless agent calls are cold per call, so each re-pays the index build and
`find_all`'s `scan_root` re-reads every non-active vault (`bench.find_all_bench`:
~0.16 ms/note → ~96–975 ms for a 3-vault `find_all` at 200–2000 notes/vault) —
**deferred** behind two gates (let retrieval features define the read shape; build
only on a real-vault baseline), with the interim win shipped: the skill tells the
agent to **batch a task into one headless session** (index builds once, stays warm).
It sits on v1.23.0, step 1 of the retrieval thread: it closes the gap the
formal eval confirmed — `find`/`query` read only the active vault, so "which of my
vaults holds X" forced a filesystem grep. **`api.find_all(term)`** is the
cross-vault twin of `find`: it sweeps every registered vault (and the active root)
and groups matches per vault (`{ vault, number, root, active, notes, tags }`),
case- and accent-insensitively over titles, filenames, and tags (views stay
per-vault, `find`'s job). It reads each non-active vault straight from disk via the
new **`index.scan_root(root)`** — a per-root reader that builds nothing and never
touches the active singleton index — so it is safe to call from any vault. The
skill now routes cross-vault discovery to `find_all` instead of a filesystem grep
(grep stays a deeper fallback for body text); **re-run `:PKMAgentProtocol
install`**. `test_v1230_p1` proves the decisive case (a term unique to the
non-active vault, which `find` misses and `find_all` catches). It sits on v1.22.0
(released, tagged), the first code thread of the post-eval plan: it closes the
reference-recording gap both evals flagged, so a source becomes a citable **bib
note**, not a freetext line. **`api.cite_source(citing_ref, source, opts?)`** finds
the source's bib note (by `source.title`, exact then substring, among indexed `bib`
notes in the active vault) or creates one with the standard citation at the top
(`source.bibtex`, BibTeX preferred; optional `source.notes`; `by` defaults to
`claude`), then cites it — placing the token **under a `## References` heading**
(default, created if absent; `opts.heading = false` appends at the body's end, the
old `cite` behaviour). Idempotent (`cited = false` when already present),
single-vault like every citation, and it wraps `notes.write_new_note` + `citations`
+ `write_section`/`write_body` without reimplementing a core (`test_v1220_p1`). The
**bib doctrine** landed in `doc/AGENT_PROTOCOL.md` § 10 (consult `P:\Recursos` + web;
find-or-create the bib note; a precise bib note is the one encouraged exception to
"don't write the user's vault"; copy between vaults with markers; never alter a
user-authored bib note without permission), with `doc/CONVENTIONS.md`
§ Bibliography Notes for the format and § 7 naming the exception. **Re-run
`:PKMAgentProtocol install`** to redistribute the skill. It sits on v1.21.0
(docs-only, driven by the first formal evaluation, the "ringforge" task, verified on
disk): `doc/AGENT_PROTOCOL.md` § 11 — a memory-organization doctrine (memory = lean
index/pointer layer; vault = body of studied knowledge; write by seriousness tier;
organize by life-area; vault authoritative for studied knowledge, memory for
facts-about-the-user and how-to-operate) — plus § 5.3 directive 6 (ask only for
genuine forks) and SKILL updates (memory doctrine; filesystem search for cross-vault
discovery since `find`/`query` are single-vault; titles default to the filename),
and § 11.6 (learning is retrieval + revision, not only capture). It sits on
v1.20.0, which added `api.ui_state` — a plain-data snapshot of the interactive UI
(current buffer, sidebar/buffer-panel open state, the highlighted view) that is
the *inspect* half of agent-assisted smoke testing: an assistant drives a headless
Neovim's real mappings with `feedkeys`, then reads `ui_state` to assert the path
behaved (the interactive part the unit suite can't see; proven in
`test_v1200_p1`). It also added `doc/AGENT_PROTOCOL.md` § 10 — notes are
provisional knowledge: cross-check a retrieved note against current knowledge and
sources, read a user's note as situated/partial, and record provenance (author,
date, references by edition-year or visit-date) on write. It sits on v1.19.0,
which added `api.annotate` — a `By Claude: `-marked comment added to a note
that is **not** the assistant's own, at a section or note boundary, marker baked
in, the user's text untouched (over `notes.annotate` → `write_section`/
`write_body`). It completes the note-writing surface the protocol described. It
sits on v1.18.0, which added the note-lifecycle **writes** to `pkm.api`:
`api.rename`,
`api.changetype`, and `api.transpose` (covering promote + transpose), backed by
three pure headless seams in `notes.lua` (`convert_file`, `changetype_file`,
`rename_note_at`) — the twins of the interactive commands, which are left
untouched. Plus the gestor wraps `api.set_membership` / `save_subproject` and the
vault-wide `api.rename_tag` (subsuming `tags.merge`). A gestor-mode agent can now
restructure a vault through the surface. It sits on v1.17.0, which added
`api.insert_section` (placement-aware body writing — append/replace a named
section, reusing the exported `markdown.scan_headings`) and fixed the standing
`PKMCitation` highlight bug (the `matchadd` regex never fired), on top of
v1.16.0, which shipped `require('pkm.api')` (a data-only, headless surface over the
cores: create/body/cite/tag/find/query/audit/export/…), `doc/AGENT_PROTOCOL.md` +
`doc/PKM_API.md`, the `pkm-notes` skill and `:PKMAgentProtocol` installer, the
`/pkm-learning` learning modes, and the `:PKMHeader sibling` next-header (planned
as v1.15.0, shipped here). Validated by a real evaluation — with the skill
installed the assistant drove the vault through pkm.api, discovered a subject that
is a view via `find`, and wrote an authored, bodied note, with no raw-file edits.
v1.13.0–v1.14.0 had finished the command clearup; the surface is now **16
commands** (12 verb-contexts + `:PKMCheck`/`:PKMStats`/`:PKMToggleAutoSync`/
`:PKMTags`), no aliases.*

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
rename, bufsync, vault, args, check, api, skill`.

`api` (v1.16.0) is `require('pkm.api')`, the data-only, headless, no-UI surface an
LLM assistant drives the vault through — it wraps the cores (never reimplements),
reports what each write changed, and keeps the index/graph in step. `skill`
(v1.16.0) installs the `pkm-notes` skill and the `/pkm-learning` command into the
user's Claude Code dirs. The policy is `doc/AGENT_PROTOCOL.md`; the reference and
headless JSON contract are `doc/PKM_API.md`.

`commands` (v1.13.0) is a **directory**, not a file: one module per verb-context
(`note, tag, cite, browse, view, vault, trash, list, header, panel, export, agent,
misc`), wired by `commands/init.lua`, which exposes the single `register()`
`pkm.init` calls — so `require('pkm.commands')` is unchanged. Each context is
`:PKM<Context> <verb>` dispatched through `args`. **v1.14.0 deleted the aliases**;
**v1.16.0 added `:PKMAgentProtocol`** (the skill installer): the surface is 16
commands (12 contexts + `:PKMCheck`/`:PKMStats`/`:PKMToggleAutoSync` + `:PKMTags`,
the vault-wide bulk tag command). `commands/shared.lua` holds cross-context
helpers.

`args` (v1.12.0) is the one reading of a command's arguments —
`:PKM<Context>[!] <verb> [positional] [key=value]` → `{verb, positional, named,
bang, is_verb}`; `views` and `tags` parse through it, and every typed form uses
it. `check` (v1.12.0) is the read-only `:PKMCheck` audit: pure, returns findings,
built to never report a false positive.

`tags`, `picker`, `actions`, `rename` and `bufsync` are the bulk-operation stack
(v1.8.0): `tags` and `rename` hold the rules and the writes, `picker` owns every
selection screen, `actions` is the registry every panel's `<C-a>` opens, and
`bufsync` keeps open buffers in step with what a batch wrote.

`vault` (v1.11.0) owns the registry `vaults.json` — which vaults exist, which
one a path belongs to, and which one opens by default. Nothing in it is
required: a `root_path` with no registry beside it answers an empty list and a
nil vault, which is the state every test file and `min_init` runs in.

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
| Never derive a write location from `root_path` | `vaults_path` names the vaults directory outright, and nothing guesses it. Deriving it from the root's parent means any stale or temporary root nominates its parent as the place the registry is written into |
| Never optimize without benchmarking first | Baseline measurements required; `bench.lua` is the gate |
| Never register `UndoPost` autocmd | Event does not exist in Neovim ≤ 0.11.x; tree-sitter tracks buffer changes via on_bytes |
| Never call `index.invalidate` from buffer-only metadata commands | No disk write occurred; re-index happens on user's next `:w` |
| Never strip backlinks in `trash_note()` | Backlinks preserved for restoration; `cleanup_deleted_note` only in `empty()` / `purge_old()` |
| Never run `git gc` on this repo | Google Drive sync causes object-directory deletion conflicts |
| Never touch a file twice within one phase | Each phase edits every file it touches in a single pass; see `doc/PRINCIPLES.md` § Execution for how to split work that doesn't fit one pass |
| Never call `vim.fn.confirm` / `input` right after closing a picker without `inputsave()` | They read the typeahead: the `<CR>` that closed the picker answers the dialog before it is drawn, and it vanishes unseen (v1.8.0 Ph7) |
| Never scan the vault per note in a batch | `citations.propagate_title` / `update_references_on_rename` glob and read three folders *per call*; use the batched form or it is quadratic |
| Never give a `-count` command a numeric argument | Vim reads a leading number **as** the count: the old `:PKMHeaderNext 6` meant six headers ahead, never level six — which is why the header context spells the level `h6`, takes a `range` not a count, and reads its motion count as an explicit argument (`:PKMHeader next 3`) |
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
:PKMPanel mode on
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
