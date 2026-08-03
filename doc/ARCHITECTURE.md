# PKM.nvim — Architecture Reference

Structural reference for the codebase: the on-disk layout, what each module is
responsible for, and how configuration is shaped. This document **owns** these
three concerns; other docs point here instead of restating them.

Source-of-truth ordering still applies: a source file read live from disk is
authoritative over this document. Where this file names exact defaults, function
signatures, or invariants, the code is canonical if they ever diverge — treat a
mismatch as a bug in *this* file and fix it here.

---

## File Structure

```
pkm.nvim/
├── lua/pkm/
│   ├── init.lua        # Orchestration: setup, delete_note_safely, sync autocmds
│   ├── config.lua      # Default config table and resolution logic (pure data)
│   ├── utils.lua       # Shared cross-platform utilities: path join, OS flags, notify
│   ├── commands/       # :PKM* registration, one file per context (handlers lazy-require)
│   │   ├── init.lua     #   wires every context; `register()` is the single entry point
│   │   ├── shared.lua   #   helpers used by more than one context (focus_main_win)
│   │   └── …            #   note, tag, cite, browse, view, vault, trash, list, header, panel, export, misc
│   ├── keymaps.lua     # All keymap wiring (receives resolved config)
│   ├── yaml.lua        # YAML frontmatter parsing and generation — handle carefully
│   ├── timestamp.lua   # Timestamp creation, parsing, formatting
│   ├── citations.lua   # Bidirectional citation engine, tag indexing, add/remove tag
│   ├── notes.lua       # Note CRUD, conversion, promotion, linking; set_title
│   ├── journal.lua     # Journal entry creation, filename sync
│   ├── ui.lua          # Fallback UI (no Telescope): browse, tags, bufpanel
│   ├── telescope.lua   # Telescope pickers: browse, tags, citations, tag merge
│   ├── templates.lua   # Template application to notes
│   ├── export.lua      # Note filtering and copy utility (read-only, no setup)
│   ├── filter.lua      # Filter DSL parser and evaluator (pure logic, no I/O)
│   ├── tags.lua        # Tag rules (pure), preview (read-only), batch apply (writes)
│   ├── picker.lua      # Shared note picker + confirmation float (Telescope or fallback)
│   ├── actions.lua     # Bulk-action registry over a set of notes (panel <C-a>)
│   ├── rename.lua      # Name substitution (pure), bulk title write + propagation
│   ├── bufsync.lua     # Open buffers vs. bulk disk writes (reload / ask / save)
│   ├── index.lua       # In-memory note index with incremental invalidation
│   ├── views.lua       # Named views: sidecar, CRUD, two-mode sidebar, type filter
│   ├── panel.lua       # Generic per-tabpage panel factory (winfixbuf, lifecycle)
│   ├── mode.lua        # PKMMode: session context toggle, syntax enable/disable
│   ├── syntax.lua      # FACADE re-exporting the pkm-syntax plugin (highlighting
│   │                   #   moved out; graceful no-op stub if the plugin is absent)
│   ├── trash.lua       # Soft-delete: manifest, trash/restore/empty/purge_old
│   ├── markdown.lua    # Markdown editing: headers, renumber, convert_list, wrap, symbols
│   └── bench.lua       # Benchmarking utilities (developer, not user-facing)
│   (queries/markdown/*.scm and the highlighting module now live in the separate
│    pkm-syntax repo — see "Highlighting: the pkm-syntax split" below)
├── plugin/pkm.lua      # Auto-load marker
├── doc/
│   ├── pkm.txt                    # Vim :help documentation (end-user, in-editor)
│   ├── ARCHITECTURE.md            # This file: layout, modules, config shape
│   ├── ROADMAP.md                 # Forward plan + how-to-execute (release/verify protocol)
│   ├── LLM_CONTEXT.md             # Fast-read session brief for LLMs
│   ├── LLM_PROJECT_INSTRUCTIONS.md# Coding standards, review protocol, doc cadence
│   ├── PHILOSOPHY.md              # Design principles (non-negotiable constraints)
│   ├── CONVENTIONS.md             # Note-content formatting conventions (in-text)
│   └── CHANGELOG.md               # Version history, known bugs, dead code
├── test/               # Headless test files (test_v<ver>_p<phase>.lua) + min_init.lua
└── README.md           # End-user onboarding
```

