# PKM.nvim — Changelog

---

## [Unreleased]

### Known Bugs (queued)

- `bench.lua`: `utils.join` uses `\` separator on Windows/WSL, producing
  malformed paths when `bench_dir` is a Unix-style path (e.g. `/tmp/pkm_bench`).
  Files are still created correctly because `vim.fn.mkdir`/`glob` tolerate
  mixed separators on WSL. Fix: accept `bench_dir` as-is and join subdirs with
  the correct separator for the path type, or document that `bench_dir` must use
  the native separator.

- `:PKMOrphans` is O(V × N) at call time (calls `views.match_all()` once per
  defined view to build the viewed-path set). `bench.views_suite` was run at
  10k notes: overview costs V × 3.1ms (50 views → 158ms, 300 views → 935ms).
  At current real corpus scale (hundreds of notes, tens of views) the cost is
  negligible. `_match_cache` is deferred: revisit if corpus reaches ~5k notes
  or view count exceeds ~200 with observed latency.

### Benchmarks 

#### Post-index integration (bench_dir on NTFS/WSL, P: drive)

  - 10k notes: raw 1966ms, build 1510ms, query 0.20ms, filter 6.6ms
  - Post-index query + filter: ~6.8ms vs ~1966ms raw (~290× improvement)
  - 100k projection (raw scan): ~14.2s; post-index: ~65ms
  - Previous run used Linux tmpfs (raw ~1449ms at 10k); difference is
    filesystem speed, not a regression.

### Views_suite (NTFS/WSL, P: drive, synthetic notes)

  - Scaling is perfectly linear: ms/view is constant across all view counts.
  - 10k notes: single 3.5ms,  50 views → 158ms,  300 views → 935ms,  1000 views
    → 3087ms  (~3.1ms/view)
  - 1k notes (post-JIT):      50 views →   7ms,  300 views →  40ms,  1000 views
    →  130ms  (~0.13ms/view)
  - JIT accounts for ~2–3× speedup between cold and warm runs at same note
    count.
  - Caching decision: not warranted at current scale. Revisit at ~5k notes or
    ~200+ views.

---

## [1.5.3] - 2026-6-17

### Fixed

- **TS highlighter extmark out-of-range errors** — all four variants (end_row
  on `dd`/`d{motion}`, end_col on bracket deletion, probabilistic on `J`, and
  end_col on line deletion above a header) share the same root cause:
  `parser:parse()` was deferred via `vim.schedule`, leaving stale extmarks
  visible during the synchronous redraw that follows any buffer change.
  Fix: removed `vim.schedule`; the parse now runs synchronously in the
  `TextChanged`/`TextChangedI` callback. `parser:parse()` is incremental and
  cannot trigger further change events.

- **Sidebar/view panel not refreshed after metadata save** — `:PKMAddTag`,
  `:PKMRemoveTag`, `:PKMSetTitle` are buffer-only; after `:w`, the index was
  updated but `refresh_sidebar_if_open()` was never called. Notes remained
  visible in views despite tag removal. Fix: `refresh_sidebar_if_open()`
  added at the end of the PKMSync `BufWritePost` `vim.schedule` block.

- **Sidebar opening squeezes leftmost editing window** — `topleft vsplit`
  took space from the leftmost editing window; when two or more vertical splits
  were present, setting the sidebar to its configured width left the remaining
  windows narrower than expected. Fix: `vim.cmd('wincmd =')` called after
  `winfixwidth` is set on the sidebar, redistributing remaining space equally
  among unfixed editing windows.

- **Sidebar `<CR>` could target bufpanel or netrw** — the fallback window
  scan in the `<CR>` handler did not filter panel filetypes, so in edge cases
  the buffer panel or netrw could be selected as the open target. Added
  `_PANELS` filter to both the alternate-window check and the scan loop.

### Added

- **Filename / title display toggle** — `config.display_mode` (`'filename'`
  default | `'title'`). All note labels in the sidebar, buffer panel, and
  sidebar winbar respect this setting. Runtime toggle: `T` inside either
  panel switches both simultaneously. New public functions in `ui.lua`:
  `get_display_mode()`, `toggle_display_mode()`, `refresh_bufpanel()`.
  Falls back to filename stem if title is empty.

- **`[N]<CR>` window selection in sidebar** — pressing `N<CR>` (where N is
  a count, e.g. `2<CR>`) opens the note in the Nth main editing window,
  sorted left to right by column position. Warns if N exceeds the number of
  available windows. Plain `<CR>` without a count retains existing behavior
  (alternate window, then first non-panel window, then new split).

### Changed

- **Sidebar and buffer panel: stripped display prefixes** — filename labels
  no longer show the leading `NNNN_type_` portion of consolidated note stems
  (`0042_note_Introduction` → `Introduction`) or the `journal_`/`scratch_`
  prefix of timestamped notes. The note type is already communicated by the
  `[n]`/`[a]`/etc. bracket prefix; the number is a system identifier that
  provides no display value. Line-counter indices (`1`, `2`, …) removed from
  both sidebar and buffer panel entry lines. Title mode unaffected (frontmatter
  titles are free-form and have no prefix to strip).

- **Sidebar and buffer panel: sorted by mtime** — note lists now sort by
  `entry.mtime` (most recently modified first) instead of by type then title.
  The type prefix `[n]`/`[a]`/etc. still communicates note type visually.
  Buffer panel non-PKM files fall back to `vim.fn.getftime()` for sorting.

- **Sidebar focus retained on open** — `:PKMViewSidebar` / `<leader>vs` no
  longer returns focus to the editing window after opening. The sidebar retains
  focus so the user can immediately navigate, open a note, or use a
  sidebar-specific keymap. Switching to the editing window is `<C-w>l` or any
  standard Vim window navigation.

- **LLM rule added** — note numbers (`NNNN`) are PKM system identifiers and
  must not appear in any user-facing UI display. Strip `NNNN_type_` from all
  sidebar, panel, and picker labels. Recorded in `LLM_CONTEXT.md`.


---

## [1.5.2] - 2026-6-15

### Fixed

- **TS `end_row out of range` on line deletion** — deleting lines with `dd`
  or `d{motion}` left tree-sitter extmarks referencing rows that no longer
  existed, causing repeated highlighter errors. Root cause: only programmatic
  writes (via `renumber_sequence`) restarted TS; normal editing did not.
  Fix: `TextChanged` + `TextChangedI` autocmds in `syntax.M.enable` now
  schedule `parser:parse()` after every buffer change, forcing an incremental
  re-parse before the decoration provider next runs.

- **Frontmatter fold closes after save** — `vim.treesitter.start` called in
  `BufWritePost` re-evaluated all fold expressions, resetting `foldlevel` to 0
  and closing user-opened folds. `winsaveview`/`winrestview` do not preserve
  fold open/closed state. Fix: `BufWritePost` now saves `foldclosed(1)` for
  every non-float window showing the written buffer before the TS restart, then
  in a `vim.schedule` callback reopens folds (`zR`) in any window where they
  were open before the save. Per-window, so two splits with different fold
  states are handled independently.

- **Buffer panel window markers stale after buffer switch** — the `w1`/`w2`
  indicators only updated when a buffer was added or deleted (`BufAdd`,
  `BufDelete`). Switching a window to an already-open buffer (via panel `<CR>`
  or sidebar navigation) fires neither event, so the markers did not move.
  Added `BufEnter` to the refresh autocmd list; the panel now re-evaluates
  the window-to-buffer mapping on every buffer switch.

### Added

- **Buffer panel `colorcolumn` cleared** — the 80-column highlight (set
  globally in user config) was visible in the buffer panel window.
  `vim.api.nvim_set_option_value('colorcolumn', '', { win = t.win })` added
  after the window-options loop in `toggle_bufpanel`.

- **Buffer panel window indicators** — each buffer entry now shows which main
  editing window(s) currently display it: `w1`, `w2`, etc. Windows are
  numbered in tabpage order, excluding panels (sidebar, bufpanel, netrw) and
  floats. A buffer open in two splits shows `w1,w2` adjacent to its title.

- **PKMCitation bold highlight** — `setup_hl_groups` now reads Special's
  foreground at definition time and defines `PKMCitation` as
  `{ fg = sp.fg, bold = true }` rather than a plain link to Special. This
  makes citations visually distinct even when nested inside outer bracket
  structures (e.g. `[CF/88 (bib[0035]) Art. 165]`). Falls back to
  `{ link = 'Special' }` if Special has no explicit fg. Refreshed on
  `ColorScheme` via the existing autocmd.

- **Foldtext simplified** — `M.foldtext()` now returns
  `▸ frontmatter (N lines)` without key hints. Fold commands documented in
  `pkm.txt` section 7 instead.

---

## [1.5.1] - 2026-6-15

### Fixed

- **`close_sidebar` E444 when sidebar is last window** — `nvim_win_close` raised
  E444 when `q` or `<Esc>` was pressed in the sidebar with no other non-float
  window open. `close_sidebar()` now counts non-float windows; if the sidebar is
  the only one, it calls `vim.cmd('quit')` (respects tabpage and Neovim quit
  logic) instead of `nvim_win_close`.

- **Unnamed `[No Name]` buffer left in buffer list** — `_detach_buf_from_wins`
  in `init.lua` and `ensure_main_window` in `ui.lua` both call `noautocmd enew`/
  `noautocmd aboveleft new` as a last resort to keep a window open. These created
  persistent `[No Name]` buffers that appeared in `:ls` and blocked `:wa`. Fix:
  `vim.bo.bufhidden = 'wipe'` immediately after each creation call, so the buffer
  self-destructs when the window next displays any other buffer.

### Added

- **netrw winbar** — when the PKM file explorer (netrw) opens via
  `toggle_file_explorer`, a `FileType netrw` autocmd (registered via
  `PKMNetrwFixes` augroup in `keymaps.lua`) sets the window's `winbar` to the
  current directory (home-relative via `fnamemodify(:~)`). Updates on `BufEnter`
  to track subdirectory navigation.

- **netrw window navigation keymaps** — the same `FileType netrw` autocmd adds
  buffer-local `<C-h/j/k/l>` → `<C-w>h/j/k/l` keymaps, overriding netrw's
  `<C-l>` refresh binding. Restores standard Vim window navigation while in the
  file explorer. Scoped to the netrw buffer; global keymaps are unaffected.

- **netrw excluded from buffer panel** — `bufpanel_build_lines` now skips buffers
  with `filetype = 'netrw'`. The file explorer no longer appears as `[f]` in the
  `:PKMBuffers` panel.

- **Sidebar winbar shows view name** — when in detail mode with the cursor on a
  header, tree, or separator line (i.e. when the buffer's own header has scrolled
  off screen), the winbar now shows `≡ viewname` (plus `[type]` if a type filter
  is active). On a note line, the existing filename display is preserved. The view
  name remains visible regardless of scroll position.

---

## [1.5.0] - 2026-6-15

### Decisions
- **Trash isolation over OS integration** — PKM trash is a self-contained
  `.pkm-trash/` folder inside the root rather than the OS recycling bin.
  Rationale: no portable Lua/Neovim API exists for Windows RecycleBin, macOS
  .Trash, and Linux `gio trash` simultaneously; the manifest stores PKM-specific
  metadata (original path, title, deletion timestamp) needed for clean
  restoration and autoclear; the trash folder moves with the PKM root and
  remains version-controllable.

- **Note numbering skips trashed numbers** — `get_next_note_number()` checks
  both the consolidated folder and the trash manifest. If note 0042 is in
  trash, the next new note is 0043. Gaps in numbering are intentional and
  cause no problems; numbers are permanent identifiers, not sequential labels.

- **Phase 4 syntax mechanism: tree-sitter queries** — PKM-specific syntax,
  conceal, and frontmatter folding/injection will be implemented as bundled
  tree-sitter queries (`queries/markdown/highlights.scm`,
  `queries/markdown/injections.scm`) loaded by Neovim's built-in query
  resolver. No `nvim-treesitter` plugin dependency: the `markdown`,
  `markdown_inline`, and `yaml` parsers are bundled in Neovim 0.10+.
  Activation: `vim.treesitter.start(bufnr, 'markdown')` per PKM buffer when
  `:PKMMode` is active. Deactivation: `vim.treesitter.stop(bufnr)` + `syntax
  on` restores Vimscript highlighting including `after/syntax/markdown.vim`.
  The existing Vimscript file is retained as the non-PKMMode fallback; it will
  be deleted when its two rules are superseded by tree-sitter captures in the
  Phase 4 highlights.scm. This decision gates all frontmatter folding, conceal,
  injection, and context-aware highlighting work.

### Added
- **Creation commands respect window context** — `:PKMNewNote`, `:PKMNewJournal`,
  `:PKMNewScratchpad`, `:PKMImport` now call `focus_main_win()` before opening
  any buffer. When the current window is the PKM sidebar (`pkm-sidebar`),
  buffer panel (`pkm-bufpanel`), or netrw file explorer, focus switches to the
  nearest non-panel non-float window, or a new split is created if none exists.
  Pressing `<leader>nn` (or any creation keymap) from the sidebar, buffer panel,
  or netrw now opens the new note in the main editing area.

- **`config.keymaps.toggle_file_explorer`** (default `"<leader>nE"`) — cycles
  between the PKM views sidebar and a netrw file explorer (`:topleft vsplit`
  over `root_path`). PKM sidebar open → close sidebar, open netrw at the same
  width; netrw open → close netrw, open PKM sidebar; neither → open PKM sidebar.

- **Trash autoclear** — `config.trash.max_age_days` (default 60; 0 = disabled).
  `trash.M.purge_old()` is called via `vim.defer_fn` (5 s after startup),
  permanently deletes manifest entries older than the threshold, and strips
  their backlinks. Manifest entries now include `deleted_timestamp` (Unix
  epoch) for accurate comparison; legacy entries without this field fall back
  to parsing `deleted_at` date string.

- **Phase 5: Trash system** — `:PKMDeleteNote` with `trash.enabled = true`
  (default) now moves notes to `{root}/.pkm-trash/` instead of permanently
  deleting them. Backlinks in other notes are NOT stripped on trash — they are
  preserved so restoration is fully reversible. New commands:
  - `:PKMRestoreNote` — picker over trash manifest; moves note back to its
    original path, re-indexes, no citation reconstruction needed (backlinks
    intact).
  - `:PKMEmptyTrash` — permanently deletes all trashed notes and strips their
    backlinks from other notes via `citations.cleanup_deleted_note`. Requires
    `yes` confirmation.
  New module `lua/pkm/trash.lua`. Config: `trash = { enabled = true }`.
  Set `enabled = false` to revert to permanent delete (old behaviour).

- **`type:` filter predicate** — `filter.lua` gains a `type` field.
  `type:note`, `type:agg`, `type:bib`, `type:journal`, `type:scratch`,
  `type:other` match `entry.note_type` exactly (case-insensitive). Works in
  `:PKMBrowse`, view filter expressions, `:PKMOrphans`, and any other
  filter-DSL consumer. Tab completion for `:PKMBrowse` suggests `type:` and
  its six values.

- **Sidebar `<C-t>` type filter** — in detail mode, `<C-t>` cycles through
  `all → note → agg → bib → journal → scratch → all`. The note list is
  re-filtered on each cycle; the count header shows `N of M` when a filter
  is active. The filter resets to `all` when navigating to overview. The
  `type_filter` field is added to per-tabpage sidebar state.

- **`:PKMConvertList [to_ordered|to_unordered]`** — converts ordered ↔
  unordered list items in range or paragraph at cursor. Direction is
  auto-detected (all ordered → to_unordered; all unordered → to_ordered;
  mixed → prompts). If multiple indent depths are present, prompts for max
  conversion depth. Items already in the target format are preserved (ordered
  items are renumbered to maintain sequence). Delegates to new
  `markdown.M.convert_list(start, end, direction?)` and
  `markdown.M.convert_list_at_cursor(direction?)`. Config:
  `keymaps.convert_list` (default `false`). Visual mode uses selection;
  normal mode uses paragraph bounds.

### Fixed
- **`:PKMDeleteNote` leaves dead space when last buffer is closed** — `bdelete!`
  was called while the note buffer was still shown in its window. If the buffer
  panel was open, the layout collapsed or repositioned. Root cause identical to
  the buffer-panel `d`/`D`/`w` fix. Added `_detach_buf_from_wins(bufnr)` local
  helper in `init.lua`; called before every `bdelete!` in `delete_note_safely`.
  Uses the same alternate-buffer → listed-buffer → `enew` priority as `ui.lua`.

- **`filter.lua` `type:` predicate never matched** — `elseif field == 'type'`
  used an undefined variable (`field`; should be `tree.field`). Predicate
  silently evaluated false for all notes.

- **`sidebar_show_help` width 38 instead of 44** — duplicate `local width`
  declaration; second shadowed first, clipping the `<C-t>` line. Fixed to 44.

- **`refresh_sidebar_if_open` nil error when window destroyed externally** —
  extra `end` placed the three buffer-write API calls outside the valid-window
  `else` block; with `lines` out of scope (nil), `nvim_buf_set_lines` errored.
  Removed the extra `end`; write operations are now correctly inside `else`.

- **Note numbers reused after deletion** — `get_next_note_number()` only
  scanned the consolidated folder; if the highest-numbered note was trashed,
  the number would be reused by the next new note, conflicting with a later
  restore. Now also checks the trash manifest.

- **Sidebar `<C-s>` splits the sidebar window** — global split keymaps
  (e.g. user-bound `<C-s>`) activated when focus was in the sidebar, splitting
  it instead of the intended main editing window. Added a buffer-local no-op
  for `<C-s>` in the sidebar buffer; buffer-local keymaps take precedence over
  globals, so the split command is suppressed while the sidebar has focus.

- **`renumber_sequence`: `list_bold_line` family** — detects `**N. body**`
  (double asterisks wrapping the whole ordered list item) as a distinct family.
  Detection comes before `list_emph` in the detection order. Renumbering
  preserves the surrounding `**...**` markers. Example: `**1. a**`, `**3. b**`
  → `**1. a**`, `**2. b**`.

- **Phase 4 syntax implementation** — `lua/pkm/syntax.lua` stubs replaced
  with full implementation. `M.enable(bufnr)` and `M.disable(bufnr)` now:
  - Start/stop `vim.treesitter` for the `markdown` parser
  - Load custom captures from `queries/markdown/highlights.scm` (bundled in
    plugin, loaded automatically via runtimepath) and
    `queries/markdown/injections.scm`
  - Register per-window `matchadd` highlights: `PKMCitation` for
    `type[identifier]` patterns; `PKMMetaComment` for `((text))` double-paren
    meta-comments (§9 convention); `Conceal` on `[[`/`]]` wiki-link brackets
  - Apply per-window options: `foldmethod=expr` with `M.foldexpr()` for
    frontmatter folding; `conceallevel=2` + `concealcursor=''` for wiki-link
    conceal
  - `M.foldexpr(lnum)` — fold expression called by Neovim; returns `'>1'` on
    the opening `---`, `'1'` for frontmatter body, `'0'` elsewhere; caches
    frontmatter end line in `vim.b._pkm_fm_end`, invalidated on BufWritePost
  - Highlight groups: `@pkm.indented.markdown → Normal` (suppresses indented
    code colour); `PKMCitation → Special`; `PKMMetaComment → Comment`
  - Re-applies groups on `ColorScheme`; cleans up per-window matches on
    `WinClosed`; idempotent enable/disable with `_active_bufs` tracking

- `queries/markdown/highlights.scm` (new) — extends built-in markdown queries:
  suppresses `indented_code_block` highlight via `@pkm.indented` capture (Phase
  4 fix: 4-space text no longer rendered as code); captures all list marker node
  types explicitly to ensure visibility at 4th-level and deeper nesting.

- `queries/markdown/injections.scm` (new) — extends built-in injections: injects
  the `yaml` parser into `minus_metadata` nodes (the `---`…`---` frontmatter
  block). Requires the `yaml` tree-sitter parser to be installed separately
  (not bundled with Neovim); silently ignored if unavailable.

- §9 conventions implementation — `((text))` double-paren meta-comment pattern
  highlighted as `PKMMetaComment` (links to `Comment`). Citation pattern
  `type[identifier]` highlighted as `PKMCitation` (links to `Special`). Both
  applied via `matchadd` in `syntax.lua`; no tree-sitter changes needed for
  these inline patterns.
- **`:PKMMode [on|off]`** — session-level PKM context toggle. Activates the
  explorer UI (views sidebar + buffer panel), pre-builds the index if not yet
  built (`index.prebuild = true`), and enables PKM-specific syntax highlighting
  on all open PKM buffers. Deactivation closes both panels and reverts syntax.
  Both directions are idempotent: re-activating when already active re-opens
  any manually closed panels without error; deactivating when already inactive
  is a no-op. Manual panel closure does not change mode state.
  Optional argument: `on` / `off`; bare `:PKMMode` toggles.
  New module `lua/pkm/mode.lua`; called from `pkm.init.setup()`.

- **`:PKMExplorer`** — toggle sidebar + buffer panel as a unit, independent of
  `:PKMMode` state. If both panels are open, closes both. If either is closed,
  opens the closed one(s). Does not affect index or syntax state.

- **`config.pkm_mode`** — new nested config block with four sub-tables:
  `triggers` (`open_note = true`, `enter_dir = false`),
  `layout` (`sidebar = true`, `bufpanel = true`),
  `index` (`prebuild = true`),
  `syntax` (`enabled = true`).
  Trigger `open_note`: activates mode on `BufReadPost` for any file under
  `root_path`. If mode is already active, only enables syntax on the new buffer.
  Trigger `enter_dir`: activates on `DirChanged` + startup check when Neovim
  opens inside `root_path`. Default off.

- **`config.keymaps.focus_sidebar`** (default `false`) — jump directly to the
  sidebar window via `nvim_set_current_win`; notifies if sidebar is not open.
  Works regardless of split count.

- **`config.keymaps.toggle_mode`** (default `false`) — keymap for `:PKMMode`.

- **`lua/pkm/syntax.lua`** — new stub module. `M.enable(bufnr)` and
  `M.disable(bufnr)` are no-ops until Phase 4 writes the tree-sitter query
  files. Signatures are fixed; bodies filled in Phase 4.

- **`views.is_sidebar_open()`** — returns true if sidebar is open in the
  current tabpage. **`views.get_sidebar_win()`** — returns the sidebar window
  handle or nil. Both added to support `mode.lua` and `focus_sidebar`.

- **`ui.is_bufpanel_open()`** — returns true if buffer panel is open in the
  current tabpage. Added to support `mode.lua`.
- `bench.views_suite(opts?)` — view-scaling benchmark for the overview
  scenario. Generates `note_count` (default 10 000) synthetic notes and
  builds an in-memory entry table, then at view counts 50 / 100 / 300 / 1 000
  times: (a) a single `filter.eval` pass over all notes (sidebar detail-mode
  cost) and (b) V sequential passes, one per synthetic view, counting matches
  only (mirrors `sidebar_build_overview` and `:PKMOrphans` — both O(V × N)).
  Uses synthetic state only; live PKM index, views.json, and real notes are
  not modified. Required measurement gate before any `_match_cache`
  optimisation of the O(V × N) path; do not add caching without running this
  first and recording the numbers in CHANGELOG.
  Usage: `:lua require('pkm.bench').views_suite()`.
  Options: `note_count` (integer, default 10000), `bench_dir` (string, default
  temp), `keep` (boolean, default false).

- `filter.lua`: `any` predicate — bare word, standalone quoted string, or
  unrecognised-field token. `eval` for `any`: case-insensitive plain substring
  over title ∪ body ∪ filename ∪ tag values. Tag values are substring for
  `any:` (unlike `tag:` which remains exact). Grammar: `predicate = (field
  ":") ? value`; `field` gains `any`; tokenizer now disambiguates (unknown
  field → any, bare word → any). `parse_atom` field validation removed; the
  tokenizer guarantees only KNOWN_FIELDS reach the parser.

- `:PKMBrowseRecent [n]` — show the n most recently modified notes (default 20),
  sorted by `mtime` descending. Opens in the live filter picker (Telescope) or
  `vim.ui.select` (fallback); `n` can be overridden per invocation.
  `telescope.browse_recent` and `ui.browse_recent` added. `live_picker` gains
  a `presorted` parameter (4th arg, boolean) that skips the internal type/title
  sort; callers that pre-sort by another criterion (mtime) pass `true`.

- `:PKMOrphans` — list notes that have no tags, no citations (in any
  `cites`/`cited_by` group), and do not match any defined view. Useful for
  locating abandoned or unfiled notes. `index.lua` entry shape extended with
  `has_citations` (boolean) computed at build time from frontmatter — no
  per-query file reads needed.

- `:PKMSetTitle` — prompt for a new title and write it to the current buffer's
  `title` frontmatter field. Buffer-only; never writes disk. `notes.lua` gets
  `M.set_title()`.

- `:PKMAddTag [tag]` — append a tag to the current buffer's frontmatter `tags`
  list; prompts if no argument; skips silently if already present. Buffer-only.

- `:PKMRemoveTag [tag]` — remove a tag from the current buffer's frontmatter
  `tags` list; presents a picker if no argument. Buffer-only.

  All three metadata commands use `yaml.save_frontmatter(fm, content_start)`
  (Case A: buffer-only write). None calls `index.invalidate`; the index
  re-reads from disk on the user's next `:w` via `BufWritePost`. `citations.lua`
  gets `M.add_tag()` and `M.remove_tag()`.

  Config defaults: `set_title = false`, `add_tag = false`, `remove_tag = false`.

- Filter autocomplete for `:PKMBrowse` — a `complete` function on the command
  suggests field prefixes (`tag:`, `title:`, `text:`, `filename:`, `any:`),
  boolean operators (`AND`, `OR`, `NOT`), and `tag:<value>` candidates from the
  index (when already built). Implemented as a module-level local
  `browse_complete` in `commands.lua`.

- §9 Conventions SPEC added to `doc/CONVENTIONS.md` (documentation only;
  implementation in Phase 4).

- **Sidebar filename infobar** — … Implemented as a buffer-local `CursorMoved`
  autocmd using the `winbar` window option (not `statusline`) so it coexists
  with lualine and other plugins that refresh the statusline on their own
  events. The winbar is hidden (`''`) when the cursor is on a header line or in
  overview mode, and shows the filename when on a note line.

### Changed
- **`type_prefix` compact format** — note type prefix in all note-listing
  displays changed from `[  note   ]` (11 chars) to `[n]` (3 chars). Mapping:
  `note → n`, `agg → a`, `bib → b`, `journal → j`, `scratch → s`,
  `other → o`, `file → f` (bufpanel non-PKM files), `subview → v` (view
  picker subview entries). Implemented via new `_TYPE_ABBREV` table in both
  `views.lua` and `ui.lua`; `type_prefix` function replaced. Display columns
  throughout sidebar, bufpanel, and all pickers reduced by 8 characters per
  entry.
- **`renumber_sequence` upgrade** (`markdown.lua`) — rewritten with a
  per-level counter stack and two new families:
  - **Nested lists**: effective depth is computed as blockquote depth (2 per
    `>`) + indent depth (1 per space, 4 per tab). `counters[depth]` tracks
    the counter at each level; stepping to a shallower depth clears all
    deeper entries so sub-lists restart from 1 under each new parent item.
  - **Blockquote-prefixed lists**: `>` and `>>` prefixes are stripped before
    pattern matching and restored in output unchanged. Blockquote depth is
    included in the effective depth so `>` and `>>` items at the same text
    indent maintain independent counters.
  - **Emphasis-wrapped ordinals** (`list_emph` family): detects `*N*[.)]`
    and `**N**[.)]` as list markers (single and double emphasis). Uses the
    same per-level counter stack as plain lists. Detected after plain list,
    before header families, preserving detection order discipline.
  - **Header families** (`hdr_prefix`, `hdr_suffix`): behaviour unchanged;
    use a flat counter; now also handle blockquote-prefixed headers.
  - All families now accept leading `>` blockquote markers on every line.
  - Detection order preserved: `list` → `list_emph` → `hdr_prefix` →
    `hdr_suffix`.

- `:PKMBrowse` is now the primary note browser (`<leader>nf`). With Telescope,
  the prompt is a live filter bar: each keystroke evaluates the expression
  through `filter.lua` against the full index. Bare text (no prefix) triggers
  the `any` predicate; structured expressions (`tag:x AND title:y`) work as
  before. `:PKMBrowse <expr>` still pre-seeds the prompt. Falls back to a
  single `vim.fn.input` prompt when Telescope is unavailable.

- `telescope.browse_paths` and `ui.browse_paths` now resolve paths to index
  entries and route through `live_picker`. The sidebar `/` and views-tree
  `<C-f>` searches now evaluate the live prompt against the scoped entry set
  (§2.4 shared engine), replacing the old display-string substring match.

- `config.keymaps.search` removed; `config.keymaps.browse` defaults to
  `"<leader>nf"`.

- `:PKMViewUpdate` (`M.edit_view`) — extended beyond filter-expression editing.
  Now presents an action picker: "Edit filter expression" (existing behaviour),
  "Rename" (renames the sidecar key; propagates to any child subprojects whose
  `parent` field referenced the old name; updates `_last_view` and the current
  tabpage's `name` field if they match), and "Change parent" (subprojects only;
  validates against ancestor-descendant cycles via a recursive descendant
  check before writing). Rename and Change parent are shown only when the view
  exists in views.json (config-only views show only "Edit filter expression"
  with a note to edit the Neovim config for structural changes). New local
  helpers: `rename_view_prompt`, `reparent_view_prompt`.

- **Per-tabpage sidebar state (`views.lua`)** — the nine flat `_sidebar_*`
  module-level variables replaced by a `_tabs` table keyed by
  `nvim_get_current_tabpage()`, accessed via a `get_tab()` local helper.
  A `TabClosed` autocmd in `M.setup()` prunes dead tab entries.
  `refresh_sidebar_if_open()` now iterates all tabpages so note deletions and
  renames refresh sidebars in every tab, not only the caller's.
  `BufWipeout` autocmd in `open_sidebar` clears only its own tab's entry.
  `rename_view_prompt` updated to patch `t.name` on the current tab rather
  than a flat `_sidebar_name` global. This is the prerequisite for Phase 3's
  unified explorer UI; `ui.lua` bufpanel state receives the same treatment
  (see next entry).

- **Per-tabpage bufpanel state (`ui.lua`)** — `_bufpanel_win`, `_bufpanel_buf`,
  `_bufpanel_augroup`, and `_bufpanel_map` replaced by a `_tabs` table keyed by
  `nvim_get_current_tabpage()`, accessed via `get_tab()`. A `TabClosed` autocmd
  added to `M.setup()` prunes dead tab entries. Bufpanel augroup is now
  tab-scoped (`PKMBufPanel_<id>`) to prevent cross-tab autocmd collisions.
  `BufWipeout` clears only the relevant tab's entry and deletes its augroup.
  Phase 2 Item 1 complete: both sidebar (`views.lua`) and bufpanel (`ui.lua`)
  state are now per-tabpage.

### Removed
- `:PKMSearch` and its backers `telescope.search_notes` / `ui.search_notes` —
  raw Telescope `live_grep` over PKM files. Body search is absorbed by
  `:PKMBrowse` (any predicate); frontmatter/citation noise eliminated because
  matching now runs over structured index fields.

- Dead emphasis-wrapping keymap defaults from `config.lua` (`wrap_italic`,
  `wrap_bold`, `wrap_bold_italic`, `wrap_code`, `wrap_strike`) — removed in
  1.4.1 but defaults were not cleaned up.

### Fixed
- **`syntax.lua` `M.enable()` missing closing `end`** — `M.disable()` was
  being defined as a local function inside `M.enable()`, causing the module to
  error on load. Added missing `end` after the `UndoPost` autocmd registration.

- **`renumber_sequence` missing `if not kind` guard** — the early-return with
  user notification was dropped during the detection loop rewrite. Without it,
  unrecognized ranges silently wrote back unchanged content with no feedback.
  Guard restored between detection loop and renumber section.

- **Help float clips `<C-v>` line** — `sidebar_show_help` had `local width =
  30`, clipping the 38-char `<C-v>` line. Corrected to `40`.
- **Frontmatter fold not closed on buffer open** — tree-sitter's async initial
  parse reset window options set in the same tick. Fix: `enable()` now wraps
  the initial `setup_win_matches`/`setup_win_opts` calls in `vim.schedule` so
  they run after the first parse completes. `setup_win_opts` now also calls
  `silent! normal! zM` to force-close the frontmatter fold immediately.

- **Tree-sitter `end_row out of range` on delete and undo** — `nvim_buf_set_lines`
  (from `renumber_sequence`) and undo operations left tree-sitter's extmark
  positions stale, causing the highlighter decoration provider to error when
  the buffer shrank. Fix: (1) `UndoPost` autocmd in `syntax.enable()` restarts
  the tree-sitter parser after every undo; (2) `renumber_sequence` schedules
  `vim.treesitter.start` after its `nvim_buf_set_lines` call when PKM mode is
  active.

- **`renumber_sequence` skips items with no body text** — patterns required a
  space after the separator, so `> 1.` (no text) was never matched; only items
  with text (`> 4. a`) were renumbered. Fix: all detection and renumbering
  patterns for `list` and `list_emph` families now use a two-pass approach —
  match with body first, fall back to a no-body/end-of-line pattern.

- **Sidebar help float included note-level fold keymaps** — `za`, `zM`, `zR`
  are native Vim commands applicable to the current buffer (notes), not sidebar
  navigation. Removed from `sidebar_show_help()`; `foldtext` already advertises
  `za`. Width adjusted to fit shorter content.
- **Unwanted conceal (backticks, link brackets, citation brackets)** — setting
  `conceallevel = 2` in `setup_win_opts` activated ALL built-in tree-sitter
  markdown conceal rules, including code span delimiters and link brackets,
  causing `bib[0042]` to display as `bibnumber`. Removed `conceallevel` and
  `concealcursor` settings entirely; removed wiki-link Conceal matchadd
  patterns. Built-in tree-sitter markdown conceals are suppressed when
  `conceallevel = 0` (Neovim default).

- **YAML highlight colour** — yaml injection highlight groups mapped to
  pink/magenta in kanagawa-wave. Added overrides in `setup_hl_groups()`:
  `@property.yaml → Identifier`, `@string.yaml → Normal`,
  `@punctuation.*.yaml → NonText`, `@boolean.yaml → Keyword`,
  `@number.yaml → Number`.

- **`[No Name]` and line/col counter in sidebar and bufpanel statuslines** —
  lualine rendered its default statusline (filename + location) in these
  windows. Fixed by setting `filetype = 'pkm-sidebar'` / `'pkm-bufpanel'` on
  the buffers and overriding `statusline` via `vim.schedule` in a `WinEnter`
  autocmd, which runs after lualine's handler and replaces it with a concise
  hint line.

- **Syntax highlighting disappears after saving** — `noautocmd e` in
  `init.lua` BufWritePost reloads the buffer, which implicitly stops
  tree-sitter. Added `pcall(vim.treesitter.start, written_buf, 'markdown')`
  after the reload, guarded by `require('pkm.mode').is_active()`.

- **Fold behavior — `+` indicator, no visible toggle key** — default
  `foldtext` showed cryptic `+-- N lines: ---`. Replaced with
  `M.foldtext()` showing `▸ frontmatter (N lines) [za toggle · zR open all]`.
  Added `foldcolumn = '0'` to suppress gutter indicators. Documented `za`
  (toggle), `zM` (close all), `zR` (open all) in sidebar help float. Note:
  entering insert mode auto-opens folds (standard Neovim behaviour via
  `foldopen`); `za` or `zM` re-closes them without requiring a save.

- **Sidebar `/` search opens file over sidebar** — Telescope opened files in
  the window from which it was invoked (the sidebar). The `/` keymap now
  switches focus to the main editing window before invoking the picker, so
  file selection opens there.

- **Sidebar `<C-v>` keymap** — opens the note under cursor in a new vertical
  split. Finds the nearest main editing window and splits it; falls back to
  `rightbelow vsplit` if no other window exists. Available in detail mode only.

- **Sidebar help float** — updated to include `<C-v>`, fold keymaps, and a
  note that `/` now opens in the main window.
- **`syntax.lua` parse error on load** — the Lua long string `[[\]\]]]`
  (pattern for wiki-link closing `]]`) was parsed incorrectly: the level-0
  long string scanner found `]]` inside the content (`\]` + first `]` of the
  intended closing), truncating the content and leaving a stray `]` that
  caused `E5108: ')' expected near ']'` on every PKM note open. Fix: all four
  `matchadd` patterns in `setup_win_matches` switched to level-1 long strings
  (`[=[...]=]`), which close on `]=]` and are immune to `]]` in content.

- **4-space indented text highlighted as code** — `indented_code_block` nodes
  (tree-sitter) were mapping to `@markup.raw` (green code colour). New capture
  `@pkm.indented` in `queries/markdown/highlights.scm` re-assigns these nodes;
  `syntax.lua` links the group to `Normal` so indented text renders as prose.

- **List markers missing at 4th+ nesting level** — built-in markdown highlights
  may not define `@markup.list` for deeply nested list marker node types.
  `queries/markdown/highlights.scm` now explicitly captures all five marker
  node types (`dot`, `parenthesis`, `minus`, `star`, `plus`) at every depth.
- **`:PKMMode` trigger fires on every note open** — `M.activate()` was calling
  `vim.notify` unconditionally; if the `if not _active` guard in the
  `BufReadPost` callback was missing or bypassed, mode re-activated (with
  notification, panel re-checks, and index rebuild scheduling) on every PKM
  note open. Fix: (1) `M.activate()` now captures `was_active` before setting
  `_active = true` and only notifies when `not was_active`; (2) the
  `BufReadPost` callback restructured to early-return when `_active` is true,
  making the guard harder to accidentally drop. Both panels remain idempotently
  re-openable by `:PKMMode on` when already active.
- **Symbol abbreviations leave trailing space** — `setup_symbols` used
  `iabbrev` for `trigger` entries; Vim's abbreviation mechanism requires a
  non-keyword character (typically Space) to fire and inserts it alongside
  the expansion. Changed to `vim.keymap.set('i', ...)`, matching the
  existing `key` implementation. Expansions fire on the exact key sequence
  with no trailing space and no Space required to activate. `trigger` and
  `key` remain distinct fields for semantic clarity but now share the same
  implementation.

- **Cross-citation data loss (modified cited buffer)** — `manage_backlink` now
  detects whether the target buffer is open and modified before reading. If
  modified: reads from the buffer (not disk), applies the `cited_by` change via
  `nvim_buf_set_lines` over the entire buffer, writes nothing to disk, and skips
  `index.invalidate`; the user's next `:w` persists both their edits and the
  backlink through the normal `BufWritePost` cycle. If unmodified or not open:
  existing disk-write + index-invalidate + buffer-reload path is preserved.
  Decision: writing disk for the modified case is skipped because reconciling
  the on-disk mtime to suppress W11 has no clean API.

- **`:PKMBrowse` E488 on multi-token filter expressions** — command was
  registered with `nargs='?'`, causing Neovim to raise E488 on any expression
  with spaces before the handler ran. Changed to `nargs='*'`; `opts.args`
  delivers the full string unchanged.

- **Buffer panel E32 on `w`** — `BufWritePost` callback used `vim.fn.expand
  ("%:p")` inside `vim.schedule`, which reflects the current buffer at callback
  time rather than the buffer just written. After `bdelete` in the `w` keymap,
  the current buffer could be the panel's `nofile` scratch buffer (no name),
  causing `noautocmd e` to raise E32. Fix: capture `ev.buf` at autocmd
  registration time; derive `filepath` from `nvim_buf_get_name(written_buf)`;
  add `nvim_buf_is_valid` guards; run the reload inside
  `nvim_buf_call(written_buf, …)` so `noautocmd e` always targets the written
  buffer regardless of which window is current.

- **Buffer panel phantom window on last-buffer close** — closing the last
  regular buffer via `d`, `D`, or `w` in the panel could leave the panel as
  the only window, causing Neovim to reposition it and create a non-interactive
  gap below it. New module-level local `ensure_main_window()` is called after
  every `bdelete` from the panel: if no non-panel, non-float window remains, it
  opens `noautocmd aboveleft new` relative to the panel, preserving the layout.
  `D` keymap updated to report errors consistently with `d`.

- **Buffer panel `w` saves wrong buffer** — pressing `w` (save and close) was
  writing the buffer currently shown in the main editing window instead of the
  buffer selected in the panel. Root cause: the implementation switched to the
  main window via `nvim_set_current_win` then called `nvim_set_current_buf` to
  redirect it to the panel-selected buffer; autocmds triggered by the window
  switch could drift the current buffer before `write` executed. Fix: replace
  the window-switching sequence with `nvim_buf_call(bufnr, fn)`, which executes
  `write` in the context of the panel-selected buffer without touching any
  window — the same pattern used in `init.lua`'s BufWritePost reload. `bdelete`
  already names the buffer by number and was unaffected.

- **Buffer panel `d`/`D`/`w` close the editing window instead of the buffer**
  — `bdelete n` closes every window displaying buffer `n` before unloading it;
  when the main editing window was the only non-panel window, it closed rather
  than switching away. New module-level local `detach_buf_from_wins(bufnr)`
  iterates all non-panel non-float windows in the current tabpage that show the
  target buffer, switching each to its alternate buffer, another listed buffer,
  or a new empty buffer (`noautocmd enew`) in that priority order. Called by
  `d`, `D`, and `w` before any `bdelete` call. `d` and `D` gain an explicit
  `nvim_buf_is_valid` guard (previously only `if bufnr then`). This also
  consolidates the three keymaps to share the detach helper.

---

## [1.4.1] - 2026-6-8

### Added
- `markdown.lua`: `M.renumber_sequence(start_line, end_line)` — renumbers
  ordered-sequence items in a line range sequentially from 1. Family
  (list dot, list paren, header inline ordinal, header suffix counter) is
  detected from the first matching line; detection order (list → hdr_prefix →
  hdr_suffix) ensures a line like `## N. title-text-3` is always treated as
  hdr_prefix and only its leading ordinal is renumbered. Non-matching lines
  are preserved unchanged. Trailing non-digit annotations on suffix-counter
  headers are preserved.
