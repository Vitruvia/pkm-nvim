# PKM.nvim — Changelog

---

## [Unreleased]

### In Progress
- Module API header blocks (one per file)
- LuaDoc annotations on exported functions
- Section separators inside large files (citations.lua, notes.lua)

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
