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
│   ├── commands.lua    # All :PKM* command registration (handlers lazy-require)
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
│   ├── index.lua       # In-memory note index with incremental invalidation
│   ├── views.lua       # Named views: sidecar, CRUD, two-mode sidebar, type filter
│   ├── panel.lua       # Generic per-tabpage panel factory (winfixbuf, lifecycle)
│   ├── mode.lua        # PKMMode: session context toggle, syntax enable/disable
│   ├── syntax.lua      # Tree-sitter syntax management: highlights, folding, matches
│   ├── trash.lua       # Soft-delete: manifest, trash/restore/empty/purge_old
│   ├── markdown.lua    # Markdown editing: headers, renumber, convert_list, symbols
│   └── bench.lua       # Benchmarking utilities (developer, not user-facing)
├── queries/markdown/
│   ├── highlights.scm  # PKM tree-sitter captures: indented code, list markers
│   └── injections.scm  # YAML injection into frontmatter (minus_metadata nodes)
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
`utils.ensure_dir(path)`, `utils.notify(msg, level?)` (emits `[pkm]`),
`utils.type_prefix(note_type)` / `utils.strip_display_prefix(filename, note_type)`
(shared display helpers used by `ui.lua` and `views.lua`), `utils.is_windows`,
`utils.is_wsl`. No `pkm.*` dependencies — safe to require from anywhere.

**commands.lua** — registers all `:PKM*` commands. Handlers use lazy `require`.
Contains `browse_complete` (filter DSL autocomplete for `:PKMBrowse`).

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
`browse_tags`, `insert_citation_ui`, `merge_tags_ui`, `show_stats`.
`toggle_bufpanel()` / `is_bufpanel_open()` — per-tabpage buffer-list panel, built on
`panel.create`. Tag panel is also built on `panel.create`.

**telescope.lua** — all Telescope pickers. Checked at call time via `pcall`.
`browse`, `browse_paths`, `browse_recent`, `browse_tags`, `insert_citation_picker`,
`merge_tags_picker`.

**export.lua** — filter + copy notes. No setup. Read-only. Delegates to filter.lua
and index.lua. `export_direct(label, paths)` skips the filter form.

**filter.lua** — pure logic, no I/O. Grammar:
`field = tag | title | text | filename | type | any`.
`any`: bare words and unknown-field tokens; case-insensitive substring over all fields.
`type`: exact match against `entry.note_type`. `tag`: exact (case-insensitive).
`from_legacy(tbl)` converts `{tags_any, tags_all, title, text}`.

**index.lua** — in-memory note index. Entry shape:
`{path, filename, note_type, title, tags, body, mtime, has_citations}`.
`note_type`: `note|agg|bib|journal|scratch|other`. `has_citations`: true when
any cites/cited_by group is non-empty.
Lazy build on first `get_all()`. Incremental invalidation via BufWritePost autocmd
and explicit `invalidate(path)` after every programmatic write or delete.
**Must NOT be called from buffer-only metadata commands** — no disk write occurred.

**views.lua** — named project views. Sidecar `views.json` + `config.projects`.
Two-mode sidebar (overview + detail); per-tabpage `_tabs` state including `type_filter`.
`sidebar_build_lines(name, paths, total_count)` — builds detail lines; callers
pre-filter by type and pass `#all_paths` as total for "N of M" display.
`refresh_sidebar_if_open()` — iterates all tabpages, applies per-tab type filter.
`edit_view(name?)` — action picker: edit filter / rename / reparent.
Note: the sidebar's per-tabpage `_tabs` state and the view-tree helpers
(`build_tree_entries`, `get_view_parent`/`get_view_children`) are shared with the
panels/pickers and with the public sidebar accessors (`get_last_view`,
`is_sidebar_open`, `get_sidebar_win`), so the sidebar is **not** cleanly separable
into its own module — extraction would require a bidirectional dependency and a
wider public surface. A cleaner split, if ever pursued, is to extract the *model*
layer (sidecar + tree helpers + `match_all`), not the sidebar UI.

**panel.lua** — generic per-tabpage panel factory. `create(spec)` returns an independent
panel object `{ open(init?), close(), toggle(init?), refresh(), is_open(), get_win() }`,
each owning its own per-tab state. Every panel gets `winfixbuf = true` and a scoped
augroup (debounced refresh, WinClosed/BufWipeout/TabClosed lifecycle) uniformly. Consumed
by `ui` (buffer panel, tag panel), `trash` (restore panel), and `views` (views/delete
panels). Header/statusline hints, content formatting, and filtering are deliberately NOT
unified — panels differ enough there that a shared format would fight real differences.

**mode.lua** — `M.activate()`, `M.deactivate()`, `M.toggle()`, `M.set(arg)`,
`M.is_active()`. Manages PKMMode session state: triggers index prebuild, opens
sidebar + bufpanel, enables syntax on all PKM buffers. `setup(config)` registers
BufReadPost (open_note trigger) and DirChanged (enter_dir trigger) autocmds.
Idempotent in both directions.

**syntax.lua** — per-buffer tree-sitter activation. `M.enable(bufnr)`: starts
markdown TS parser, defines HL groups, registers per-window matchadd highlights
(PKMCitation, PKMMetaComment) and window opts (foldmethod=expr, foldtext).
`M.disable(bufnr)`: stops TS, clears matches, restores opts, runs `syntax on`.
`M.foldexpr(lnum)`, `M.foldtext()`.
**UndoPost does not exist in Neovim ≤ 0.11.x** — do not register it.

**trash.lua** — soft-delete system. Trash folder: `{root}/.pkm-trash/`.
Manifest: `manifest.json` array of `{filename, original_path, title, deleted_at,
deleted_timestamp}`. `trash_note(filepath)` — moves file, does NOT strip backlinks.
`restore_note(entry)` — moves back, re-indexes; backlinks intact, no reconstruction.
`empty()` — permanent delete + `cleanup_deleted_note` for each entry.
`purge_old()` — auto-purge entries older than `max_age_days`.
`setup(cfg)` — stores config, schedules `purge_old()` via `vim.defer_fn(fn, 5000)`.

**markdown.lua** — `append_next_header`, `shift_header_level`, `setup_symbols`,
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