- `markdown.lua`: `M.renumber_at_cursor()` — renumbers the sequence in the
  paragraph surrounding the cursor (blank-line bounded).
- `:PKMRenumberList` — `range = true` command. Normal mode: auto-detects
  paragraph. Visual mode: uses selection (bare `:` mapping lets Neovim
  prepend `'<,'>` automatically).
- Config key `keymaps.renumber_list` (default `false`).

### Fixed

- **`wrap_with_marker` operator-pending mode** — `nvim_feedkeys('g@', 'n', false)`
  appended `g@` to the typeahead buffer as a side effect rather than returning it
  as the keymap result. With multi-character leader sequences (e.g. `<leader>Mi`),
  this caused `g@` to not reliably enter operator-pending mode; subsequent
  keystrokes were then processed as ordinary normal-mode commands, moving the
  cursor without applying any wrapping. Fix: `wrap_with_marker` now returns `'g@'`
  instead of calling `nvim_feedkeys`. Normal-mode emphasis keymaps in `keymaps.lua`
  use `{ expr = true }` so the returned string is processed as the mapping's RHS.

- **`:PKMDeleteNote` with sidebar open** — deleted note remained visible in the
  sidebar until `r` was pressed. `delete_note_safely()` now calls
  `views.refresh_sidebar_if_open()` after a successful deletion and index
  invalidation. New public function `M.refresh_sidebar_if_open()` added to
  `views.lua`; also updates the module header.

