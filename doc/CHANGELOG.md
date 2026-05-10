# PKM.nvim — Changelog

---

## [Unreleased]

### In Progress
- Module API header blocks — citations.lua, yaml.lua, notes.lua, journal.lua,
  ui.lua, commands.lua, keymaps.lua, telescope.lua, export.lua, templates.lua,
  timestamp.lua, config.lua, utils.lua done
- LuaDoc annotations — same files done
- Section separators — same files done
- Remaining: init.lua only

### Known Bugs (queued for after refactor)

- **Rename from inside note requires manual `e!`** — when a note's title is
  changed in frontmatter and saved, `sync_filename_on_save` renames the file
  on disk but the buffer remains associated with the old path. The user must
  run `:e!` to reload. Fix requires: (1) write content to new path, (2) delete
  old file, (3) redirect buffer via `keepalt file` + `edit`. A secondary E484
  error from `migrate_legacy_links` attempting to read the old (now deleted)
  path is separately fixed by adding a `filereadable` guard at the top of
  `update_references`.

- **Greedy timestamp pattern in `journal.lua` querying functions** —
  `find_by_date_range`, `list_recent`, and `find_by_tag` all use the greedy
  pattern `filename:match("^(.+)_(.+)$")` which returns only the last
  component of a multi-part timestamp. Fix: replace with
  `filename:match("^journal_(.+)$")` in all three functions.

- **`PKMSearch` and `PKMTags` have no Telescope fallback** — both commands
  call `require('pkm.telescope')` directly. If Telescope is unavailable they
  error instead of falling back to `ui.search_notes()` and `ui.browse_tags()`.
  `PKMMergeTags` correctly uses a `pcall` check and should be the model.

- **`quick_capture` keymap calls wrong command** — `keymaps.lua` maps
  `k.quick_capture` to `<cmd>PKMNewNote<cr>` instead of a dedicated
  `PKMQuickCapture` command. `notes.quick_capture()` exists but is unreachable
  via keymap. Fix: add `PKMQuickCapture` command in `commands.lua` and update
  the keymap.

- **`telescope.lua` checks Telescope at load time** — top-level
  `pcall(require, 'telescope')` returns an empty M if Telescope hasn't loaded
  yet. Under Lazy.nvim deferred loading this can silently make all pickers
  unavailable. All other modules check availability at call time; this module
  should be refactored to match.

- **`export.lua` `collect_files` scans the templates folder** — iterates
  `config.folders` with `pairs`, which includes `templates`. Template files
  will appear in export results if they match filters. Fix: scan only
  consolidated, journal, and scratchpad explicitly instead of all folders.

- **`templates.lua` `apply_template` silently fails when Telescope is loaded**
  — calls `tele.template_picker(templates, on_select)` which is an empty stub.
  When Telescope is available, nothing happens. Fix: either implement the
  picker in `telescope.lua` or fall through to `vim.ui.select` unconditionally
  until it is implemented.

### Dead Code (queued for removal after refactor)

- `normalize_path(path)` in `notes.lua` — defined but never called.
- `is_empty_table(t)` in `yaml.lua` — defined but never called.
- `is_array_table(t)` in `yaml.lua` — defined but never called.
- `show_stats_window(stats)` in `ui.lua` — the `stats` table it expects is
  never constructed. `show_stats()` is the live implementation.
- `select_note_enhanced` in `ui.lua` — defined but not called from any command.
- `M.template_picker` in `templates.lua` — empty stub, never called externally.

### Pending Cleanup

- `export.lua` used its own local `path_sep` and `join_path` instead of
  `pkm.utils`. Fixed in this session (replaced with `utils.join` and
  `utils.sep`).

---

## [1.1.1] — 2026-05-10

### Fixed
- `do_convert` in `notes.lua` used `"consolidated"` as template key.
  Now correctly resolves to `"note"`, `"agg"`, or `"bib"`.
- `import_note` in `notes.lua` had the same template key bug.
- Template key `"consolidated"` renamed to `"note"` throughout. `agg` template
  added to defaults.
- `get_note_type_and_id` pattern fix confirmed working: cross-folder backlinks
  now work correctly.
- `sync_yaml_on_rename` in `journal.lua` had the greedy pattern bug. Fixed
  with `filename:match("^journal_(.+)$")`.

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
