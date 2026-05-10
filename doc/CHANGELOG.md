# PKM.nvim — Changelog

---

## [Unreleased]

### In Progress
- Module API header blocks (one per file) — citations.lua, yaml.lua, notes.lua done
- LuaDoc annotations on exported functions — citations.lua, yaml.lua, notes.lua done
- Section separators inside large files — citations.lua, yaml.lua, notes.lua done

### Known Bugs (queued for after refactor)
- **Rename from inside note requires manual `e!`** — when a note's title is
  changed in frontmatter and saved, `sync_filename_on_save` renames the file
  on disk but the buffer remains associated with the old path. The user must
  run `:e!` to reload. Root cause: buffer is not redirected to the new path
  after the filesystem rename. Fix requires: (1) write content to new path,
  (2) delete old file, (3) redirect buffer via `keepalt file` + `edit`.
  A secondary E484 error from `migrate_legacy_links` attempting to read the
  old (now deleted) path is fixed by adding a `filereadable` guard at the top
  of `update_references`. That guard can be applied independently at any time.

### Dead Code (queued for removal after refactor)
- `normalize_path(path)` in `notes.lua` — defined but never called. Safe to
  delete; path normalization is handled inline where needed.
- `is_empty_table(t)` in `yaml.lua` — defined in Generation helpers section
  but never called; `generate_yaml` uses inline `next(value) == nil` instead.
- `is_array_table(t)` in `yaml.lua` — same as above; defined but unused.

---

## [1.1.1] — 2026-05-10

### Fixed
- `do_convert` in `notes.lua` was passing `"consolidated"` as the template
  key when promoting a scratchpad to a consolidated note. Now correctly
  passes `"note"`, `"agg"`, or `"bib"` depending on user selection.
- `import_note` in `notes.lua` had the same template key bug — used
  `"consolidated"` as fallback instead of resolving from `selected_type`.
  Now correctly passes `"note"` or `"agg"` alongside `"bibliography"`.
- Template key `"consolidated"` renamed to `"note"` throughout `config.lua`,
  `notes.lua`, and `convert_note()`. Author injection in `config.resolve()`
  updated accordingly. `agg` template added to defaults.
- `get_note_type_and_id` pattern fix from 1.1.0 confirmed working: journal
  and scratch notes now correctly return their type and identifier, enabling
  cross-folder backlink sync.

---

## [1.1.0] — 2026-05-09

### Refactor: init.lua decomposition

`init.lua` was carrying too many responsibilities. Extracted into dedicated modules.

**Added:**
- `lua/pkm/utils.lua` — shared cross-platform utilities: `join()`, `sep`,
  `normalize()`, `ensure_dir()`, `is_windows`, `is_wsl`. Eliminates copy-pasted
  path logic that existed independently in notes.lua, journal.lua, ui.lua,
  citations.lua, and templates.lua.
- `lua/pkm/config.lua` — default config table and `resolve(user_config)`.
  Pure data, no side effects.
- `lua/pkm/commands.lua` — all `:PKM*` user command registration. Handlers
  lazy-require their target modules. References to init.lua functions use
  `require('pkm')`.
- `lua/pkm/keymaps.lua` — all keymap wiring. Receives resolved config as
  parameter to `register(config)`.

**Changed:**
- `init.lua` is now pure orchestration: calls module setup, then
  `commands.register()`, `keymaps.register(config)`, `setup_sync_autocmds()`.
- `setup_keymaps()` and `setup_sync_autocmds()` are now module-level functions
  on init.lua's M, not inline inside setup().
- All modules that previously declared local `path_sep`, `join_path`,
  `ensure_dir` now use `utils` instead: notes.lua, journal.lua, ui.lua,
  citations.lua, templates.lua.

**Added:**
- `:PKMStats` command — was listed in README but never implemented.
  Now calls `ui.show_stats()`.

### Fixed
- `commands.lua` handlers that called init.lua functions via `M.x()` now
  correctly use `require('pkm').x()`. Affected: `PKMDeleteNote`,
  `PKMToggleAutoSync`.
- `keymaps.lua` incorrectly referenced `M.config` (its own empty table)
  instead of the `config` parameter passed to `register(config)`.
- `setup()` closing `end` was missing, causing all module-level functions
  to be silently defined inside `setup()`.
- `setup_sync_autocmds()` was being called twice inside `setup()`.
- Both `commands.lua` and `keymaps.lua` were missing `return M`, causing
  `require()` to return `true` instead of the module table.
- `get_note_type_and_id` used a greedy pattern that split on the last
  underscore, causing journal/scratch filenames with multiple underscores
  to return nil. Fixed with explicit prefix matching.
- `validate_frontmatter` used folder-name-to-template lookup which could not
  distinguish note/bib/agg within the consolidated folder. Now reads type
  from filename.

---

## [1.0.1] — 2026-05 (approximate)

### Added
- `export.lua` — interactive filter form and Telescope picker for exporting
  notes. Supports filtering by tag, title, body text. Exact-match only.
- Tag merging: `citations.merge_tags(sources, target)` and Telescope picker
  `telescope.merge_tags_picker()`.

### Removed
- `status` field from frontmatter. Do not reintroduce.

### Fixed
- Trailing space on YAML `---` delimiter was silently aborting frontmatter
  parsing. Fixed by cleaning affected note files (not by adding parser
  tolerance).

---

## [1.0.0] — Initial release

- Single wiki system with Scratchpad, Journal, Consolidated folder types
- Note creation with automatic numbering
- YAML frontmatter management
- Bidirectional citation system
- Flexible timestamp system
- Cross-platform path handling
- Telescope integration: search, tags, citations
- Filename-YAML synchronization
- Citation cleanup for deleted notes