- **Stale sidebar on external file deletion** — pressing `<CR>` on a note whose
  file had been deleted externally attempted `:edit` on a missing path and errored.
  A `vim.fn.filereadable(path)` guard in the detail-mode `<CR>` handler now
  detects the missing file and notifies the user instead of opening it.

- **Syntax highlighting lost after save** — `noautocmd e` suppressed all
  autocmds on buffer reload, including the `Syntax`/`FileType` events that
  restore per-buffer syntax definitions. `g:syntax_on` remained set but
  highlighting was gone until the buffer was manually reloaded. Fix: fire
  `doautocmd Syntax` after `winrestview`. This reloads the syntax file without
  re-reading the buffer, preserving the E518/modeline protection.

### Changed
- `:PKMViewNew` now prompts for view type (Simple view / Subproject) first,
  then follows the appropriate creation flow. Replaces the two-command surface
  (`:PKMViewNew` + `:PKMViewNewSub`). `views.save()` and
  `views.save_subproject()` are unchanged.

### Removed
- `markdown.lua`: `M.goto_heading(direction)` — duplicated built-in `]]`/`[[`
  exactly (any heading, any level). No differentiated behaviour; removed.
- `:PKMHeadingNext`, `:PKMHeadingPrev` — commands backed by `goto_heading`.
- Config keys `keymaps.heading_next`, `keymaps.heading_prev`.
- `:PKMViewNewSub` — superseded by the unified `:PKMViewNew`.
- **Emphasis wrapping** — `wrap_with_marker`, `_wrap_operator`, `_wrap_visual`,
  and all related locals (`apply_marker`, `strip_emphasis`, `EMPHASIS_MARKERS`,
  `_pending_marker`) removed from `markdown.lua`. `map_emphasis` and all
  `wrap_*` keymap slots removed from `keymaps.lua` and `config.lua`. Use
  vim-surround for all wrapping operations.