---

## Module Responsibilities

**init.lua** — pure orchestration. Calls `setup()` on every module, registers commands
and keymaps, sets up sync autocmds. Holds `delete_note_safely()` (uses trash if enabled,
permanent delete otherwise) and `setup_sync_autocmds()` (BufWritePre for `last_updated_on`,
BufWritePost for citation sync + silent reload + TS restart).

**config.lua** — pure data. Default config table and `resolve(user_config)`. Contains
`projects`, `pkm_mode`, `trash`, `frontmatter_templates`, all keymap defaults. No side
effects. This is the **canonical source of every config default** (see Configuration below).

**utils.lua** — `utils.join(...)`, `utils.sep`, `utils.normalize(path)`,
`utils.read_lines(path)` (readfile-equivalent reader that stays in LuaJIT —
drops a UTF-8 BOM, strips CR before LF, keeps a CR at EOF, empty file → `{}`;
used by the index build, where the VimL round trip per file was measurable),
`utils.ensure_dir(path)`, `utils.notify(msg, level?)` (emits `[pkm]`),
`utils.type_prefix(note_type)` / `utils.strip_display_prefix(filename, note_type)`
(shared display helpers used by `ui.lua` and `views.lua`), `utils.is_windows`,
`utils.is_wsl`. No `pkm.*` dependencies — safe to require from anywhere.

