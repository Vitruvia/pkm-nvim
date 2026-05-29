# PKM.nvim — Changelog

---

## Unreleased

### Known Bugs (queued)

- `bench.lua`: `utils.join` uses `\` separator on Windows/WSL, producing
  malformed paths when bench_dir is a Unix-style path (e.g. `/tmp/pkm_bench`).
  Files are still created correctly because vim.fn.mkdir/glob tolerate mixed
  separators on WSL. Fix: accept bench_dir as-is and join subdirs with the
  correct separator for the path type, or document that bench_dir must use
  the native separator.

- **`PKMInsertCitation` has no non-Telescope fallback** — the command calls
  `require('pkm.telescope').insert_citation_picker()` directly. After the
  1.2.1 telescope.lua refactor this degrades to a `vim.notify` warning rather
  than silently doing nothing, but there is no `vim.ui.select` fallback path.
  `ui.lua` would need a `select_note_for_citation()` function to complete the
  fallback.

### Benchmarks — post-index integration (bench_dir on NTFS/WSL, P: drive)

  - 10k notes: raw 1966ms, build 1510ms, query 0.20ms, filter 6.6ms
  - Post-index query + filter: ~6.8ms vs ~1966ms raw (~290× improvement)
  - 100k projection (raw scan): ~14.2s; post-index: ~65ms
  - Previous run used Linux tmpfs (raw ~1449ms at 10k); difference is
    filesystem speed, not a regression.

### Suspended Functions (queued for decision)

- **`journal.sync_yaml_on_rename`** — reads the journal filename, parses the
  timestamp from it, and writes `date` and `time` fields back into YAML.
  Called from the `BufReadPost` autocmd in `init.lua`.

  Was silently broken by the greedy pattern bug — the function exited without
  writing anything. When the pattern was fixed in 1.1.1, it began writing
  `date` and `time` to every journal note on open. These fields are not in
  the journal template and conflict with the `created_on`/`last_updated_on`
  design.

  **Current state:** the `BufReadPost` call in `init.lua` is commented out.
  The function definition in `journal.lua` is left intact.

  **Options:**
  - Delete — if `date`/`time` fields are never wanted.
  - Add to template and reinstate — if split date/time fields are wanted.
  - Replace with a function that syncs `created_on` from the filename instead.

  Note: `notes.sync_yaml_on_rename` (consolidated folder) is unrelated — it
  syncs `title` only and is not affected.

### Dead Code (queued for removal)

- `normalize_path(path)` in `notes.lua` — defined but never called.
- `is_empty_table(t)` in `yaml.lua` — defined but never called.
- `is_array_table(t)` in `yaml.lua` — defined but never called.
- `show_stats_window(stats)` in `ui.lua` — stats table never constructed;
  `show_stats()` is the live implementation.
- `select_note_enhanced` in `ui.lua` — defined but not called from any command.
- `normalise_tags` in `export.lua` — no longer called after `match_file`
  rewrite.

## [1.2.1] — 2026-05-28

### Fixed

- **`telescope.lua` load-time Telescope check** — top-level
  `pcall(require, 'telescope')` + `if not has_telescope then return M end`
  made the entire module return an empty table if Telescope had not yet loaded
  (always the case under Lazy.nvim deferred loading). Removed the early return.
  Added `require_telescope()` helper that checks availability at call time and
  returns a table of all sub-modules. All five exported functions now call this
  helper as their first act, consistent with the project-wide pattern.

- **`PKMSearch` and `PKMTags` had no Telescope fallback** — both commands
  called `require('pkm.telescope')` directly. Now use
  `pcall(require, 'telescope')` with fallback to `ui.search_notes()` and
  `ui.browse_tags()`, matching the established `PKMMergeTags` pattern.

- **`templates.lua` `apply_template` silently failed when Telescope was
  loaded** — the Telescope branch called `tele.template_picker()`, an empty
  stub. Removed the Telescope branch entirely; `vim.ui.select` is now the
  unconditional implementation.

- **Rename from inside note required manual `:e!`** — `rename_from_yaml` used
  `vim.cmd("file ...")` to redirect the buffer after an atomic filesystem
  rename. `:file` marks the buffer as modified even when disk content is
  correct. Changed to `vim.cmd("keepalt file ...")` + `vim.bo.modified = false`
  to redirect cleanly without the spurious modified flag.

- **Same buffer-redirect bug in `change_note_type`** — identical root cause
  and fix: `keepalt file` + `vim.bo.modified = false`.

- **Secondary E484 on rename** — `BufWritePost` calls `sync_filename_on_save`
  (which renames the file) and then `update_references(old_filepath)`. After
  rename, the old path no longer exists; `migrate_legacy_links` attempted
  `vim.fn.readfile(old_filepath)` and threw E484. Added a `filereadable` guard
  at the top of `update_references`: exits silently when `target_file` is
  provided but no longer readable.

- **Journal greedy pattern bug (CHANGELOG entry was stale)** —
  `find_by_date_range`, `list_recent`, and `find_by_tag` in `journal.lua`
  already use `filename:match("^journal_(.+)$")`. The Known Bugs entry
  incorrectly described them as still using the old greedy pattern.

- **Write-only captures in `update_references_on_rename`** — `old_type` and
  `new_type` were assigned from `get_note_type_and_id` but their values were
  never read. Replaced both with `_`.

- **`ftype` write-only in `get_citable_items_map`** — second return value of
  `uv.fs_scandir_next` was named `ftype` but never read. Replaced with `_`.

- **Duplicate comment in `update_references`** — `-- 5. Scan Text for
  Citations` appeared twice. Duplicate removed.

- **`PKMInsertCitation` now has a `vim.ui.select` fallback** — the command
  previously called `insert_citation_picker()` directly with no fallback.
  Added `M.insert_citation_ui()` to `ui.lua` and updated the command to use
  the `pcall`/fallback pattern matching the other picker commands.

### Removed

- **Dead code:**
 - `is_empty_table` and `is_array_table` in `yaml.lua` — the two functions
   only called each other; nothing outside the pair called `is_array_table`.
   `generate_yaml` uses its own inline array check. Both deleted.
 - `normalise_tags` in `export.lua` — orphaned by the `filter.lua` rewrite;
   `match_file` now delegates to `filter.eval()`. Deleted.
 - `normalize_path` in `notes.lua` — defined but never called. Deleted.
 - `show_stats_window`, `select_note_enhanced`, `show_graph`, `show_analytics`
  in `ui.lua` — none called from any command or live code path. Deleted.

- **`M.quick_capture()`** in `notes.lua` — the function assumed a "daily
  aggregator" scratchpad (one file per day, entries appended with timestamp
  headings) that has no basis in the system design. Scratchpads are independent
  timestamped notes; there is no "today's scratchpad" concept. Removed the
  function, the `quick_capture` keymap entry from `config.lua` and
  `keymaps.lua`, and the `:PKMQuickCapture` documentation.
  `:PKMNewScratchpad` is the replacement; the title prompt can be dismissed
  with Enter for minimum friction.

- **`M.template_picker` stub** in `templates.lua` — empty function, never
  called externally, listed as dead code since 1.1.3. Deleted.

## [1.2.0, dev-view] - 2026-5-16

### Added
- `docs/PHILOSOPHY.MD` - a brief on the project's philosophy and scope.
- `lua/pkm/views.lua` — named project views over the note index.
  - `views.list()` → sorted view names from `config.projects`
  - `views.match_all(name)` → sorted paths matching the view's filter
  - `views.open(name?)` → activates a view; prompts for name if nil.
    Telescope picker with exact-substring prompt and file preview, or
    scrollable float fallback. Filter trees cached after first parse.
- `config.lua`: added `projects = {}` to defaults.
- `commands.lua`: `:PKMView [name]` — open a named view (tab-completes
  view names). `:PKMViews` — list all defined views.

## [1.1.6, dev-view] — 2026-05-16

### Fixed
- `index.lua`: `get()` and `invalidate()` now normalize path separators
  (`\` → `/`) before key lookup. Previously, callers passing Unix-style paths
  on Windows received nil even for indexed files.

## [1.1.5, dev-view] — 2026-05-16

### Added
- `lua/pkm/filter.lua` — new module: filter expression parser and evaluator.
  No I/O, no Neovim API calls. Fully testable in isolation.
  - `filter.parse(expr)` → `tree, nil` | `nil, error_string` — hand-rolled
    recursive descent parser for the boolean filter DSL (fields: `tag`,
    `title`, `text`; operators: `AND`, `OR`, `NOT`; parentheses supported;
    quoted values with spaces supported).
  - `filter.eval(tree, note)` → `boolean` — evaluates a parsed tree against
    a note data table `{path, title, tags, body}`. Tag matching is exact
    (case-insensitive); title and text matching are plain substring.
  - `filter.from_legacy(tbl)` → `tree | nil` — converts the old `export.lua`
    filter table `{tags_any, tags_all, title, text}` into a tree for backward
    compatibility.
- `lua/pkm/bench.lua` — developer benchmarking utilities. Not user-facing,
  no commands registered. Fully self-contained: synthetic files are written
  to a temp directory and deleted after each run by default.
  - `bench.time(fn)` → elapsed ms (float) via `vim.uv.hrtime()`.
  - `bench.gen_notes(n, dest)` — write n synthetic consolidated notes with
    realistic frontmatter and body. Deterministic (seed 42).
  - `bench.cleanup(bench_dir)` → `vim.fn.delete(dir, 'rf')` — removes all
    synthetic files. Called automatically by `run_suite` unless `keep=true`.
  - `bench.baseline()` — Phase 1 raw scan on the real corpus. Read-only.
  - `bench.run_suite(bench_dir?, opts?)` — four-phase suite over 100/1k/10k
    synthetic notes (100k if `opts.extended=true`):
    - Phase 1 (raw scan): readfile + parse_frontmatter — pre-index baseline.
    - Phase 2 (index build): in-memory table construction — index.rebuild() cost.
    - Phase 3 (index query): table iteration — post-index get_all() cost.
    - Phase 4 (filter eval): filter.eval() on every entry — post-index query cost.
    Each tier warm-cycled once before timing. Cleans up on completion.
- `lua/pkm/index.lua` — in-memory note index with incremental invalidation.
  Eliminates the per-query readfile + parse_frontmatter scan (baseline: ~0.25
  ms/note; projected 27s at 100k notes). Index is built lazily on the first
  call to get_all() and kept current by a BufWritePost autocmd that
  re-reads only the saved file.
  - `index.setup(config)` → store config, register BufWritePost autocmd
  - `index.get_all()` → `entry[]` — builds on first call, O(n) table iter after
  - `index.get(path)` → `entry | nil`
  - `index.invalidate(path)` → re-read one file; remove entry if gone
  - `index.rebuild()` → full rescan on demand
  - `index.is_built()` → boolean
  - Entry shape: `{path, title, tags, body, mtime}`
- `pkm.init`: added `require('pkm.index').setup(M.config)` call in `setup()`.

### Changed
- `export.lua`: `match_file` now consults `pkm.index` for note data and
  delegates filter evaluation to `pkm.filter.eval()` via `filter.from_legacy()`.
  Returns false if the path is not in the index. Public API and filter
  semantics are unchanged.
- `export.lua`: `collect_files` now calls `index.get_all()` instead of
  globbing the filesystem per query. Filter evaluation via `filter.eval()`.
  Scope (consolidated, journal, scratchpad only) is preserved — the index
  excludes templates by construction.
- `init.lua`: `delete_note_safely()` calls `index.invalidate(filepath)` after
  successful deletion so the stale entry is removed immediately.
- `notes.lua`: `create_new_note()` and `create_scratchpad()` call
  `index.invalidate(filepath)` after `writefile` so newly created notes are
  immediately queryable.
- `notes.lua`: `apply_in_place()` (inside `convert_note()`) calls
  `index.invalidate(current_path)` after `writefile` — the write bypasses
  BufWritePost so the autocmd would not fire.
- `notes.lua`: unnamed-file branch of `convert_note()` calls
  `index.invalidate(new_path)` after write and `index.invalidate(current_path)`
  after optional delete.
- `notes.lua`: `import_note()` calls `index.invalidate(target_path)` after
  write and `index.invalidate(current_path)` if the original is deleted.
- `citations.lua`: `manage_backlink()` calls `index.invalidate(target_path)`
  after `save_frontmatter` when a backlink is added or removed.
- `citations.lua`: `migrate_legacy_links()` calls `index.invalidate(filepath)`
  after `writefile`.
- `citations.lua`: `update_references()` calls `index.invalidate(target_file)`
  after `save_frontmatter` when operating in disk mode (target_file provided).
  Buffer mode is excluded — BufWritePost handles that path.
- `citations.lua`: `update_references_on_rename()` calls
  `index.invalidate(file)` after each `writefile` in both the fm and non-fm
  branches.
- `citations.lua`: `merge_tags()` calls `index.invalidate(file)` after
  `save_frontmatter` for each modified file.
- `notes.lua`: `_finish_convert()` calls `index.invalidate(new_path)` after
  the new file is written and `index.invalidate(original_path)` if the user
  deletes the original. Covers all `do_convert` branches including transpose.
- `notes.lua`: `change_note_type()` calls `index.invalidate(current_path)`
  and `index.invalidate(new_path)` after rename and frontmatter write.
- `notes.lua`: `rename_from_yaml()` calls `index.invalidate(filepath)` and
  `index.invalidate(new_filepath)` after a successful rename.
- `notes.lua`: `promote_note()` — covered via `_finish_convert()`;
  no direct changes needed.

### Dead Code
- `normalise_tags` in `export.lua` — no longer called after `match_file`
  rewrite. Queued for removal.

### Known Bugs
- `bench.lua`: `utils.join` uses `\` separator on Windows/WSL, producing
  malformed paths when bench_dir is a Unix-style path (e.g. `/tmp/pkm_bench`).
  Files are still created correctly because vim.fn.mkdir/glob tolerate mixed
  separators on WSL. Fix: accept bench_dir as-is and join subdirs with the
  correct separator for the path type, or document that bench_dir must use
  the native separator.   

### Suspended Functions (queued for decision)

- **`journal.sync_yaml_on_rename`** — reads the journal filename, parses the
  timestamp from it, and writes `date` and `time` fields back into YAML.
  Called from the `BufReadPost` autocmd in `init.lua`.

  Was silently broken by the greedy pattern bug — the function exited without
  writing anything. When the pattern was fixed in 1.1.1, it began writing
  `date` and `time` to every journal note on open. These fields are not in
  the journal template and conflict with the `created_on`/`last_updated_on`
  design.

  **Current state:** the `BufReadPost` call in `init.lua` is commented out.
  The function definition in `journal.lua` is left intact.

  **Options:**
  - Delete — if `date`/`time` fields are never wanted.
  - Add to template and reinstate — if split date/time fields are wanted.
  - Replace with a function that syncs `created_on` from the filename instead.

  Note: `notes.sync_yaml_on_rename` (consolidated folder) is unrelated — it
  syncs `title` only and is not affected.

### Dead Code (queued for removal)

- `normalize_path(path)` in `notes.lua` — defined but never called.
- `is_empty_table(t)` in `yaml.lua` — defined but never called.
- `is_array_table(t)` in `yaml.lua` — defined but never called.
- `show_stats_window(stats)` in `ui.lua` — stats table never constructed;
  `show_stats()` is the live implementation.
- `select_note_enhanced` in `ui.lua` — defined but not called from any command.
- `M.template_picker` in `templates.lua` — empty stub, never called externally.

---

## [1.1.4] — 2026-05-11

### Added
- `change_note_type()` in `notes.lua` - changes the type of a note that is
already on the intended folder. Used especially for changing between "note",
"agg", and "bib" within "Consolidated Notes".

## [1.1.3] — 2026-05-11

### Added
- `transpose_note()` in `notes.lua` — moves the current note to a different
  PKM folder and converts it to that folder's format. Works from any folder,
  unlike `promote_note` which is scratchpad-only. Presents all folders except
  the current one as targets, then delegates to `do_convert()`.
- `:PKMTranspose` command in `commands.lua`.
- `transpose_note = "<leader>nT"` keymap in `config.lua` defaults and
  `keymaps.lua`.

### Fixed
- `do_convert` journal and scratchpad branches were missing
  `update_references_on_rename` calls. Wiki-links and frontmatter citations
  pointing to converted notes became stale. Now called after `writefile` in
  all three branches (journal, note, scratchpad).
- `do_convert` note branch was also missing `update_references_on_rename`.
  Added after `writefile` with `fm_data.title` as the title argument.
- `convert_note` unnamed-file branch had a duplicate and incorrect
  `update_references_on_rename` call using `fm_data.title` (undefined in
  scope) before `writefile`. Removed the duplicate; the correct single call
  with `title` after `writefile` is retained.
- `get_citable_items_for_picker` in `citations.lua` truncated scratch/journal
  identifiers to date-only via `id:match("%d%d%d%d%-%d%d%-%d%d")`. This
  caused citation metadata to never update for scratch/journal citations
  because the token didn't match the full identifier in `update_references`.
  Fixed by removing the date-only pattern; identifiers now fall through to
  the full `id`.
- **`short_id` truncation was breaking scratch citation metadata** — in
  `get_citable_items_for_picker`, the pattern `id:match("%d%d%d%d%-%d%d%-%d%d")`
  truncated scratch/journal identifiers to date-only (e.g. `"2026-05-09"`
  instead of `"2026-05-09_22-17-17"`). The lookup key in `update_references`
  used the full identifier, so the citation token never matches and metadata
  is not updated. Fixed by removing the date-only pattern and fall through to the
  full `id`.

### Documentation
- Module API headers, LuaDoc annotations, and section separators added to all
  modules: citations, yaml, notes, journal, ui, commands, keymaps, telescope,
  export, templates, timestamp, config, utils, init.

---

## [1.1.2] — 2026-05-10

### Fixed
- `export.lua`: `collect_files` now scans only consolidated, journal, and
  scratchpad folders. Previously iterated all `config.folders` including
  templates.
- `export.lua`: replaced local `path_sep`/`join_path` with `pkm.utils`.

---

## [1.1.1] — 2026-05-10

### Fixed
- `do_convert` used `"consolidated"` as template key; now resolves to `"note"`,
  `"agg"`, or `"bib"`.
- `import_note` had the same template key bug.
- Template key `"consolidated"` renamed to `"note"` throughout. `agg` template
  added to defaults.
- Cross-folder backlinks now work correctly (`get_note_type_and_id` fix
  confirmed working).
- `sync_yaml_on_rename` in `journal.lua` had greedy pattern bug; fixed with
  `filename:match("^journal_(.+)$")`.

---

## [1.1.0] — 2026-05-09

### Refactor: init.lua decomposition

**Added:**
- `lua/pkm/utils.lua` — shared cross-platform utilities.
- `lua/pkm/config.lua` — default config table and `resolve(user_config)`.
- `lua/pkm/commands.lua` — all `:PKM*` user command registration.
- `lua/pkm/keymaps.lua` — all keymap wiring.

**Changed:**
- `init.lua` is now pure orchestration.
- All modules now use `utils` for path operations.

**Added:**
- `:PKMStats` command implemented via `ui.show_stats()`.

### Fixed
- `commands.lua` handlers used `M.x()` for init.lua functions; now use
  `require('pkm').x()`.
- `keymaps.lua` used `M.config` instead of the `config` parameter.
- `setup()` closing `end` was missing.
- `setup_sync_autocmds()` was called twice.
- `commands.lua` and `keymaps.lua` missing `return M`.
- `get_note_type_and_id` greedy pattern fixed with explicit prefix matching.
- `validate_frontmatter` now reads note type from filename instead of folder.

---

## [1.0.1] — 2026-05 (approximate)

### Added
- `export.lua` — filter and copy notes by tag/title/body text.
- Tag merging: `citations.merge_tags()` and Telescope picker.

### Removed
- `status` field from frontmatter. Do not reintroduce.

### Fixed
- Trailing space on YAML `---` delimiter aborted frontmatter parsing.

---

## [1.0.0] — Initial release

- Single wiki system with Scratchpad, Journal, Consolidated folder types
- Note creation with automatic numbering
- YAML frontmatter management
- Bidirectional citation system
- Flexible timestamp system
- Cross-platform path handling
- Telescope integration
- Filename-YAML synchronization
- Citation cleanup for deleted notes