---

## [1.4.0] - 2026-6-7

### Added

- **Sidebar two-mode navigation** — `open_sidebar(nil/'')`  now opens in
  overview mode (full views hierarchy, same tree as `:PKMViews`) rather than a
  prompt. `<CR>` on any view line enters detail mode. The two modes share one
  persistent window; state variables `_sidebar_mode`, `_sidebar_view_lines`,
  `_sidebar_history` track current mode, line-to-view mapping, and history.

- **Sidebar navigation history** — a session-scoped stack of `{mode, name}`
  entries capped at 50. `sidebar_push_history()` / `sidebar_pop_history()` are
  module-level locals. `<BS>` pops to the previous state; if the stack is empty,
  falls back to overview from detail or notifies from overview. `<C-b>` jumps
  directly to overview, pushing the current state first. History is wiped on
  sidebar close.

- `views.get_last_view()` — returns the name of the active view for
  context-aware consumers. Prefers the sidebar's open detail view; falls back
  to `_last_view`.

- `telescope.browse_paths(title, paths)` — scoped Telescope note picker over a
  pre-computed path list. Sorts by type then title. Uses `sorting_strategy =
  'ascending'` and `prompt_position = 'top'`. Never re-evaluates a filter.
- `ui.browse_paths(title, paths)` — `vim.ui.select` fallback for the same.