**commands/** — registers all `:PKM*` commands, split one file per context
(`note`, `tag`, `cite`, `browse`, `view`, `vault`, `trash`, `list`, `header`,
`panel`, `export`, `misc`). `init.lua` requires each and exposes the single
`register()` that `pkm.init` calls, so `require('pkm.commands')` is unchanged.
`shared.lua` holds the cross-context helpers (`focus_main_win`); each context
keeps its own (e.g. `browse.lua` holds `browse_complete`, the `:PKMBrowse`
filter-DSL autocomplete). Handlers use lazy `require`. This is the surface the
command clearup turns into verb-contexts, one file at a time.

**keymaps.lua** — `register(config)`. Receives resolved config; keymap strings
needed at registration time. Registers both normal and visual mode bindings for
range commands (`renumber_list`, `convert_list`, header level shift).

**yaml.lua** — YAML frontmatter parse and generation. **Do not modify without
strong justification.** Contains the non-trivial nested-empty-structure parser.
`save_frontmatter` retries transient write failures.

**timestamp.lua** — timestamps in multiple formats; creates filenames; parses timestamps.

**citations.lua** — bidirectional citation sync (`manage_backlink`, `update_references`,
`update_references_on_rename`, `cleanup_deleted_note`); `get_all_tags()`,
`get_citable_items_map()`; `merge_tags(sources, target)`;
`add_tag(tag?)` / `remove_tag(tag?)` — buffer-only frontmatter mutation.

**notes.lua** — note CRUD: `create_new_note`, `create_scratchpad`, `promote_note`,
`do_convert`, `convert_note`, `change_note_type`, `transpose_note`, `rename_note`,
`link_to_note`, `follow_link`, `show_backlinks`, `import_note`.
`set_title()` — buffer-only title mutation (no `index.invalidate`).
`get_next_note_number()` — checks both consolidated folder AND trash manifest.

**journal.lua** — journal creation (auto-timestamped); `sync_filename_on_save`.

**ui.lua** — fallback UI (no Telescope): `browse`, `browse_paths`, `browse_recent`,
`insert_citation_ui`, `merge_tags_ui`, `show_stats`.
`toggle_bufpanel()` / `is_bufpanel_open()` — per-tabpage buffer-list panel, built on
`panel.create`. Tag panel is also built on `panel.create`.

**telescope.lua** — all Telescope pickers. Checked at call time via `pcall`.
`browse`, `browse_paths`, `browse_recent`, `insert_citation_picker`,
`merge_tags_picker`. (Tag browsing lives in `tags.browse_by_tag` since v1.8.0 Ph3 —
both `browse_tags` implementations are gone.)

**export.lua** — filter + copy notes. No setup. Read-only. Delegates to filter.lua
and index.lua for matching, and to `picker.lua` for selection (v1.8.0 Ph2 — the
results picker used to live here). `export_direct(label, paths)` skips the filter form.
Deep export (v1.7.0 Ph1): `read_citation_edges(path)` returns the identifier lists
of both directions (grouped or legacy-flat frontmatter), and `collect_deep(seeds,
opts?)` walks the citation graph out from the seeds under a **per-path budget** —
`cites_depth` (2) hops along `cites` and `cited_by_depth` (0) along `cited_by`,
mixable in any order, counted from the seeds. Both are pure; `deep_export()` is the
UI entry that feeds their result to `export_direct`. Identifier→path resolution
reuses `citations.get_citable_items_map()`.

**filter.lua** — pure logic, no I/O. Grammar:
`field = tag | title | text | filename | type | any`.
`any`: bare words and unknown-field tokens; case-insensitive substring over all fields.
`type`: exact match against `entry.note_type`. `tag`: exact (case-insensitive).
`from_legacy(tbl)` converts `{tags_any, tags_all, title, text}`.
`tag_sets(tree)` (v1.8.0 Ph9) answers the inverse question — *what would make
this match* — as the expression in disjunctive normal form: alternatives of
`{add, remove, blockers}`, negation pushed down (De Morgan), where a blocker is a
condition no tag can produce. It is what makes "add this note to that view" a
computation rather than a guess. `NOT` binds to an atom, so `NOT NOT x` is a
parse error and `NOT (NOT x)` is the double negative.

**index.lua** — in-memory note index. Entry shape:
`{path, filename, note_type, title, tags, body, mtime, has_citations}`.
`note_type`: `note|agg|bib|journal|scratch|other`. `has_citations`: true when
any cites/cited_by group is non-empty.
Lazy build on first `get_all()`. Incremental invalidation via BufWritePost autocmd
and explicit `invalidate(path)` after every programmatic write or delete.
**Must NOT be called from buffer-only metadata commands** — no disk write occurred.
The build lists directories with `uv.fs_scandir` and reads files with
`utils.read_lines`; `vim.fn.glob`/`vim.fn.readfile` were measured as ~80% of it
(v1.6.2 Ph1). `mtime` still comes from `vim.fn.getftime` and the filename stem
from `vim.fn.fnamemodify` — both measured *faster* than their libuv/Lua
counterparts, so they stayed. Listing is unordered (nothing depends on it) and
no longer honours `'wildignore'`.

**views.lua** — named project views, and (for now) the sidebar container host.
Sidecar `views.json` + `config.projects`. Since **v1.49.0** the sidebar rides
`panel.create` (`_panel`, `name = 'sidebar'`): the panel owns the window / per-tab
state / width / lifecycle. Since **v1.51.0 (Phase 3.3a)** the sidebar hosts pluggable
content **providers** — `views` (built in) and `nav` (registered from `nav.setup` via
`register_sidebar_provider`). `state.provider` (per-tab) selects one; `sidebar_build`
DISPATCHES to `_sidebar_providers[provider].build_lines`. Switching provider swaps the
buffer's keymaps in place (teardown by lhs → apply the new set) so nav's colliding keys
(`<CR>`/`/`/`r`) never fight views'; `q`/`<Esc>` (close) and `<C-n>` (cycle) are common
and survive. The views provider's own state (`mode`/`name`/`paths`/`tree`/`header_count`/
`type_filter`/`marked`/`history`) rides the same per-tab table; `get_tab()` is a thin
alias over `_panel.get_state()`. Public: `show_sidebar_provider`/`cycle_sidebar_provider`/
`set_sidebar_provider`/`sidebar_provider`/`sidebar_provider_is`. (Lifting the container out
into a dedicated `pkm.sidebar` module is a later mechanical tidy.)
`sidebar_build_lines(name, paths, total_count)` — builds detail lines; callers
pre-filter by type and pass `#all_paths` as total for "N of M" display.
`refresh_sidebar_if_open()` — iterates all tabpages, applies per-tab type filter.
`edit_view(name?)` — action picker: edit filter / rename / reparent.
Query API: `match_all(name)` returns the matching paths, sorted by basename with
precomputed sort keys; `count_all(name)` / `count_many(names)` return counts only,
reading the index once per batch and skipping the path array and the sort. Every
"(N)" shown by an overview, panel or picker comes from the counting pair — never
from `#match_all` — which is what keeps overview cost linear in views, not in
views × sorts (see CHANGELOG, v1.6.1 Ph3, for the measured effect).
Note: the sidebar's *container* (window/lifecycle/width) was extracted onto
`panel.create` in v1.49.0. Its *content* still leans on the view-tree helpers
(`build_tree_entries`, `get_view_parent`/`get_view_children`, `match_all`), which
are shared with the panels/pickers — so the views-provider is not a standalone
module, and that is fine: those helpers are the model layer, and the sidebar UI is
just one consumer of it. The public sidebar accessors (`get_last_view`,
`is_sidebar_open`, `get_sidebar_win`, `refresh_sidebar_if_open`) now delegate to
`_panel`. As of Phase 3.3a the one container also hosts the `nav` provider.

**nav.lua** — current-file navigation, a **sidebar content provider** (not its own
container as of v1.51.0). Exposes `sidebar_provider` (a heading index of the last
active markdown window via `markdown.scan_headings`: `build_lines` + `<CR>` jump / `/`
filter / `c` clear keymaps + statusline + `on_enter` cursor placement) and registers it
with `views.register_sidebar_provider` from `setup()`. Tracks the source window with a
`WinEnter`/`BufWinEnter` autocmd (`_source`), refreshing the sidebar only while it is
showing nav. `capture_current()` seeds the source before the sidebar switches to nav.

**picker.lua** — note selection and confirmation front-ends. `select(paths, opts,
on_confirm)` shows the Telescope picker or the float fallback — the only place that
knows which — with one rule in both: `<CR>` with nothing marked confirms everything
currently listed, `<Tab>` narrows to marks. `opts.display` (v1.8.0 Ph3) is the row
renderer, which is what lets a batch preview be the same picker showing
"before → after" instead of a screen with its own gesture. `select_tag(rows, opts,
on_choice)` picks one tag from counted rows, previewing the notes that carry it and
showing each row's `note`; with `opts.allow_new` typing an unknown tag offers to
create it. Its sorter is pass-through, so the caller's ranking is what the user
sees; it takes the rows ready-made, so the module has no dependency on the tag engine.
`select_live(opts, on_confirm)` (v1.8.0 Ph7) is the one where the prompt *is* the
operation: `compute(prompt)` recomputes the rows on every keystroke, `display`
draws them and `preview` shows the result of the row under the cursor, so an
operation is written and seen in a single panel rather than a form followed by a
result screen. `confirm(opts)` remains for all-or-nothing gates (`<CR>` accepts,
`q`/`<Esc>` backs out) where a per-note choice would be a lie. Writes nothing
itself. Consumed by `export.lua`, `tags.lua` and `rename.lua`.

**bufsync.lua** — keeps open buffers in agreement with what a bulk write put on
disk (v1.8.0 Ph7). `reload(paths)` re-reads unmodified buffers and deliberately
skips modified ones; `unsaved(paths)` finds the notes open with pending edits and
`guard(paths, on_ready)` asks about them **only when there are any**, so the
common case is promptless. Consumed by `rename.lua` and `tags.lua`.

**rename.lua** — substitution over the names of a set of notes (v1.8.0 Ph7). The
notes in a selection do not share a name, so the input is a *substitution*, not a
value: one field holding `pattern/replacement`, the two halves of a `:%s`.
`parse_substitution(input)` splits it (first unescaped `/`; `\/` is literal) and
`plan_names(items, sub)` computes the result through **Neovim's own regex**
(`vim.fn.match` / `vim.fn.substitute`), so the expression that works in `:%s`
works here — which is also why there is no menu of operations: `^/X ` prepends,
`$/ X` appends, `pat/` removes. Not matching is reported as `matched = false`,
not as an error. `apply_titles(plan)` is the only writer: one frontmatter write
per changed note, `index.invalidate` on each, then a **single**
`citations.propagate_titles` pass. `title_flow(paths)` drives
`picker.select_live`.

Filenames (v1.8.0 Ph8) are the same substitution over a different field:
`split_stem` separates the fixed `NNNN_type_` prefix from the editable name so a
pattern can never touch identity, `stem_items` returns what may be renamed plus
what may not (journal and scratchpad names *are* their timestamp) with the
reason, `find_collisions` refuses a batch that would produce one name twice, and
`apply_filenames` renames through `notes.rename_file` and then rewrites every
reference with a single `citations.update_references_on_renames`.
`filename_flow` is the same panel, but its `<CR>` leads to an all-or-nothing
`picker.confirm`: a rename that half-applies leaves dangling links. Consumed by
`actions.lua` (`set_titles`, `rename_files`).

**actions.lua** — the bulk-action registry (v1.8.0 Ph4). Rows of
`{ id, label, run }`; `list()`/`get(id)` are pure, `run(paths)` shows the short
menu, `run_id(id, paths)` dispatches without one. Every navigation panel calls
`run(paths)` and knows nothing about what the actions do; every action receives
paths and knows nothing about panels. New bulk operations are appended here
rather than wired into panels again — and because the registry is data, it is the
first piece shaped for the planned `pkm.api`. Consumed by `telescope.lua`
(`live_picker` `<C-a>`) and `views.lua` (views panel `<C-a>`).

**tags.lua** — tag computation and batch application, in four layers:
`plan(tags, ops)` pure (every rule lives here — rename→remove→add, case-insensitive
matching, no duplicates, surviving tags keep their stored spelling, remove beats
add); `preview(paths, ops)` and `tag_counts(paths?)` read-only; `apply(paths, ops)`
the only writer, which **must** `index.invalidate` each note it writes — the mirror
image of the buffer-only `citations.add_tag`/`remove_tag`, which must not.
`tag_counts` sources tags from the index (so `Draft`/`draft` collapse into one row)
and restricts to a selection when given one; `rank_tags(rows, ctx)` is pure and
orders them by relevance to a selection (on some of it → co-occurring → by usage →
already on all of it), with `suggest_tags(paths?)` gathering that context
read-only; `format_change(item)` is pure so the
wording shown before a destructive write is testable, as are `scope_choices` and
`parse_command_args` (the `:PKMTags` argument contract). The interactive layer is
`browse_by_tag()` and `batch_on(paths, kind, ops?, header?)` — a selection that
already exists, straight to the tag prompt and the confirmation — with
`batch_flow(kind)` reduced to building a selection for callers that have none.
`view_flow(paths, kind, ctx)` (v1.8.0 Ph9) adds notes to a view or takes them out
by tags: it asks `filter.tag_sets` which tag sets satisfy the view's filter — or,
for removal, its negation — refuses when every alternative depends on a condition
tags cannot reach, and offers the choice when more than one route exists.
Consumed by `actions.lua`, `citations.merge_tags`, `notes.create_relative_note`
and `:PKMTags`.

**panel.lua** — generic per-tabpage panel factory. `create(spec)` returns an independent
panel object `{ open(init?), close(), toggle(init?), refresh(), refresh_all(), is_open(),
get_win(), get_state() }`, each owning its own per-tab state. Every panel gets
`winfixbuf = true` and a scoped augroup (debounced refresh, WinClosed/BufWipeout/TabClosed
lifecycle) uniformly. Optional `spec.width` makes it a **managed-width side split** (fix
width + `wincmd =` at open, re-assert on `WinResized`); optional `spec.on_open(state,
helpers)` is the per-panel decoration seam (statusline/winbar/extra autocmds). Consumed by
`ui` (buffer panel, tag panel), `trash` (restore panel), and `views` (the sidebar since
v1.49.0, which since v1.51.0 hosts the `views` and `nav` content providers, plus the
views/delete panels). Header/statusline hints,
content formatting, and filtering are deliberately NOT unified — panels differ enough there
that a shared format would fight real differences.

**mode.lua** — `M.activate()`, `M.deactivate()`, `M.toggle()`, `M.set(arg)`,
`M.is_active()`. Manages PKMMode session state: triggers index prebuild, opens
sidebar + bufpanel, enables syntax on all PKM buffers. `setup(config)` registers
BufReadPost (open_note trigger) and DirChanged (enter_dir trigger) autocmds.
Idempotent in both directions.

**syntax.lua** — a **thin facade** over the standalone `pkm-syntax` plugin (see
"Highlighting: the pkm-syntax split" below). It `pcall(require, 'pkm-syntax')`
and re-exports it unchanged, so every caller — `enable`/`disable`/`refresh_fold`/
`foldtext` and the `*_list_pattern` / `_find_*` exports — is untouched. If the
plugin is absent it degrades to a one-time warning plus a no-op stub, so the rest
of pkm-nvim still loads. The highlighting code itself (tree-sitter activation, the
PKMCitation/PKMListMarker/PKMMetaComment/subalínea highlights, the frontmatter
fold, and `queries/markdown/*.scm`) lives in pkm-syntax now.
**UndoPost does not exist in Neovim ≤ 0.11.x** — do not register it.

**Highlighting: the pkm-syntax split** — as of v1.44.0 the markdown highlighting
is a **separate plugin**, `pkm-syntax` (sibling repo, github.com/Vitruvia/pkm-syntax),
and **pkm-nvim depends on it** (add it to your plugin manager). It highlights any
markdown buffer with no dependency on note state, which is what let it be
extracted; `mode.lua` drives its `enable(bufnr[, highlight_only])` per buffer.
Keeping the highlighting in one place matters: two copies of `queries/markdown/`
on the runtimepath would double-apply the `; extends` query. Cross-repo rule:
pkm-syntax stays `Dependencies: none`; its public API is the contract this facade
depends on — change the two repos in lockstep.

**trash.lua** — soft-delete system. Trash folder: `{root}/.pkm-trash/`.
Manifest: `manifest.json` array of `{filename, original_path, title, deleted_at,
deleted_timestamp}`. `trash_note(filepath)` — moves file, does NOT strip backlinks.
`restore_note(entry)` — moves back, re-indexes; backlinks intact, no reconstruction.
`empty()` — permanent delete + `cleanup_deleted_note` for each entry.
`purge_old()` — auto-purge entries older than `max_age_days`.
`setup(cfg)` — stores config, schedules `purge_old()` via `vim.defer_fn(fn, 5000)`.

**markdown.lua** — `append_next_header`, `shift_header_level`,
`find_heading_target(lines, cursor, opts)` (pure ATX targeting: direction,
count, level filter; frontmatter and fenced code skipped) and its cursor
wrapper `goto_heading(opts)`, `setup_symbols`,
`renumber_sequence` (per-level counter stack; list/list_emph/list_bold_line/
hdr_prefix/hdr_suffix families; blockquote-aware),
`renumber_at_cursor`, `convert_list(start, end, direction?)`,
`convert_list_at_cursor(direction?)`.

**bench.lua** — developer benchmarking. Not user-facing. Four-phase suite: raw scan,
index build, index query, filter eval. `views_suite(opts?)` — scaling bench for
O(V × N) sidebar path. Self-cleaning; `baseline()` times real corpus read-only.

---

## Configuration

`config.lua` is the **canonical, exhaustive source** of every configuration key and its
default — it is pure data with inline documentation. This section maps the shape so you
know where to look; it does not re-list default values (that would drift from the code).
For user-facing configuration prose, see `pkm.txt` §11 CONFIGURATION.

`require('pkm').setup(opts)` merges `opts` over the defaults via `resolve()`, which also
resolves/normalizes `root_path`, validates it exists, and injects `user.name` into the
author-bearing frontmatter templates.

Top-level config sections (see `config.lua` for keys and defaults):

- `root_path` — notes root (required; defaults to `~/Notes`).
- `folders` — `scratchpad` / `journal` / `consolidated` / `templates` subfolder names.
- `sync` — `enabled`, `auto_sync_on_save` (citation/timestamp sync autocmds).
- `frontmatter_templates` — per-type YAML skeletons (`note`/`agg`/`bibliography`/
  `journal`/`scratchpad`), each with the `cites`/`cited_by` grouped structure.
- `timestamp` — `default_format` (`full`|`date_time`|`date_only`), `auto_timestamp`.
- `projects` — declarative named views (string filter, or `{parent, filter}` subproject).
  Sidecar `views.json` wins on collision; config-defined views cannot be renamed/deleted
  through PKM's own commands.
- `sidebar_width`, `display_mode` (`filename`|`title`) — sidebar/panel presentation.
- `user` — `name`, `email` (author injection).
- `symbols` — buffer-local insert-mode expansions for PKM notes.
- `pkm_mode` — `triggers` (open_note/enter_dir), `layout` (sidebar/bufpanel),
  `index.prebuild`, `syntax.enabled`.
- `trash` — `enabled`, `max_age_days`.
- `keymaps` — every default binding (set any to `false` to disable).