- **Sidebar `/` keymap** — in detail mode opens `browse_paths` scoped to the
  current view's path list; in overview mode opens full `PKMBrowse`. Sidebar
  remains open in the background.

- **Views tree `<C-f>` keymap** — in both `telescope_views_tree_picker` and
  `float_views_tree_picker`, `<C-f>` opens `browse_paths` scoped to the
  highlighted view. Prompt titles updated to advertise the keymap.

- Config: `keymaps.view_sidebar` default changed from `false` to `"<leader>nS"`.

- **Sidebar header keymap hints** — `sidebar_build_overview` and
  `sidebar_build_lines` now include a hint line in the buffer header advertising
  `<BS>/<C-b> back/views`, `/ search`, `r refresh`, `q close`. Addresses the
  discoverability gap: the navigation keymaps were implemented but not visible.

- `export.export_direct(label, paths)` — skips the filter form and opens the
  results picker (Telescope or float fallback) directly over a pre-computed path
  list. Computes a timestamped default destination path. Used by `:PKMExportView`
  and any future context-aware export.

- `:PKMExportView [name]` — export all notes in a named view without the filter
  form. Tab-completes view names. Without a name, presents a picker. Calls
  `export.export_direct(name, views.match_all(name))`.

- **`:PKMBuffers` persistent buffer panel** — `ui.toggle_bufpanel()` opens a
  `botright split` at the bottom listing all listed regular-file buffers. PKM
  notes display with `type_prefix` and title; non-PKM files show filename only.
  Modified buffers show ` [+]`. Height capped at 8 rows (`winfixheight`).
  Keymaps: `<CR>` open in main window, `d` close buffer, `D` force-close,
  `w` write+close, `r` refresh, `q`/`<Esc>` close panel. Auto-refreshes on
  `BufAdd`, `BufDelete`, `BufWipeout`, `BufModifiedSet`. State cleared by
  `BufWipeout` autocmd. Config: `keymaps.view_buffers` (default `false`).

- **Context-aware citation picker** — `telescope.insert_citation_picker()` and
  `ui.insert_citation_ui()` now pre-score items before display. Score: `+2` if
  the item's path is in the active view (`views.get_last_view()` +
  `views.match_all()`); `+1` per tag shared with the current note (via
  `index.get(cur_path).tags`). Items sorted descending by score then
  alphabetically. Contextually relevant items prefixed with `~ `. When a view is
  active and has matching items, Telescope picker exposes `<C-v>` to toggle
  between full list and view-only mode via `picker:refresh()` without closing.
  No toggle in the `ui` fallback (no interactivity after selection).

- **`rename_note` extended to journal and scratchpad** — previously rejected
  non-consolidated files with "not a consolidated note". Now detects the PKM
  folder and branches: consolidated preserves number + type prefix and renames
  the title part; journal/scratchpad prompts for a full stem replacement with the
  current stem as the default. All paths propagate via
  `update_references_on_rename`.


### Fixed

- **Post-citation prompts:** (Fix attempt, but there have been new instances of
  the bug reported later on). Went back to getting prompts for loading file or
  pressing ok after adding a citation. This used to be solved, with the buffer
  self-updating after every citation. The cited note's buffer, if open, is also
  not updating unless I save the note that cites it. Behavior if the note is
  not open in a buffer is unknown, but this alone is an issue.

- `init.lua` `BufWritePost`: `yaml.save_frontmatter` writes frontmatter to
  disk and then calls `vim.cmd("checktime")`, forcing a buffer reload that
  triggers Vim's modeline scanner. Notes whose body contains `ex:`-style
  patterns can produce `E518`. 
  Fix:
  - Added a `BufWritePre` autocmd that updates `last_updated_on` in the buffer
    (Case A: `nvim_buf_set_lines`, no disk write) before Neovim's normal write
    cycle writes the buffer to disk.
  - Removed `yaml.save_frontmatter(frontmatter, content_start, filepath)` from
    `BufWritePost`, eliminating the redundant second disk write.
  - Replaced `vim.cmd("checktime")` with `noautocmd e` + `winsaveview`/
    `winrestview`: silent buffer reload that preserves cursor position and
    suppresses autocmds, avoiding the "file changed on disk" prompt.
  - `manage_backlink`: after writing the cited note's `cited_by` frontmatter to
    disk, iterates open buffers and silently refreshes any loaded, unmodified
    buffer whose path matches the target, preventing the "file changed on disk"
    prompt when the user switches to the cited note.

- **`rename_note` E180 error** — `vim.fn.input('Rename note: ', name_part:gsub('_', ' '))`
  passed two return values from `gsub` (string + substitution count); Vim treated
  the integer as the completion type argument and errored. Fix: extra parentheses
  `(name_part:gsub('_', ' '))` discard the second return value.

---

## [1.3.3] - 2026-6-7

### Added
- View picker navigation keymaps (both Telescope and float variants of
  `telescope_view_picker` / `float_view_picker`):
  - `<C-b>` — return to the PKM Views tree overview (`M.list_views()`)
  - `<C-p>` — open the parent view directly; notifies if none exists
  - `<C-s>` — open a subview picker; if only one subview exists opens it
    directly; notifies if none exist
  These keymaps are documented in the picker's prompt title.
- `index.lua`: `note_type` field added to every index entry. Computed at
  index-build time from the filename stem: `note`, `agg`, or `bib` for
  consolidated notes; `journal` for journal entries; `scratch` for scratchpads;
  `other` for anything else. Local helper `get_note_type(stem)` encapsulates
  the classification logic.
- `views.lua`: `sort_paths_by_type(paths)` — sorts a path list by note type
  (note → agg → bib → journal → scratch → other) then alphabetically by title
  within each type. `type_prefix(note_type)` — formats a type as a fixed-width
  bracket label `[note   ]`, `[journal]`, etc. for display alignment.
  `_TYPE_ORDER` module-level table encodes the sort priority.

### Changed

- All note-listing pickers now display notes grouped by type with a fixed-width
  `[type   ]` prefix and sorted note→agg→bib→journal→scratch within each view.
  Applies to `telescope_view_picker`, `float_view_picker`, `sidebar_build_lines`
  in `views.lua`; `M.browse` in `telescope.lua` and `ui.lua`.
- `telescope_views_tree_picker`: ordinals are now position-encoded
  (`%05d` sequential index) instead of view names, so `sorters.empty()`
  preserves the exact depth-first order from `build_tree_entries()`. Prompt
  filtering matches against `item.name` (not ordinal), fixing the bug where
  subviews appeared under the wrong parent.
- `go_children` in both `telescope_view_picker` and `float_view_picker`:
  removed the single-child fast-path that called `M.open()` directly. Now
  always presents a `vim.ui.select` picker, giving the user explicit control
  regardless of how many subviews exist.
- `sidebar_build_lines` now returns a 4th value `sorted_paths` — the type-sorted
  path array whose order matches the displayed note lines. All three call sites
  in `open_sidebar` (initial open, replace-contents branch, and `r` refresh)
  updated to capture and assign this value to `_sidebar_paths`.

### Fixed
- `telescope_views_tree_picker`: replaced `generic_sorter` with
  `finders.new_dynamic` + `sorters.empty()`. `generic_sorter` applies fzy
  scoring which reorders the depth-first tree entries, placing subviews under
  the wrong parents in the display. The fix preserves the exact ordering from
  `build_tree_entries()` while still allowing exact substring filtering on
  view names via the prompt.

---

## [1.3.2] - 2026-6-7

### Added
- `views.lua`: `M.save_subproject(name, parent, filter_expr)` — validates the
  parent exists in the current view set and the filter expression is valid, then
  writes `{parent=parent, filter=filter_expr}` to views.json. The effective
  filter (parent chain composed via AND) is resolved at query time by
  `get_tree()`; no pre-computation needed here.
- `:PKMViewNewSub` — interactive command to create a subproject view. Prompts
  for subproject name, presents a picker of all existing views for parent
  selection, prompts for the own filter expression (the additional constraint
  only), then confirms before writing. Removes the need to edit views.json
  directly for subproject creation.

## [1.3.1] - 2026-6-7

### Added
- `views.lua`: `M.list_views()` — opens a tree-structured picker over all
  defined views in depth-first parent-child order. Each view displays its
  indented name with `▶` (has children) or `•` (leaf) and its current note
  count. Selecting a view calls `M.open()`. Telescope picker with
  `generic_sorter` (fzy is appropriate here — matching short view names, not
  structured content) when available; scrollable float fallback otherwise.
  Internal helper `build_tree_entries()` produces a depth-first ordered array
  of `{name, depth, has_children}` shared by both picker variants.
- `:PKMViews` updated — now opens the tree picker (`M.list_views()`) instead
  of a `vim.notify` comma list. Previous behaviour was unreadable beyond a
  handful of views.
- Config: `keymaps.view_list` (default `"<leader>nv"`).

---

## [1.3.0] - 2026-6-6

### Added

- `lua/pkm/markdown.lua` — new module for general markdown editing utilities.
  No setup() required; required lazily by command handlers.
  - `append_next_header()`: duplicates the header on the current line with its
    trailing counter incremented by one, appends at EOF after a blank separator.
    Handles trailing non-digit annotations (e.g. " (FGV)") transparently.
    Skips the separator if the buffer already ends with an empty line.
  - `shift_header_level(direction, start_line, end_line)`: shifts the `#`-level
    of all header lines in the given range up or down by one step. Level-1
    headers are left unchanged on decrease. Non-header lines pass through unmodified.
  - `wrap_with_marker(marker)`: enters operator-pending mode; the next motion
    defines the target range. Accepts any delimiter string.
  - `_wrap_operator(motion_type)`: operatorfunc callback invoked by Neovim
    after a g@ motion completes. Do not call directly.
  - `_wrap_visual(marker)`: wraps or unwraps the current visual selection.
    Called from visual-mode keymaps.
  - Toggle behaviour: same marker on an already-wrapped range removes it.
    Different marker replaces the existing emphasis without stacking.
    Longest-first matching (`***` before `**` before `*`) prevents partial
    stripping of compound markers.
  - Multi-line ranges are rejected with a warning; single-line only.
  - `setup_symbols(symbols)`: registers buffer-local insert-mode abbreviations
    and keymaps from a list of `{trigger?, key?, expansion}` entries. Called
    from the `BufReadPost` autocmd so registrations are scoped per buffer.
    Both fields are optional — an entry may have either, or both.
  - `goto_heading(direction)`: jumps to the next or previous ATX heading line
    (`#`-prefixed) in the current buffer. Notifies if none is found.
- Config: `keymaps.wrap_italic`, `wrap_bold`, `wrap_bold_italic`, `wrap_code`,
  `wrap_strike` — all default `false`. Assign in your setup call to enable.
- Config: `symbols = {}` — top-level list of `{trigger?, key?, expansion}`
  tables. Default empty. Populated by the user; no default symbols are shipped.
- `keymaps.lua`: `map_emphasis` helper registers both normal and visual mode
  bindings from a single call per marker.
- `:PKMNextHeader` — invoke `append_next_header()` from the current line.
- `:PKMHeaderLevelUp` — increase header level in range; default range is whole
  buffer. Accepts `'<,'>` prefix for selection-scoped operation.
- `:PKMHeaderLevelDown` — decrease header level in range; default range is whole
  buffer. Accepts `'<,'>` prefix for selection-scoped operation.
- `:PKMHeadingNext` — jump to the next ATX heading in the buffer.
- `:PKMHeadingPrev` — jump to the previous ATX heading in the buffer.
- Config: `keymaps.next_header` (default `<leader>mh`), `keymaps.header_level_up`,
  `keymaps.header_level_down`, `keymaps.heading_next`, `keymaps.heading_prev`
  (all except `next_header` default `false`).
- **Free-form `title` field — title decoupled from filename.**
  - `filter.lua`: `filename:` predicate added to the filter grammar. Matches
    the file stem (without extension) as a case-insensitive substring. The note
    data table now carries a `filename` field alongside `path`, `title`, `tags`,
    and `body`.
  - `index.lua`: `filename` field added to every index entry (file stem without
    extension). Title computation updated: uses `fm.title` if non-empty,
    otherwise derives from the filename stem with underscores replaced by spaces.
    This fallback ensures `title:` predicates always have a non-empty value to
    match against even for notes without an explicit `title` field.
  - `notes.lua`: `M.rename_note()` — prompts for a new name, sanitizes it,
    renames the file on disk, invalidates both paths in the index, redirects the
    buffer via `keepalt file`, and propagates the rename through citations. Does
    not touch the `title` frontmatter field. Consolidated notes only.
  - `:PKMRenameNote` — invoke `rename_note()` from the current buffer.
  - Config: `keymaps.rename_note` (default `<leader>nr`).
- `telescope.lua`: `M.browse(filter_expr?)` — new note browser. Pre-filters the
  index using a `filter.lua` expression at open time; the Telescope prompt then
  applies exact substring narrowing over the pre-filtered set. `finders.new_dynamic`
  + `sorters.empty()` ensures fzy is never applied to structured filter results.
  Empty or nil expression shows all notes. Display format: `title  (filename)`.
- `ui.lua`: `M.browse(filter_expr?)` — `vim.ui.select` fallback with identical
  index + filter pipeline and display format.
- `:PKMBrowse [filter_expr]` — browse PKM notes with an optional filter expression
  in the `filter.lua` grammar (`tag:math AND title:fourier`, `filename:0042`, etc.).
  Tab-completable predicates: `tag:`, `title:`, `text:`, `filename:`. Telescope
  picker when available; `ui.browse` fallback otherwise.
- Config: `keymaps.browse` (default `false`).
- **Subproject hierarchy for views** — `get_tree()` in `views.lua` now handles
  both string values (simple views) and table values (subprojects). A subproject
  entry has `parent` and `filter` fields; its effective filter is the parent's
  filter AND-ed with its own. Resolution walks the parent chain recursively at
  query time using `filter.lua`'s existing AND node — no new parser work needed.
  Cycle detection tracks visited names and returns an error on re-entry. Depth
  is capped at 8 levels. Caching is unaffected: composed trees are cached after
  first resolution; `invalidate()` clears all caches on any views.json change.
  Subprojects are authored via `:PKMViewEdit` (direct views.json editing).
  `views.json` format extended: string values remain simple views (backward
  compatible); table values declare subprojects:
```json
  {
    "ringforge": "tag:ringforge",
    "ringforge-mechanics": { "parent": "ringforge", "filter": "tag:mechanics" }
  }
```

- **`:PKMViewLast`** — reopens the last view activated in the current session.
  `views.lua` tracks `_last_view` (set in `M.open()` on every successful
  activation). `M.open_last()` calls `M.open(_last_view)` if set, or notifies
  if no view has been activated yet. Session-scoped by design: does not persist
  across Neovim restarts. New command `:PKMViewLast` in `commands.lua`. New
  keymap `view_last` (default `<leader>nV`) in `config.lua` and `keymaps.lua`.

- **`:PKMViewSidebar` — persistent split buffer for view navigation** — opens a
  full-height vertical split at the far left listing the active view's notes.
  `M.open_sidebar(name?)` in `views.lua`:
  - No name + sidebar open → closes. No name + sidebar closed → prompts for view.
  - Same name called again → toggles closed. Different name → replaces contents.
  - Buffer keymaps: `<CR>` opens the note under cursor in the last focused
    non-sidebar window (uses `winnr('#')` — Neovim's alternate window — with
    fallback to first non-sidebar non-float window, then `rightbelow vsplit` if
    no other window exists); `r` refreshes against the current index;
    `q` / `<Esc>` closes.
  - Window is `winfixwidth`, no line numbers, `cursorline` enabled. Buffer is
    `nofile`/`bufhidden=wipe`. State (`_sidebar_win`, `_sidebar_buf`,
    `_sidebar_name`, `_sidebar_paths`) is cleared automatically by a
    `BufWipeout` autocmd, covering `:q` and external window destruction.
  - Focus returns to the previous window after the sidebar opens.
  - New command `:PKMViewSidebar [name]` (tab-completes view names) in
    `commands.lua`. New keymap `view_sidebar` (default `false`) in `config.lua`
    and `keymaps.lua`. New config key `sidebar_width` (default `40`).
- **Sidebar tree header** — the sidebar buffer gains a navigable tree header
  when the active view participates in the subproject hierarchy (has a parent
  or children). Flat views (no parent, no children) retain the original simple
  header unchanged.
  - Layout (top to bottom): optional parent line `▶ name (N)`, current view
    line `▼ name (N)`, zero or more child lines `▶ name (N)`, separator, blank,
    note entries. Note count for each related view is computed via `match_all`.
  - `<CR>` on any `▶` line calls `M.open_sidebar(name)` for that view.
    `<CR>` on the `▼` line (current view) is a no-op.
  - `<BS>` navigates to the parent view, or notifies if no parent exists.
  - `sidebar_build_lines(name, paths)` refactored to return
    `(lines, tree_entries, header_count)`. `tree_entries` is a sparse table
    keyed by 1-based line number; `header_count` is the total number of
    non-note prefix lines. Both are stored in new module state variables
    `_sidebar_tree` and `_sidebar_header_count`, cleared by `BufWipeout` and
    the external-close guard.
  - Two new internal helpers: `get_view_parent(name)` and
    `get_view_children(name)`.

### Changed

- `filter.lua`: the `title:` predicate now matches the free-form YAML title
  with a filename-derived fallback (consistent with the index entry). The
  grammar comment and note data table comment updated to reflect the `filename`
  field. `parse_atom` error message updated to list all four valid fields.
- `index.lua`: entry shape extended with `filename` (file stem without
  extension). Title fallback logic added to `read_entry`. `Consumed by` comment
  updated to remove stale `(planned)` annotations.
- `init.lua`: `BufWritePost` autocmd no longer calls `notes.sync_filename_on_save`;
  `notes` local removed from the callback. `BufReadPost` autocmd no longer calls
  `notes.sync_yaml_on_rename`; now calls `require('pkm.markdown').setup_symbols`
  instead. `setup_sync_autocmds` LuaDoc updated to reflect current behaviour.
- `commands.lua`: `register()` reorganized with inline section separators
  (Note creation / Note file operations / Note conversion and promotion / Sync
  control / Search and browse / Citations / Navigation and linking / Stats /
  Views / Markdown editing). No functional changes.
- `telescope.lua` `browse_tags()`: rewritten to use `citations.get_all_tags()` +
  the index+filter pipeline. Now a simple tag picker that opens `M.browse('tag:<selected>')`.
  Ripgrep dependency removed entirely from this function.
- `ui.lua` `browse_tags()`: same rewrite as the Telescope version.
- `ui.lua`: removed unused `yaml` module-level variable and its `setup()` assignment;
  the old `browse_tags` was the only caller.
- `telescope.lua` `require_telescope()`: added `sorters` to the returned table
  (required by `M.browse`).
- `:PKMSearch` description updated to clarify scope: raw streaming text search via
  ripgrep (`live_grep`). Not a replacement for `:PKMBrowse`.

### Removed

- **`notes.sync_filename_on_save`** — automatically renamed the consolidated
  note file on every `BufWritePost` to match the `title` frontmatter field.
  Removed as part of the title decoupling: `title` is now a free-form field
  and the system never drives filename changes from it. The `BufWritePost` call
  site in `init.lua` removed.
- **`notes.sync_yaml_on_rename`** — automatically overwrote the `title`
  frontmatter field on every `BufReadPost` with a value derived from the
  filename. The round-trip was lossy (special characters stripped by
  `sanitize_title` were never recoverable). Removed as part of the title
  decoupling. The `BufReadPost` call site in `init.lua` removed.
- **`journal.sync_yaml_on_rename`** — was writing `date` and `time` fields not
  present in the journal template, conflicting with `created_on`/`last_updated_on`
  design. The `BufReadPost` call had already been commented out. Function body
  deleted from `journal.lua`; commented-out call removed from `init.lua`.

---

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
  - `M.setup_auto_update()` and `M.update_last_modified()` in `yaml.lua`, both
    which were overriden by functions in `init.lua`.

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

---

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
