# PKM.nvim — Changelog

---

## [Unreleased]

*The sections below are living project state, not release notes: they are
carried forward from version to version and consulted before any fix.*

### Status checkpoint (post-v1.61.1, 5/8/2026)

- **Full headless suite green: 89/89** `test_*.lua` files report their pass
  marker (`test_phase1_old` passes by self-skipping its populated-root assertions
  on the empty temp root — legacy, not a regression). Run after the v1.61.1
  docs-only batch; `git show --stat HEAD` confirmed that commit touches no `lua/`.
- **Pending-features audit** (verified against live code, not just docs): the only
  **non-deferred, near-term** pending features are two — the **forced-save prompt**
  (Near 5.1; `bufsync.lua` still prompts via `vim.fn.confirm`) and the
  **`pkm.sidebar` extraction** (no `lua/pkm/sidebar.lua`; host still in
  `views.lua`). Everything else pending is deferred or long-horizon — see
  ROADMAP § Forward plan by area, "Pending-features status".

### Known Bugs (queued)

*(Six entries were closed in v1.10.1: the `ex:` modeline in Ph1, the two test
drifts in Ph2, `:PKMOrphans` and the `bench.lua` separator in Ph3, the absolute
`original_path` in Ph4 and the `E484` on emptying the trash in Ph5 — the last
two found while evaluating multi-vault support, along with the one below.)*

*No open bugs. (The `PKMCitation` highlight bug found 27/7/2026 — the `matchadd`
regex that never fired — is **fixed in v1.17.0**; see that entry.)*

### Known limitations

- **The add/remove tag panel is always the built-in list, never a Telescope
  picker.** `:PKMTag add`/`remove` (and the `:PKMAddTag`/`:PKMRemoveTag`
  aliases) with no tag call `ui.open_tag_panel(mode)` directly, which has no
  Telescope variant — unlike browse, citations and tag-merge, which pick
  Telescope when it is present. Fine at ≤5 tags on a note; degrades past ~10,
  where a fuzzy picker would matter. Pre-existing (v1.13.0 preserved it
  verbatim); noticed during the v1.13.0 smoke. Fix is a `telescope`-branch in
  the tag handler mirroring the other panels' fallback pattern — a candidate to
  fold into v1.14.0.

- `notes.is_same_file()`'s case-fold fallback is gated on
  `utils.is_windows`/`utils.is_wsl` (session-level) rather than a per-path
  filesystem case-sensitivity check, which `pkm.utils` doesn't currently
  expose. Safe for the current single documented root (`P:/Notes`, NTFS,
  always case-insensitive); would misbehave if a root were ever pointed at
  a case-sensitive filesystem from a Windows/WSL session. Revisit only if
  that assumption changes.

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

## [1.71.2] - 11/8/2026

*Fix the sidebar/buffer-panel note-open bug found in the v1.67.0 & v1.71.0 smoke
(notes 0289, 0293), and stop the auto-sidebar stealing focus from the note.*

### Fixed

-   **`:quit`-ing the last note window with the sidebar AND buffer panel open no
    longer strands the tabpage on panels.** `panel.ensure_main_window` returned as
    soon as it found any non-float window other than its own — but with two panels
    open, each panel counted the OTHER panel as a "main window", so neither
    recreated an editing window. The tabpage was left panels-only, the sidebar
    collapsed to a full-width strip above the buffer panel, and note-opens landed
    in the wrong place. It now ignores `pkm-*` panel windows when deciding, and
    recreates the main window on the side that suits the panel (beside a
    managed-width side panel, above a bottom bar), restoring its managed width so
    the sidebar snaps back to a left column instead of a strip.
-   **The sidebar's nav `<CR>` no longer dead-ends with "the note window is gone".**
    When the source note's window was closed (e.g. by that `:quit`) but its buffer
    still lives, `nav` now re-displays the note in an editing window and jumps,
    instead of warning and doing nothing. It only reports the note as gone when the
    buffer itself is truly gone.
-   **The auto-sidebar (v1.71.0, Item 13) no longer steals focus from the note.**
    `M.activate()` opens the sidebar (which is `focus_on_open = true` — correct when
    opened directly via `:PKMPanel`), but on auto-activation the user wants to stay
    in the note they just opened. `activate()` now restores focus to the origin
    window after opening the panels. This also fixed 11 headless tests that had
    been silently reading the sidebar buffer instead of the note since the v1.71.0
    default flip (the suite is genuinely 101/101 again).

### Tests

-   `test_sidebar_reopen.lua` (new, 8 checks): proves the main-window recreation
    (editing window restored, sidebar keeps its managed width) and nav's revive
    path. `test_v190_p2.lua` now opens the sidebar deterministically (guarded, not
    a blind toggle) so the auto-sidebar default can't shut it.

## [1.71.1] - 11/8/2026

*Docs (`doc/pkm.txt`): unambiguous help navigation + panel keymaps (Items 7, 8).*

### Fixed

-   **Help index links land in `pkm.txt` regardless of cursor position (Item 7).**
    The CONTENTS is now a pure-link TOC — each entry *is* its `|pkm-…|` tag, so
    `CTRL-]` on a line jumps into this file instead of Vim's/Lazy's help for a bare
    label word (`Keymaps`, `Installation`) that used to sit to the left of the link.
-   **Broken `|pkm-search|` reference (3 call sites) now resolves** — added the
    `*pkm-search*` tag to the WORKFLOW SEARCH subsection it pointed at.

### Added

-   **Panel keymaps documented — `*pkm-panel-keymaps*` in §12 (Item 8).** A new
    subsection lists the buffer-panel keys (`<CR>`, `[count]<CR>`, `<C-v>` split
    right, `<C-x>` split left, `/`, `<C-g>`, `d`, `q`/`<Esc>`) and the browse/views
    picker keys (`<Tab>`/`<S-Tab>` mark, `<C-a>` bulk act, `<C-t>` type cycle, `<C-l>`
    pop-up provider cycle, plus the descriptor prompt), and cross-refs the sidebar.
    Both `|pkm-sidebar|` and `|pkm-panel-keymaps|` are now in the CONTENTS index, and
    the sidebar's `<C-n>` (views↔nav) key was added to the `pkm-sidebar` section. All
    keys verified against source; helptags clean.

## [1.71.0] - 11/8/2026

*Re-enable the automatic sidebar in `:PKMMode` (backlog P7 / Item 13).*

### Changed

-   **`:PKMMode` opens the sidebar by default again (Item 13).**
    `config.pkm_mode.layout.sidebar` default flipped `false → true`, so `M.activate()`
    opens the sidebar (which follows focus — nav for a markdown note, views otherwise)
    alongside the buffer panel. The space budget is favourable now: Item 11 (line
    numbers) is skipped, so nothing competes for the left margin, and the **v1.67.0**
    panel-space fixes removed the multi-panel E36/cmdheight problems. One reversible
    config value (`layout.sidebar = false` restores the old behaviour); the space
    *feel* rides the author's smoke.

## [1.70.0] - 11/8/2026

*Syntax batch, delivered through the **pkm-syntax** sibling dependency: the
`((meta-comment))` paren-balance fix (Item 3) and XML/angle-bracket marker
highlighting (Item 4); the `<…>`-cascade (Item 5) root-caused as a grammar limit
and documented. The code lives in `pkm-syntax/lua/pkm-syntax/init.lua`; **the
author must push the pkm-syntax repo** for `:Lazy sync` to pick it up. pkm-nvim's
own `lua/` is unchanged — this version carries the suite coverage + docs.*

### Fixed (pkm-syntax)

-   **`((meta-comment))` keeps its final `)` when the body ends in a parenthetical
    (Item 3).** `find_meta_comments` scanned for the close with a lazy
    `%(%(.-%)%)`, so `((… (probably a level-2 heading)))` stopped at the FIRST
    `))` — the inner aside's `)` plus one meta `)` — dropping the last `)`. Rewrote
    it as a paren-depth balancer: from the opening `((`, each `(` deepens and each
    `)` closes, and the comment ends at the `)` that returns depth to 0; a lone
    balancing `)` (unbalanced inner parens) is rejected. Bounded to
    `MAX_META_COMMENT_LINES`. Covered by `test_v159_p3.lua` (13/13, +5 cases).

### Added (pkm-syntax)

-   **XML/angle-bracket marker highlighting — `PKMXmlTag` (Item 4).** A matchadd
    pattern (`xml_tag_pattern`, linked to `Identifier`) colours `<tag>`, `</tag>`,
    `<tag/>`, `<tag attr="x">`, and bare placeholder markers `<deslocamento_exemplo-1>`
    (the name may carry `_`/`-`). A leading `[A-Za-z]` requirement keeps it off prose
    (`a < b`, `<3`). Being matchadd, it fires by regex independently of tree-sitter —
    so it colours the marker even on a line the grammar folded into an html_block
    (see Item 5). Perf-safe (per-window, like the legal-marker patterns). Covered by
    `test_xml_marker.lua` (11/11).

### Notes

-   **Item 5 (`<…>` line reads like a header; highlights vanish below) — grammar
    limitation, documented, no code fix.** A headless tree probe showed a bare valid
    HTML/XML tag line starts a CommonMark **HTML block** in Neovim's *bundled*
    markdown grammar, which folds every following line into it until a blank line
    (type 6/7) or EOF / close tag (type 1: `<pre>`/`<script>`/`<style>`/`<textarea>`)
    — swallowing the headings below. pkm-syntax cannot change block segmentation. The
    literal report string `<deslocamento_exemplo-1>` (underscore) does **not**
    reproduce — `_` is not a valid HTML tag name, so it stays a paragraph; the hyphen
    form does. Documented in the module's *Known behaviour* with the mechanism and
    three workarounds (blank line after the marker, backticks `` `<tag>` ``, or an
    underscore in the name). The new `PKMXmlTag` highlight at least makes such a
    marker read as an intentional marker rather than a broken header.

## [1.69.0] - 11/8/2026

*Reopen the previous pop-up search with `<leader>fP`. (Backlog P6 / Item 10;
plus P5 / Item 9 resolved with no code.)*

### Added

-   **Resume the last pop-up search — `<leader>fP` (Item 10).** Opening the pop-up
    (`<leader>fp`) is always a FRESH search by design: search, open a note, reopen
    → clean. The new `<leader>fP` (`keymaps.nav_search_resume`) instead reopens the
    **previous** search with its prompt and results intact, via Telescope's native
    resume (`popup.resume()`; needs Telescope — the `vim.ui.select` fallback keeps
    no picker to restore).

### Notes

-   **Item 9 (netrw as last-active) — resolved, no code.** netrw's exclusion from
    `utils.PANEL_FILETYPES` is independent of the sidebar/buffer-panel lock (those
    are locked by their own `winfixbuf`/filetypes); it exists so a note is not
    opened into the file explorer. Author chose to keep netrw excluded.

## [1.68.0] - 10/8/2026

*Pressing `<CR>` inside an ordered list now continues the numbering. (Backlog
P3 / Item 1.)*

### Added

-   **`<CR>` continues an ordered list (Item 1).** In a PKM note, pressing `<CR>`
    inside a plain ordered-list item now splits it: the text after the cursor
    becomes the **next-numbered** item and the family cascade-renumbers so the
    following items stay sequential. It fires wherever the cursor is on the item
    (end of line → a fresh empty next item; mid-text → the tail moves down), and
    on any non-list line — or while a completion menu is open — it falls back to an
    ordinary newline, so `<CR>` is unchanged everywhere else. Buffer-local to PKM
    notes (wired in `mode.enable_note_buffer`); reuses `markdown.renumber_at_cursor`
    (now with a `quiet` flag so it does not announce each keystroke). Pure core
    `markdown.plan_list_continuation`; `test_list_continue` (12).

*The buffer panel can open a note in a split, and reopening a note after closing
every editing window no longer crashes with E36. (Backlog P2/Item 6 + P4/Item 12.)*

### Added

-   **Buffer panel: open in a split (Item 6).** The bottom buffer panel had no way
    to open a note in a split. `<C-v>` opens the note under the cursor in a vertical
    split to the **right**, `<C-x>` to the **left** — each lands in a real editing
    window (never splitting a panel), matching the view sidebar's `<C-v>` / `<C-x>`.
    Vertical only; our panels don't use horizontal splits.

### Fixed

-   **Reopening a note after `:quit`-ing every editing window no longer crashes
    with E36 (Item 12).** With the sidebar and buffer panel open, closing all
    editing windows left only `winfixheight`/`winfixwidth` panels; the buffer bar's
    `<CR>` then split from a panel that could give no room → `E36: Not enough room`.
    New `utils.win_create_resilient` retries the window creation after dropping the
    fixed sizes across the tabpage, then restores them, so the note opens instead of
    crashing. Routed through every panel-relative window creation (`open_buffer` and
    `focus_editing_win`). The E36 is terminal-dimension dependent (not
    headless-reproducible); `test_win_resilient` locks the helper's contract.
-   **The command line no longer balloons (`cmdheight` → dead space) after `:quit`
    (Item 12).** With every editing window closed, the buffer panel and sidebar sit
    side-by-side as one full-height row. The panel's `resize` then shrank that row
    to a few lines — but with no editing window to absorb the freed rows, Neovim
    inflated `cmdheight` to fill them (measured: `cmdheight 1 → 38` on a 42-row
    screen, both panels crushed to 4 lines, a huge dead command-line area — the
    author's "command line pushed up" report). The resize now **skips while no
    editing window exists**, so the panel simply fills its column and `cmdheight`
    stays put; reopening a note creates the window and the panel shrinks normally.
    `test_bufpanel_cmdheight` locks it.
-   **Reopening a note no longer leaves it cramped in a sliver of space (Item 12).**
    Related: opening a note splits the (now full-height) panel, and its own resize
    ran on a delay — so the note briefly landed a few rows tall. The buffer-panel
    open actions now refresh the panel immediately, so it reclaims its compact
    height and the note gets the room (measured: note `h=36`, panel `h=3`).
-   **Buffer-panel split keys no longer crash with "Invalid window id".** The panel
    handlers read the cursor from a cached `state.win`, which layout churn can leave
    pointing at a closed window (`get_tab()` does not prune it). A new
    `panel_row_target` reads from the panel's window, falling back to the current
    window — which *is* the panel when its buffer-local mapping fires — so `<C-v>` /
    `<C-x>` (and the other row handlers, plus the tag panel's) never crash on a stale
    handle.
-   **Sidebar `?` help now works in nav mode.** The nav provider used a declarative
    keymap table that never bound `?`, so its help float never opened (only the
    views provider wired it). `?` is now bound in nav to the same centred keymap-help
    float (`views.show_keymap_help`, now exposed for peer providers), and the nav
    statusline advertises it.

## [1.66.0] - 10/8/2026

*Post-hoc metadata setters, and a rename that keeps its author marker. Renaming
a note now offers to change the title too; an agent (or any later correction)
can set a title or a bib note's source metadata without recreating the note; and
renaming an agent-authored note no longer silently strips its `By<Author>_` mark.*

### Added

-   **`:PKMNote rename` then offers to change the title.** After the filename
    rename succeeds, a non-obstructive prompt appears, pre-seeded with the current
    title. `<C-c>`/`<Esc>` (via `cancelreturn`), an unchanged value, or an emptied
    value all KEEP the current title — only a genuinely new value is written, and
    it is written THROUGH the buffer holding the just-renamed file, so a later `:w`
    never hits a phantom W12 prompt. The filename rename is never undone by the
    title step. *(Roadmap Triaged-backlog P1 / Item 14.)*
-   **`pkm.api.set_title(ref, title)` — post-hoc title setter.** The persisting
    twin of the buffer-only `:PKMNote settitle`: writes the frontmatter title to
    disk by ref, keeps any open buffer in step (write-through), and propagates the
    new title to every note that cites this one. Correcting a title no longer needs
    an uncite → delete → recreate cycle. *(Gestor de Recursos request #2, title half.)*
-   **`pkm.api.set_source_meta(ref, {author?, type?})` — post-hoc bib provenance.**
    Sets `source_author` / `source_type` on disk; only the keys given are written;
    source metadata is not part of the citation graph, so nothing propagates.
    *(Gestor request #2, source half.)*
-   New cores in `notes.lua`: `edit_frontmatter` — the reusable frontmatter
    write-through helper factored from the `manage_backlink` pattern (unmodified
    buffer written through and re-stamped; modified buffer changed in-buffer for the
    user's next `:w`; unopened note written to disk) — plus `set_title_at` and
    `set_source_meta_at` behind it. Tests: `test_set_meta_api.lua` (24/24),
    `test_rename_marker.lua` (15/15).

### Fixed

-   **Rename no longer drops the `By<Author>_` authorship marker.** `rename_note`
    and its headless twin `rename_note_at` rebuilt a consolidated stem as
    `NNNN_type_<name>`, replacing everything after the type prefix — so renaming
    `0009_bib_ByClaude_Foo` to `Bar` produced `0009_bib_Bar` and silently lost
    `ByClaude`, which made `agent_authored` read the note as human-written and
    disabled the agent delete-guard. The marker is now identity carried in the
    name, like the number/type prefix: `new_name` is the bare human name and the
    marker is re-attached automatically (same detection as `agent_authored`), so
    the caller need not — and must not — restate it. *(Gestor request #1.)*
-   **A save after a rename no longer demands `:w!` (E13).** `rename_file` renames
    the file underneath the buffer with `nvim_buf_set_name`, which leaves Vim's
    `BF_NOTEDITED` flag set — so a later `:w` to the now-existing path raised
    `E13: File exists (add ! to override)` even with no real conflict. The new
    title write-through both triggered this and had its write silently swallowed
    (the title never reached disk). `rename_file` now forces one silent,
    autocmd-free write of the identical on-disk bytes to clear the flag and stamp
    the buffer's timestamp, so ordinary saves — and the post-rename title write —
    are clean. This also closes the **latent** pre-existing case: rename a note,
    edit it, `:w` → previously E13, now clean. Found in the v1.66.0 smoke (§3);
    locked by `test_rename_title_flow.lua`.

## [1.65.0] - 7/8/2026

*In the search pickers, `tag:` now narrows as you type (contiguous substring),
instead of the list vanishing until the tag is spelled out in full. Saved views
keep exact `tag:`.*

### Added

-   **`tag:` narrows incrementally in the live search pickers.** `tag:` has
    always been an EXACT match (that is what makes a saved view `tag:rpg` mean
    the `rpg` tag and nothing near it), but in a search box that meant typing
    `tag:r` → `tag:rp` → `tag:rpg` showed an empty list until the very last
    keystroke. `filter.eval` now takes `opts.tag_substring`, which relaxes only
    the `tag:` rule to the same **contiguous** substring the other fields use —
    so `tag:rp` matches `rpg` and `my-rpg` as you type. It is a plain `find`,
    never a fuzzy subsequence: `tag:rpg` will never match `glorious-parmeggiano`
    or `responsible-parenting`. Passed by the live pickers only — `:PKMBrowse`,
    the view note-lists, the `<C-f>` Browse-All, and the `vim.ui.select`
    fallback. **Saved-view evaluation (`match_all`/`count_*`/`match_set`) and
    `tag_sets` do NOT pass it**, so view precision and `:PKMView remove` (which
    must know the single tag to strip) are unchanged: a view `tag:rpg` still
    means exactly `rpg`. `test_filter.lua` 171/171 (+10).

## [1.64.1] - 7/8/2026

*Filter descriptors now tolerate a space after the colon: `tag: rpg` works, not
only `tag:rpg`.*

### Fixed

-   **`tag: value` / `text: value` (a space after the field colon) now parse as
    the field predicate**, exactly like the glued `tag:value`. The tokenizer
    previously required the value to touch the colon; a space made `filter.parse`
    fail, and every live picker's lenient fallback then treated the whole thing
    as a literal any-search for the string `"tag: value"`, which matched nothing.
    Found in the v1.64.0 smoke: typing `tag: <anything>` (the reflexive spacing)
    returned no results in the browse and view pickers alike. The fix is in the
    shared grammar (`pkm.filter` tokenizer: skip whitespace after a known field's
    colon, then take the next quoted string or bare word as the value), so it
    lands on **every** surface at once — `:PKMBrowse`, the view note-lists, the
    sidebar `/`, and views.json filter expressions. A known field with nothing
    after the colon (`tag:`, `tag:   `) is still an error, unchanged.
    `test_filter.lua` 161/161 (+14).

## [1.64.0] - 7/8/2026

*Descriptor search (`tag:` / `text:` / …) now works in the view note-lists and
"Browse All Notes", not just `:PKMBrowse`.*

### Added

-   **The filter-descriptor language now drives every note-listing picker.** The
    prompt in a view's note list (Telescope `telescope_view_picker` and its
    no-Telescope float `float_view_picker`) and in the `<C-f>` **Browse All
    Notes** picker is now a live `filter.lua` expression —
    `tag:`/`text:`/`title:`/`filename:`/`type:` with `AND`/`OR`/`NOT` and quoted
    values, a bare word matching any field — exactly as `:PKMBrowse` /
    `<leader>ff` already behaved. Previously these three filtered the *visible
    display string* only (type prefix + title, title falling back to the
    filename stem), so `tag:x` / `text:x` were literal text and matched nothing —
    which read as "search only works by filename". Subview rows in a view's list
    are views, not notes, so they still narrow by name substring. The pop-up's
    `views` provider (searches view *names*) and `nav` provider (searches
    *headings*) are note-less by design and unchanged.

### Changed (internal)

-   **`filter.parse_prompt(prompt)`** extracts the lenient as-you-type parse rule
    (empty → nil "match all"; parseable → AST; partial/unparseable → bare
    `any:` predicate, so a half-typed expression never clears the list). One
    source of truth now shared by `telescope.live_picker` (de-duplicated to call
    it) and the three view finders. Pure; covered by `test_filter.lua`
    (147/147, +12 `parse_prompt` assertions).

## [1.63.1] - 6/8/2026

*Doc fix: the reference-materials tree is `P:\Resources`, not `P:\Recursos`.*

### Fixed (docs)

-   **Wrong reference-tree path corrected: `P:\Recursos` → `P:\Resources`** (WSL
    `/mnt/p/Recursos` → `/mnt/p/Resources`). The folder on disk is `Resources`; the
    docs had used the Portuguese "Recursos" throughout, so an agent following the
    bib doctrine (browse the reference tree, create a bib note) would look in a
    folder that does not exist. Corrected across the `pkm-notes` skill, `doc/
    AGENT_PROTOCOL.md` (§ 6.2, § 10), `doc/CONVENTIONS.md`, both `CLAUDE.md` files,
    `doc/LLM_CONTEXT.md`, and this changelog's historical entries. No code
    referenced the path. The **installed** `~/.claude/skills/pkm-notes` copy and
    the session memory were corrected in place; re-run `:PKMAgentProtocol install`
    to keep the distributed bundle in sync with the repo source.

### Notes

-   Known, not code-fixable here: `:help pkm-keymaps` not jumping to the KEYMAPS
    section is a **stale local helptags** issue, not a doc bug — the `*pkm-keymaps*`
    tag is correct and resolves to the section when helptags are current.
    Regenerate with `:Lazy sync pkm-nvim` (or `:helptags <pkm-nvim>/doc`). A
    generated `doc/tags` is deliberately not committed (it churns on every regen).

## [1.63.0] - 5/8/2026

*Command surface sorted onto the persistent-vs-transient axis (**BREAKING**):
the transient view pop-ups moved to `:PKMBrowse views`, the persistent sidebar
has a single door `:PKMPanel sidebar`, and `:PKMView` is view-data-only.*

### Changed — BREAKING: command surface reorganized

-   **Transient view pop-ups → `:PKMBrowse views [name]`.** What was `:PKMView
    list` (the view-tree picker), a bare `:PKMView <name>` (open a view's notes),
    and `:PKMView last` (reopen the last) are now `:PKMBrowse views`,
    `:PKMBrowse views <name>`, and `:PKMBrowse views last` — alongside the other
    transient pickers (`recent`/`orphans`/`tags`). Tab-completes view names + `last`.
-   **The persistent view sidebar has ONE door: `:PKMPanel sidebar [view]`.** The
    duplicate `:PKMView sidebar` is removed (it was a byte-for-byte alias — the
    `<leader>ps` keymap even routed through it while claiming to be a `p`-panel key).
-   **`:PKMView` is now view *data* operations only:** `new`, `update`, `edit`,
    `delete`, `rename`, `export`, `add`, `remove`. It no longer *displays* views.
    A bare `:PKMView <name>` (the old "open") now prints a one-line pointer to
    `:PKMBrowse views` / `:PKMPanel sidebar` instead of opening anything.

### Config changes

-   **Default keymaps re-pointed (same keys):** `<leader>ps` → `:PKMPanel sidebar`
    (was `:PKMView sidebar`), `<leader>va` → `:PKMBrowse views` (was `:PKMView
    list`), `<leader>vl` → `:PKMBrowse views last` (was `:PKMView last`). Config
    keys unchanged; the daily keymap path is unchanged in feel.

### Notes

-   Finishes the persistent-vs-transient split the v1.60.0 keymaps started (and
    PRINCIPLES mandates): transient pickers on `:PKMBrowse`, persistent panels on
    `:PKMPanel`, view *definitions* on `:PKMView`. A view is still reachable three
    ways — by *mode*, not by owner: transient (`:PKMBrowse views`), pop-up
    (`pkm.popup`), persistent (`:PKMPanel sidebar`) — the same pattern notes have.
    `test_v1630_p1` (the sidebar dedup, the removed verbs, retained management,
    completion); full suite green (93/93); luacheck + helptags clean. Docs swept
    (`doc/pkm.txt`, ROADMAP, ARCHITECTURE, LLM_CONTEXT). Interactive pickers
    (Telescope) are a smoke confirmation.

## [1.62.0] - 5/8/2026

*The browse picker gained a `<C-t>` note-type filter — the non-sidebar way to
reach journal / scratchpad notes — and its stray `<C-l>` error is silenced.*

### Added

-   **`<C-t>` note-type cycle in the browse picker.** `:PKMBrowse` / `<leader>ff`,
    the view note lists, and the pop-up's browse (every surface backed by
    `telescope.live_picker`) now cycle a note-type filter on `<C-t>` — **all → note
    → agg → bib → journal → scratch** — applied on top of whatever is typed, so it
    reaches journal and scratchpad notes without the sidebar. It mirrors the
    sidebar's `<C-t>` and is **global** (over every note, not one view's contents);
    the active type shows as `[scratch]` in the prompt title. Cycling closes and
    reopens the picker with the next type, preserving the typed prompt. This also
    **replaces Telescope's default `<C-t>`** (open-in-tab) in these pickers.

### Fixed

-   **`<C-l>` no longer errors in the browse / view pickers.** Telescope's default
    `<C-l>` is `complete_tag`, which raised *"No tag pre-filtering set for this
    picker"* in the plain browse. It is now neutralised (a no-op) wherever there is
    no pop-up provider-cycle to run. Inside the `<leader>fp` pop-up, `<C-l>` still
    cycles browse → views → nav (a Telescope prompt captures insert-mode keys, so a
    global `<C-l>` mapping — e.g. window-switch — cannot fire there regardless).

### Notes

-   Mechanism: `telescope.live_picker` gained a `type_idx` parameter and applies a
    `passes_type` predicate in its finder (on top of the prompt filter); `<C-t>`
    reopens with the next index. Built into the picker, so it is available to every
    caller with no per-caller wiring. `test_v1614_p1` asserts the cycle and the
    per-type predicate (each type reachable exactly once, isolating that type). The
    `<C-t>`/`<C-l>` key behaviour is Telescope-interactive (smoke). Full suite green,
    luacheck clean. (Scratch/journal were always indexed and browsable via
    `:PKMBrowse type:scratch`; this is the discoverable, dedicated path.)

## [1.61.3] - 5/8/2026

*The persistent sidebar CONTAINER extracted out of `views.lua` onto its own
module (ROADMAP Area 3). Behavior-preserving refactor — no user-facing change.*

### Changed

-   **`lua/pkm/sidebar.lua` (new) owns the sidebar container host.** The container
    that was woven through `views.lua` — the `pkm.panel` instance, the per-tab
    state, the provider registry (`register/build/set/cycle/show`, statusline,
    keymap application), autoswitch (`win_is_markdown`, `autoswitch_desired`,
    `autoswitch_tick`, `set_autoswitch`), the `sidebar_on_open` decorations, and
    the open/close/refresh/query API — now lives in one module. Neither `views`
    nor `nav` is built in: each registers itself as a provider, so the dependency
    runs one way (provider → container).
-   **`views.lua` is now a provider that re-exports the container API.** It keeps
    the `views` content (build/keymaps/switch/search/help, the view-management
    panels, `open_sidebar`/`focus_sidebar` — the views-specific entry points) and
    registers the `views` provider with the container (like `nav` does). Every
    historical `views.<sidebar-fn>` call site — `commands/panel`, `keymaps`,
    `mode`, `api`, `trash`, and `nav` — keeps working unchanged through thin
    re-exports (`is_sidebar_open`, `set_sidebar_provider`, `autoswitch_tick`, …).
    A one-line `get_tab` delegator keeps the many in-provider call sites intact.

### Notes

-   Behavior-preserving: **no file outside `views.lua`/`sidebar.lua` changed**
    (nav.lua included). The full sidebar battery (`v1490`/`v1510`/`v1520`/`v1530`/
    `v1540`/`v160`) and the whole suite (90/90) stayed green; `test_v1613_p1` locks
    the extraction boundary (container API on `pkm.sidebar`, `views` re-export
    identities, the `views` provider registered and drivable via `open_sidebar`).
    luacheck clean on both files (one pre-existing long-line warning in views.lua).
    The interactive surface (autoswitch on real focus, Telescope resume, splits,
    per-surface keymaps) is a smoke confirmation. A `pkm.sidebar` split had been
    deferred repeatedly as a mechanical tidy; this is it.

## [1.61.2] - 5/8/2026

*Forced-save prompt removed at its source (ROADMAP Near 5.1) — a citation into a
note open in an unmodified buffer no longer causes a later `:w` to prompt.*

### Fixed

-   **The phantom forced-save prompt on citation.** When note A cites note B and B
    is open in an **unmodified** buffer, `manage_backlink` (`citations.lua`) writes
    B's `cited_by` backlink. It previously wrote the file with `writefile` and then
    synced the buffer's text with `nvim_buf_set_lines`, which left Neovim's stored
    on-disk timestamp for that buffer at load time. A later user `:w` on B then saw
    the plugin's write as an external change (W12) and forced a `w!` / `y`-`n`
    prompt with nothing actually in conflict. The unmodified-buffer branch now
    composes the updated content in-buffer (`undojoin`, preserving the user's
    cursor and undo) and writes it **through the buffer** (`silent keepjumps
    noautocmd write`), which re-stamps the timestamp and clears `modified` — so the
    later `:w` is clean. `noautocmd` keeps `BufWritePost` (re-index / re-cite) from
    firing on a change the user did not make; the index is invalidated explicitly.
    **Removed without risk** (the ROADMAP caveat): no genuine external-change prompt
    is auto-accepted — only the plugin's own bookkeeping artefact is eliminated.

### Notes

-   The **modified-buffer** branch is unchanged: it still applies the backlink
    in-buffer only and writes nothing to disk, so the user's unsaved edits are
    never touched and their next `:w` persists both. The two in-buffer branches now
    share one composition path. `test_v1612_p1` proves both branches (unmodified:
    synced to buffer + disk, left clean, `checktime` finds no phantom change, a
    later `:w` is clean; modified: in-buffer only, edit preserved, no disk write).
    Full suite green (90/90); luacheck adds no new warnings (the citations.lua
    whitespace warnings are pre-existing). The no-prompt outcome at a real `:w` is
    an interactive smoke confirmation.

## [1.61.1] - 5/8/2026

*Documentation review + roadmap reorganization — no code behaviour change.*

### Changed

-   **`doc/ROADMAP.md` reorganized to its own charter** (1607 → 787 lines). Per the
    document's stated purpose — "the forward plan and nothing else; completed work
    summarised in a line pointing at CHANGELOG" — the ~880 lines of per-version
    shipped narration, the resolved command-clearup essay, and the v1.12 phase
    detail were compacted into a single **Shipped so far (v1.5.7 → v1.61.0)**
    thematic summary. The forward plan is now organized around a **Forward plan by
    area** spine (the six priority-tagged areas, pending items foregrounded), with
    the Near/Distant/Potential/Nongoal specs preserved and a new **Design
    constraints carried forward** section retaining the hard-won decisions that
    still bind pending work (storytelling dropped, imperative core kept). Every
    pending item and forward spec was preserved verbatim in intent; only shipped
    narration was compacted.

### Fixed (docs)

-   **`body_lower` restored to the documented index entry shape** in
    `doc/LLM_CONTEXT.md` and `doc/ARCHITECTURE.md`. The field is live
    (`index.lua:191`, `body:lower()` cached so `filter.eval()` never re-lowercases
    the body per query) and documented in `index.lua`'s own header, but the two
    dedicated docs omitted it — the one genuine drift the documentation review
    found. Both now list it with the caching rationale.

### Notes

-   Docs-only batch (ARCHITECTURE.md, LLM_CONTEXT.md, ROADMAP.md — no code files).
    A conservative whole-tree code review (luacheck: 0 errors) found nothing
    warranting a change. Verified: `helptags doc` clean; every pending roadmap item
    confirmed present after the reorg.

## [1.61.0] - 3/8/2026

*Performance: the first sidebar / pop-up / browse open no longer pays the cold
index build synchronously. Benchmark-driven — the build is ~0.15 ms/note and
dominates the cold open, so a ~10k-note vault (or slower synced-drive I/O) is the
1–2s the author saw.*

### Added

-   **Background (chunked) index warm-up.** `index.start_background_build()` gathers
    the note list up front (cheap `uv.fs_scandir`) and reads files in idle slices
    (`vim.defer_fn`, 400/slice), so the index is warm when a panel is first opened
    instead of freezing for the cold scan. Kicked ~200 ms after `setup()`, gated by
    `pkm_mode.index.prebuild` (default on). If a panel opens mid-build the index
    completes the remainder **synchronously** (`ensure_built`), so callers never see a
    partial index; `rebuild()` cancels an in-flight warm-up.

### Notes

-   Benchmark attribution (`:lua require('pkm.bench').index_profile()`): the build
    already uses the fast primitives (`scandir` over `glob`, `io.open` over
    `readfile`); of what remains, file reads are ~49% (inherent — must read to parse)
    and per-file mtime ~39% (`fs_stat` is *slower*, so no swap). No free algorithmic
    win — the fix is *when* the cost is paid, not the build itself. `test_v161_p1`
    (synchronous completion mid-build), `test_v161_p2` (chunked self-completion);
    luacheck clean; existing index-backed suites green.

## [1.60.1] - 3/8/2026

*Documentation cleanup — no code behaviour change (one config comment only).*

### Changed

-   **`doc/ARCHITECTURE.md` refreshed** to current: the File-Structure tree gained
    the modules that post-dated it — `args.lua`, `api.lua`, `check.lua`, `nav.lua`,
    `popup.lua`, `skill.lua` — plus `PRINCIPLES.md` / `PKM_API.md` / `AGENT_PROTOCOL.md`
    in the doc list; new Module-Responsibilities entries for `api.lua`, `check.lua`,
    `args.lua`, `skill.lua`; `keymaps.lua` notes the v1.60 persistent-vs-transient
    axes and `panel.lua` its `cycle_focus`.
-   **`doc/PRINCIPLES.md` § The smoke note** — records the concrete note placement
    (test vault `00 - NotesTeste` `03-Consolidated/`, numbered after the last file,
    current frontmatter, added to the **Smoke Tests** view via `:PKMView add`).
-   **`doc/ROADMAP.md`** — reconciled the old "Fix now" wrapped-`N.` highlight item:
    highlighting is in the **pkm-syntax** repo now (so any fix belongs there), the
    produced case is mitigated by autowrap (v1.41), and the residual manual-hard-wrap
    case is inherently ambiguous — consistent with § Known Bugs showing none open.
-   **`lua/pkm/config.lua`** — neutralized the `add_tag`/`remove_tag` off-by-default
    comment (it suggested `<leader>c*`, which reads as the cite prefix for tag ops).

## [1.60.0] - 3/8/2026

*The queued UX evaluations: a mnemonic redesign of the default keymaps, and a
picker-panel for `:PKMView update`. Config keys are unchanged (the stable
contract) — only default lhs strings move — but anyone relying on the defaults
must relearn them, so this is **BREAKING for default keymaps.***

### Changed — BREAKING: default keymaps reorganized

The organizing line is **persistent vs transient**. CONTENT verbs say *what* you
do (`<leader>n` notes · `<leader>c` citations/links · `<leader>f` find ·
`<leader>v` views · `<leader>M` markdown) — a find/view action may flash a
transient picker. `<leader>p` is the **persistent panels** you toggle and live
with (sidebar, buffer bar). WINDOW keys stay the user's; `<C-Tab>`/`<C-S-Tab>`
cycle the persistent panes. `<leader>v` is now views-only (sidebar/buffers moved
to `<leader>p`), and the cyclable pop-up — being transient — lives under find as
`<leader>fp`, not with the panes.

| Action | Old | New |
|---|---|---|
| Insert citation | `<leader>nc` | `<leader>cc` |
| Goto citation | `<leader>ng` | `<leader>cg` |
| Link note | `<leader>nl` | `<leader>cl` |
| Backlinks | `<leader>nb` | `<leader>cb` |
| Browse | `<leader>nf` | `<leader>ff` |
| Browse tags | `<leader>nt` | `<leader>ft` |
| Sidebar | `<leader>vs` | `<leader>ps` |
| Buffer panel | `<leader>vb` | `<leader>pb` |
| Cyclable pop-up | `<leader>nS` | `<leader>fp` |
| Focus sidebar | `<leader>s` | `<leader>P` |
| Cycle panes | — | `<C-Tab>` / `<C-S-Tab>` |

Note lifecycle (`<leader>n*`), views last/list (`<leader>vl`/`va`), and markdown
(`<leader>M*`, `]h`/`[h`, `gf`) keep their keys. `:help pkm-keymaps` is the
reference; `:nmap <leader>` / which-key show the live binds (every bind carries a
`PKM: …` description). Config keys are the stable API — set any to `false` to
disable, or remap freely.

### Added

-   **`<C-Tab>` / `<C-S-Tab>` cycle focus among open panes** — `pkm.panel.cycle_focus`
    scans the tabpage for `pkm-*` panes plus a home editing window and moves focus
    around the ring; leaves the user's own `<C-hjkl>`/`<C-s>`/`<C-x>` window scheme
    untouched. New config keys: `cycle_panes`, `cycle_panes_back`, and `explorer`
    (a `<leader>p*` key for `:PKMPanel explorer`, off by default).
-   **`:PKMView update` (no argument) now opens a picker-panel**, not a flat
    `vim.ui.select`. It reuses the view-deletion panel's tree (shared
    `view_pick_build_lines`); `<CR>` opens the chosen view's edit UI. Reads better
    as the view count grows.

### Notes

-   Discoverability was intentionally **not** a new command — native `:help
    pkm-keymaps` + `:nmap`/which-key already cover it, and the command surface stays
    at ~15 (see the v1.13/1.14 clearup). luacheck clean; a headless check asserts
    the new defaults resolve collision-free, `keymaps.register()` binds them, and
    `cycle_focus`/`open_view_update_panel` are wired; `test_v160_p3` (view panels)
    and the popup/api/skill suites still pass.

## [1.59.0] - 3/8/2026

*Post-Area-3 consolidation, Workstream E — the documentation revision. `doc/pkm.txt`
(the `:help`) was stale since v1.14.0: its WORKFLOW and COMMANDS sections named the
~46 command aliases deleted then. Rewritten by-context to the current ~15-command
verb surface, with new sections for the pieces added since. Docs only — no code.*

### Changed

-   **`doc/pkm.txt` — §5 WORKFLOW and §6 COMMANDS rewritten by-context** to the verb
    surface: `:PKMNote`, `:PKMCite`, `:PKMBrowse`, `:PKMTag`/`:PKMTags`, `:PKMView`,
    `:PKMPanel`, `:PKMHeader`, `:PKMList`, `:PKMTrash`, `:PKMVault`, `:PKMExport`.
    New reference blocks: **Vaults**, **Utilities** (`:PKMCheck`, `:PKMStats`,
    `:PKMToggleAutoSync`, `:PKMSyntax`), and **For assistants — pkm.api**
    (`:PKMAgentProtocol` + PKM_API / AGENT_PROTOCOL / CONVENTIONS). Real `*:PKMNote*`-
    style help tags added for each context; `helptags` generates clean.
-   **`doc/pkm.txt` sweep** — the sidebar intro, §7 PKM Mode, §8 Trash, §9 Citations,
    §10 Export, the §11 Configuration comments, the §12 Keymaps table and §13
    Frontmatter now name the current commands. No stale command token remains.
-   **`doc/ROADMAP.md`** — the Current-State "Working features" list updated to the
    current surface; the Documentation-debt tracker marked cleared. Historical
    narration (the command-clearup plan, old benchmarks) keeps its period names.
-   **`doc/LLM_PROJECT_INSTRUCTIONS.md`** — "What This Project Is" now states the
    pkm-suite / pkm-syntax sibling structure ("edit highlighting in pkm-syntax, not
    here") and the `pkm.api` / agent-protocol layer.

### Notes

-   Docs-only; the headless suite and luacheck are unaffected. Verified: no stale
    command tokens in `pkm.txt`, and `nvim --headless -c "helptags doc"` exits
    clean. **This clears the documentation debt tracked since v1.14.0 and closes
    the post-Area-3 consolidation batch (Workstreams A–E).**

## [1.58.0] - 3/8/2026

*Post-Area-3 consolidation, Workstream A — the repo moved into the **pkm-suite**
working-tree container as a sibling of `pkm-syntax`. Path references reconciled and
a thin suite-level `CLAUDE.md` added. Infrastructure/docs only — no plugin code
changed; the headless suite is unaffected because the sibling is resolved
relatively.*

### Changed

-   **Repo root is now `P:\Active\pkm-suite\pkm-nvim`** (WSL
    `/mnt/p/Active/pkm-suite/pkm-nvim`), a sibling of `pkm-syntax` under the
    `pkm-suite\` container. The GitHub repos stay **separate** under `Vitruvia/pkm-*`
    — the suite is a working-tree grouping, not a monorepo.
-   **`CLAUDE.md`** Fixed facts — repo-root path updated, plus a note on the sibling
    layout, the relative sibling resolution, and the separate-repos policy.
-   **`doc/LLM_CONTEXT.md`** — the `pkm-syntax` sibling path (now
    `P:/Active/pkm-suite/pkm-syntax`) and the Environment-table plugin path. The
    dated v1.43.0 narration (old `pkm-highlight` name) is left as history.

### Added

-   **`P:\Active\pkm-suite\CLAUDE.md`** — a thin suite-level guide holding *only* the
    cross-repo contract: the sibling layout, the separate `Vitruvia/pkm-*` GitHub
    repos, the `pkm-nvim → pkm-syntax` dependency + API-lockstep contract
    (pkm-syntax stays `Dependencies: none`), and the suite-wide Google-Drive /
    no-`git gc` rule. Each repo keeps its own authoritative `CLAUDE.md`.

### Notes

-   **No code changed.** `test/min_init.lua` resolves the sibling via
    `fnamemodify(repo_root, ':h') .. '/pkm-syntax'`, so the move needed no test edit;
    `test_v1160_skill` runs ALL PASS post-move. **Remaining consolidation item:
    Workstream E** — the `doc/pkm.txt` body + ROADMAP "Working features" list, stale
    since v1.14.0 (see ROADMAP § Documentation debt).

## [1.57.0] - 3/8/2026

*Post-Area-3 consolidation, Workstream B — reference-root permission and a few
light note conventions (protocol/docs), plus the skill bundle made
self-contained. No behavioural code beyond the skill copy list.*

### Added

-   **`AGENT_PROTOCOL.md` § 6.2 — Reference materials (`P:\Resources`).** States
    the rule plainly: **read is a standing grant** (the consult step of § 10),
    **write is per-task only** — the assistant asks for permission scoped to a
    task (e.g. Manager-mode renaming of mis-named reference files, or an
    author-requested reorganisation) and the grant ends with the task. Records
    the **deferred design** (per-agent organise rights vs. one general
    housekeeping tool the agents call) as pending, not a licence to broaden.
-   **`CONVENTIONS.md` § Note granularity.** A note is a **retrieval / working-
    memory unit, not an atom**; PKM does not adopt strict Zettelkasten
    one-idea-per-note atomicity. Soft split/merge heuristics (split when two
    subjects want *distinct* links; merge when neither stands alone), decided by
    reading the notes, not a size threshold.

### Changed

-   **`CONVENTIONS.md` § Bibliography Notes** — added **"never copy a whole text
    into a bib note"**: the source lives in the reference tree (`P:\Resources`),
    the bib note carries the citation plus excerpts / commentary / cross-links.
-   **`skills/pkm-notes/SKILL.md`** — the split/merge granularity heuristic
    (firmer, agent-facing; points to `CONVENTIONS.md § Note granularity`) and the
    Resources read-freely / write-on-request rule (§ 6.2).
-   **The skill bundle now ships `CONVENTIONS.md`.** `pkm.skill.install` copies it
    alongside `SKILL.md` / `AGENT_PROTOCOL.md` / `PKM_API.md`, so both of
    SKILL.md's references into CONVENTIONS.md (§ Lists, § Note granularity)
    resolve in the installed bundle. **Re-run `:PKMAgentProtocol install`** to
    pick up the new content.

### Notes

-   `test_v1160_skill` extended to assert `CONVENTIONS.md` lands in the bundle;
    passes. luacheck clean on `skill.lua`. Docs-and-protocol change — no headless
    behaviour to smoke beyond the install test. **Workstream C (extract vs. keep
    `markdown.lua`) is resolved as a decision, not code:** keep it in-tree now, a
    `pkm-markdown` extraction (mirroring `pkm-syntax`) is the scheduled follow-up
    that future markdown features ride — see ROADMAP.

## [1.56.0] - 3/8/2026

*Area 3, Phase 3.5b (slice 2) — the cyclable pop-up container. Completes Phase
3.5: the pop-up is now the sidebar's mirror.*

### Added

-   **`pkm.popup`** — one pop-up that hosts the three content providers
    (`browse` all notes, `views` view names, `nav` headings) and **cycles between
    them with `<C-l>`** (Telescope only; the `vim.ui.select` fallback simply
    doesn't bind the key). `popup.open(provider)` opens on a provider; `<C-l>`
    re-opens on the next in `browse → views → nav` order.
-   **Standalone semantics + the origin rule, completed.** Selecting in the
    cyclable pop-up does the provider-native action and **never drives the
    sidebar**: `browse` opens the note, `views` **activates** the view
    (`M.open` → new `views.popup_search`), `nav` jumps to the heading. This is the
    other half of the origin rule — the sidebar's own `/` (which *does* drive the
    sidebar) is a separate surface. `keymaps.nav_search` now opens this cyclable
    pop-up starting on nav (`<C-l>` → views → browse).

### Changed

-   `pkm.telescope.pick_list`, `.browse`, `.browse_paths` and the internal
    `live_picker` gained an optional `on_cycle`; when set, `<C-l>` closes the
    picker and calls it. Additive — `:PKMBrowse` and the sidebar's own `/` pass
    nothing and are unchanged. The `pkm.ui.pick_list` fallback accepts `opts` for
    signature parity and ignores them.

### Notes

-   `test_v1560_p1` covers the cycle order and that `popup.open('nav')` /
    `popup.open('views')` dispatch to the right pop-up (headings jump; view names
    offered, standalone). The `<C-l>` cycling itself is Telescope-only and rides
    the manual smoke. **This closes Phase 3.5 (3.5a `/` content-consistency →
    3.5b nav pop-up → cycle + standalone).** Suite 86/0; luacheck clean (the one
    views warning is a pre-existing long notify string).

## [1.55.0] - 3/8/2026

*Area 3, Phase 3.5b (slice 1) — the nav/headings pop-up ("open nav in the
pop-up").*

### Added

-   **`nav.search()` — a fuzzy pop-up of the focused note's headings** (Telescope
    when available, `vim.ui.select` fallback); choosing one jumps the source
    window there. It is the nav provider's `/` (content-consistent with the views
    `/`), and is also reachable standalone from a markdown window via the optional
    `keymaps.nav_search` (default `false`). Built on the v1.53.0 `pick_list`.

### Changed

-   **The nav provider's `/` is now the headings pop-up**, replacing the in-panel
    heading filter (and its `c` clear). The pop-up subsumes it — fuzzy-search a
    heading and jump — and matches how `/` behaves on the views provider. `<CR>`
    (jump to the heading under the cursor) and `r` (refresh) are unchanged.

### Notes

-   Still to come in 3.5b: the **in-pop-up cycle** across file-browse / views /
    nav, and **standalone pop-up entries** whose selection does not drive the
    sidebar. `test_v1550_p1` (headings offered level-indented, carry the source
    line, jump on select, empty-note guard). `test_v1510_p1` updated (nav's keys
    are now all shared with views, so the keymap-swap is proven via the views-only
    keys being torn down). Suite 85/0.

## [1.54.0] - 3/8/2026

*Two buffer-panel additions the author asked for after the v1.53 smoke.*

### Added

-   **`[count]<CR>` in the buffer panel** opens the buffer under the cursor in the
    Nth editing window (1 = leftmost, sorted left→right) — the same gesture the
    view sidebar has. A bare `<CR>` is unchanged (alternate / first non-panel
    window). A count past the last editing window notifies instead of doing
    nothing. Reuses the sidebar's `_sort_wins_by_col` / `_resolve_window_slot`.
-   **`/` in the buffer panel** opens a fuzzy pop-up over the open buffers
    (Telescope when available, `vim.ui.select` fallback) — for when there are too
    many buffers to scan the panel — and choosing one opens it in an editing
    window. Built on the `pick_list` primitive from v1.53.0.

### Notes

-   New `ui.lua` helpers `collect_listed_bufs`, `open_buffer`,
    `open_buffer_in_slot`, `bufpanel_search`; the panel hint line now reads
    `[N]<CR> open  / find  …`. `test_v1540_p1` drives both through the real keymaps
    (`vim.ui.select` stubbed for the search). Suite 84/0; luacheck clean.

## [1.53.1] - 3/8/2026

*Three fixes from the v1.53.0 smoke, two of them one root cause: the autoswitch
"manual choice sticks until context changes" seeding was too clever.*

### Fixed

-   **Autoswitch is now LIVE instead of transition-gated.** Reopening the sidebar
    while a markdown note stayed focused left it on views until you opened a
    *different* note; and cycling to views on a markdown note stopped autoswitch
    from ever coming back (while the non-markdown direction behaved differently —
    an asymmetry). Both were the seeding. Autoswitch now simply shows the provider
    the focused editing window asks for (`nav` for markdown, `views` otherwise);
    a manual `<C-n>` cycle is a **transient peek** that holds while you stay in the
    sidebar and reverts the moment you refocus an editing window. To pin the
    sidebar, `:PKMPanel autoswitch off`. `_autoswitch_last`/`seed_autoswitch_context`
    are gone.
-   **Opening the sidebar is now context-driven** (no-name open): from a focused
    markdown window it opens on nav directly, instead of opening views and only
    flipping on the next focus change — so a reopen shows the right content at once.
-   **The vault indicator no longer gets pushed off-screen in the nav header.** A
    long note name would shove it past the sidebar width; it is now appended only
    when the whole header fits (the author's "only if there's space").

### Notes

-   `test_v1520_p1` updated to the live model (a cycle reverts on refocus).
    `test_v190_p2` (which predates autoswitch and asserts the views keymaps) pins
    the sidebar with `set_autoswitch('off')` so a focused markdown buffer doesn't
    open nav under it. Suite 83/0.

## [1.53.0] - 3/8/2026

*Area 3, Phase 3.5a — content-consistent `/` from the sidebar (first slice of the
pop-up-as-provider-container work). Smoke note #2: `/` on the views sidebar opened
the all-notes file browser; it should search the content the sidebar is showing.*

### Added

-   **`/` in the views sidebar overview now searches VIEWS**, not all notes. It
    opens a picker of view names (Telescope when available, `vim.ui.select`
    fallback) and — because it was launched from the sidebar — choosing a view
    **switches this sidebar to that view** (the pop-up and sidebar are otherwise
    separate; a standalone views pop-up, planned for 3.5b, will not drive the
    sidebar). Detail-mode `/` is unchanged — it already searches the notes of the
    view being shown.
-   **`pkm.telescope.pick_list(title, items, on_select)`** and its
    `pkm.ui.pick_list` fallback — a content-agnostic fuzzy list-picker over
    `{ display, value }` items. The reusable pop-up primitive behind the views
    `/`, and the nav/headings picker to come in 3.5b.

### Notes

-   This is the first slice of **Phase 3.5** (the pop-up becomes a provider
    container mirroring the sidebar). Still to come (3.5b): a nav/headings picker
    (`/` on the nav provider, and "open nav in the pop-up"), an in-pop-up cycle
    across file-browse / views / nav, and standalone pop-up entries whose
    selection does NOT drive the sidebar (the other half of the origin rule). The
    intricate `open_views_panel` note-browser was deliberately left untouched.
-   `test_v1530_p1` covers `pick_list` and the overview-`/` round-trip (it offers
    view names, and choosing one switches the sidebar) via the real keymap with
    `vim.ui.select` stubbed. Suite 83/0; luacheck clean (the one views warning is
    a pre-existing long notify string). The Telescope rendering rides the smoke.

## [1.52.1] - 3/8/2026

*Follow-up to the v1.52.0 smoke: autoswitch flipped to nav on focusing a markdown
window and back to views once no markdown window remained — but focusing a
**non-markdown** file while a markdown window stayed open elsewhere did nothing.*

### Fixed

-   **Autoswitch now falls back to views whenever you focus a real non-markdown
    editing window**, not only when the last markdown window closes.
    `autoswitch_desired` returned `views` solely on `not tab_has_markdown()`; it
    now returns `nav` for a focused markdown window and `views` for any other real
    editing window (a non-markdown file, a scratch buffer), while still ignoring
    the sidebar, other PKM panels, netrw, and floats. `test_v1520_p1` gained the
    two-window case (non-md focus → views with a markdown window still open).
    Suite 82/0.

## [1.52.0] - 3/8/2026

*Area 3, Phase 3.3b — the sidebar autoswitches between its providers by focus.
Completes the container/content model: the sidebar shows `nav` when you focus a
markdown file and falls back to `views` when no window holds a markdown file. On
by default; `:PKMPanel autoswitch` pins it. Also fixes the nav header glyph the
author flagged (`▚` → `≡`).*

### Added

-   **Sidebar autoswitch.** With it on (default), the open sidebar follows focus:
    `nav` when the focused window holds a **markdown** file, `views` when no
    window holds one. It acts only on a **context transition** (nav-worthy ↔
    no-file), so a manual cycle (`<C-n>`) or an explicit `:PKMPanel nav|sidebar`
    **sticks until the context actually changes** — the way to pin the sidebar is
    to turn autoswitch off. Driven from nav's existing window tracker
    (`views.autoswitch_tick`). New `config.sidebar_autoswitch` (default `true`),
    `:PKMPanel autoswitch [on|off|toggle]`, and `views.set_autoswitch` /
    `autoswitch_enabled`.
-   **`<leader>s` (focus sidebar) is now context-driven on open**: from a markdown
    window it opens the sidebar on nav; otherwise on views (when autoswitch is on).

### Fixed

-   The nav header glyph rendered as an obscure quadrant block (`▚`, U+259A). It
    is now `≡` (U+2261), the outline glyph already used in the sidebar winbar —
    renders in any monospace font.

### Notes

-   `test_v1520_p1` covers the flip to nav on focusing a markdown window, the
    fallback to views when no markdown window remains, the manual-choice-sticks-
    until-context-change rule, the on/off toggle pinning the sidebar, and
    `focus_sidebar`'s context-driven open. The command audit (`test_v1130_p8`)
    gained the `autoswitch` verb; `test_v1500_p1`'s nav-header assertion tracks the
    new glyph. Suite 82/0; luacheck clean (the one views warning is a pre-existing
    long notify string). Autoswitch is scheduled off nav's tracker, so it never
    perturbs the synchronous headless assertions; the live feel rides the smoke.

## [1.51.0] - 3/8/2026

*Area 3, Phase 3.3a — the one sidebar becomes a container that hosts multiple
content **providers**, switched in place. This corrects a Phase 3.1 mistake:
`:PKMPanel nav` used to open nav in its **own** second left split. Navigation is
content, not a container — so nav is now a provider on the single sidebar, and
`:PKMPanel nav` switches the sidebar to it. (The default stays: at most one
sidebar, at most one bottom bar.) Autoswitch — the sidebar following focus to
nav on a markdown window and back to views — is the next step, 3.3b.*

### Changed

-   **The sidebar hosts pluggable content providers.** `views` is the built-in
    provider; `nav` registers itself via `views.register_sidebar_provider` from
    `nav.setup`. A provider is `{ name, label, statusline, build_lines,
    apply|keymaps, init?, on_enter? }`. The panel's `build_lines` dispatches to
    the active provider; the container's per-tab state carries `provider`.
-   **Switching provider swaps the buffer's keymaps in place** — the container
    tears down the previous provider's buffer-local maps (by lhs) and applies the
    new provider's, then re-dispatches `build_lines`. No close/reopen, so it never
    flickers (which is what lets 3.3b's focus-driven autoswitch be smooth). The
    common keys `q`/`<Esc>` (close) and the new **`<C-n>`** (cycle providers)
    survive every swap. `views`' full keymap set moved verbatim into a swappable
    `apply_views_keymaps`; nav's `<CR>`/`/`/`c`/`r` collide with views' by design
    and are simply the ones live while nav is showing.
-   **`nav.lua` is a provider, not a container.** It no longer creates its own
    `panel.create` instance; it exposes `sidebar_provider` (build + keymaps +
    statusline + cursor placement) and keeps its source-tracking autocmd, which
    now refreshes the sidebar only while it is actually showing nav.
-   New public surface on `views`: `show_sidebar_provider(name)` (open-on / switch
    / toggle-off), `cycle_sidebar_provider()`, `set_sidebar_provider(name)`,
    `sidebar_provider()`, `sidebar_provider_is(name)`, `register_sidebar_provider`.
    `:PKMPanel nav` → `show_sidebar_provider('nav')`; `:PKMPanel sidebar` still
    opens views. `<leader>s`, `get_last_view`, and the winbar are provider-aware.

### Notes

-   Container ownership still lives in `views.lua` for now; lifting it into a
    dedicated `pkm.sidebar` module is a later mechanical tidy that doesn't change
    behavior. Nav-in-a-popup remains a separate future surface.
-   `test_v1510_p1` proves the crux directly through the buffer's keymap table:
    views-only keys (`T`/`N`/`b`) are torn down under nav, nav's `c` appears,
    common `q` and shared `r` survive, the statusline swaps, and it all happens in
    the same window/buffer. `test_v1480_p1`'s integration was rewritten to the
    provider model (nav renders inside `pkm-sidebar`, cycle both ways, toggle
    off). The views regression gate (`test_v180_p6` marking keymaps, `test_v1200_p1`
    ui_state, `test_v190_p2` filetype) stayed green unchanged. Suite 81/0; luacheck
    clean (the one views warning is a pre-existing long notify string). The
    provider switch, cycle, and nav rendering ride the manual smoke.

## [1.50.0] - 3/8/2026

*Near-patch from four author notes against the freshly-extracted panels: a
sidebar focus toggle, the note number made visible in panel winbars, the vault
shown in the nav panel, and the removal of a v1.49.0 open-time regression.*

### Added

-   **`<leader>s` is now a focus toggle** (`views.focus_sidebar`). From any other
    window it records that window as the return target and jumps into the
    sidebar; from inside the sidebar it jumps back to that window; and it opens
    the sidebar (overview) if it was closed. The come-from window is stored on the
    panel's `prev_win`, so the sidebar's own actions — and, later, the nav
    provider — can target where you actually were. (Previously `<leader>s` only
    one-way-jumped into the sidebar and did nothing if it was closed.)
-   **Panel winbars show the note number.** Panels strip the leading number from
    their row labels; the winbar is now the one place it stays readable while
    browsing. A shared `utils.winbar_label(entry, path)` renders
    `title · filename` (filename keeps the number) for the row under the cursor.
    The **sidebar** winbar now uses it (so the number shows even in title-display
    mode); the **buffer panel** gains a winbar it did not have — shown only while
    the panel is focused and cleared on `WinLeave`, so the glanceable, unfocused
    panel keeps its full height (an empty winbar takes no row). Winbar is
    per-window, so this never touches the active editing window's own winbar.
-   **`<C-g>` in the sidebar and buffer panel** echoes the full path of the note
    under the cursor — number and directory included — as an unambiguous
    "where does this live" that never costs panel space. Advertised in the
    sidebar `?` help and the buffer panel hint line.
-   **The nav panel header now shows the current vault** (when a vault indicator
    is set), matching the sidebar overview and the buffer panel header.

### Fixed

-   **Opening the sidebar no longer builds the overview twice.** The v1.49.0 open
    path ran `panel.open()` (which builds) and then re-entered the mode switch
    (which builds again) only to place the cursor — doubling the O(views×notes)
    `count_many` pass on every open, felt as lag on a large views list. The cursor
    is now placed inline from the already-built state; `test_v1500_p1` asserts
    `count_many` runs exactly once on open. (The cold first-open cost that remains
    is the synchronous index build, unrelated — tracked separately.)

### Notes

-   `test_v1500_p1` (winbar_label pure cases, the single-build proof, the focus
    toggle round-trip, the nav vault header). Suite 80/0; luacheck clean (the one
    views warning is a pre-existing long notify string). The winbar rendering and
    the focus jumps ride the manual smoke.

## [1.49.0] - 3/8/2026

*Area 3, Phase 3.2 — the views sidebar was extracted onto the generic
`pkm.panel` container factory, behavior-preserving. The sidebar had its own
bespoke window lifecycle (raw `nvim_open_win`, per-tab `_tabs`, `winfixwidth`
management, statusline/winbar, quit-if-sole close) tangled together with the
views content. `panel.create` grew the few seams a managed-width side panel
needs, and the sidebar became a **provider** on it — the same container the
buffer panel, tag panel, and nav panel already ride. This is the substrate
Phase 3.3 needs to let one container cycle between the views and nav providers.*

### Changed

-   **`pkm.panel` generalized into a managed-width side-panel container.** New
    `spec.width` (number or thunk) fixes the panel's width at open, runs
    `wincmd =` so siblings re-equalise around it, and re-asserts the width across
    every open instance on `WinResized` (the discipline the sidebar used to own).
    New `spec.on_open(state, helpers)` is the per-panel decoration seam
    (statusline, winbar, extra buffer-local autocmds/keymaps) the factory
    deliberately does not unify. New `panel.refresh_all()` repopulates the panel
    in every tabpage from each tab's own state; new `panel.get_state()` returns
    the live per-tab state while open, nil while closed. All additive — the
    buffer/tag/nav panels are untouched.
-   **The views sidebar now rides `panel.create`** (`name = 'sidebar'`,
    `split_cmd = 'noautocmd topleft vsplit'`, `width` from `config.sidebar_width`,
    `focus_on_open`). Its content is a single `sidebar_build(state)` dispatcher
    (overview vs. detail); its full interactive surface — every keymap (`<CR>`
    with `[count]`, `<Tab>`/`<S-Tab>` marks, `<C-a>`, `N`/`<C-y>` chords, `<C-v>`,
    `<C-t>` type filter, `T`, `b`/`<BS>`/`<C-b>` history, `/`, `r`, `?`), the
    statusline and the winbar — moved verbatim into `spec.on_open`. Public API is
    unchanged: `open_sidebar`, `is_sidebar_open`, `get_sidebar_win`,
    `get_last_view`, `refresh_sidebar_if_open`, `set_panel_keymap`. The sidebar's
    old `TabClosed`/`WinResized` autocmds were removed from `views.setup` — the
    container owns them now.

### Notes

-   Two intentional micro-changes from the pre-panel sidebar, both toward
    consistency with the other panels: **`<Esc>` now closes the sidebar** (via the
    same quit-if-sole close as `q`; previously inert), and the panel's `WinClosed`
    safety net ensures a main editing window exists rather than letting the
    sidebar become the sole window. Everything else is behavior-preserving.
-   `test_v1490_p1` covers the new container API in isolation (width/on_open/
    refresh_all/get_state) and the sidebar on it (container props, history
    push/pop, type-filter cycle, close, no-arg toggle). The existing headless
    sidebar tests are the real regression gate and stayed green unchanged —
    `test_v180_p6` drives the marking keymaps for real; `test_v1200_p1` reads the
    sidebar through `api.ui_state`; `test_v190_p2` asserts the `pkm-sidebar`
    filetype. Suite 79/0; luacheck clean (the one views warning is a pre-existing
    long notify string). Interactive behaviors the headless suite cannot see
    (winbar/statusline rendering, `wincmd =` layout, focus, split placement) ride
    the manual smoke.

## [1.48.0] - 2/8/2026

*Area 3, Phase 3.1 — current-file navigation. The first new content provider on
the generic `pkm.panel` container factory (the same one the buffer and tag panels
use), proving the container/content direction with zero refactor risk (no
`views.lua` change). The heading index is the standout content type the author
asked for; here it ships as a standalone panel, ahead of the sidebar extraction.*

### Added

-   **`lua/pkm/nav.lua` + `:PKMPanel nav`** — a persistent side panel listing the
    ATX headings of the markdown buffer you are working in, indented by level,
    with a title header. `<CR>` jumps the source window to the heading; `/` filters
    by text (`c` clears, `r` refreshes, `q`/`<Esc>` close). The panel **follows the
    active note** as you switch buffers (a `WinEnter`/`BufWinEnter` source tracker
    registered by `nav.setup`, wired in `init.lua`). Optional `keymaps.nav_panel`
    (default `false`). Reuses `markdown.scan_headings` (fence- and
    frontmatter-aware), so `#` inside code or frontmatter is never listed.

### Notes

-   Built entirely on `panel.create` — one content provider among others; the
    container/content generalization and the sidebar extraction are later phases.
-   `test_v1480_p1` (heading index core + open/close integration); the command
    audit (`test_v1130_p8`) gained the `nav` verb. Suite 77/0, no new luacheck
    warnings.

## [1.47.1] - 2/8/2026

*Follow-up to the v1.47.0 author smoke: `highlight_all_markdown` highlighted only
markdown opened **after** setup, never buffers already open when setup ran. The
diagnostic was conclusive — facade resolved to the real backend, the `FileType`
autocmd was registered, yet tree-sitter was inactive on the current buffer while
`:PKMSyntax on` worked.*

### Fixed

-   **`highlight_all_markdown` now also enables already-open markdown buffers.**
    `FileType` does not re-fire for a buffer that was already loaded when the
    autocmd registered (a config reload/`:source`, or a file whose `FileType`
    fired before pkm-nvim finished loading), so it was never highlighted until
    re-edited. `mode.setup` now loops the loaded markdown buffers and enables them
    (highlight-only, skipping PKM notes) — mirroring `pkm-syntax.setup()`'s own
    existing-buffer loop. `test_v1471_p1`; suite 76/0.

## [1.47.0] - 2/8/2026

*Area 4 (syntax control). Two things: make the highlighter load-order-proof, and
give the user a manual on/off toggle. The `highlight_all_markdown` mechanism is
correct (verified headless: opening a non-PKM markdown buffer activates tree-sitter
+ the PKM matchadds), so the real-world non-firing is environmental — a facade that
cached a no-op stub, and pkm-syntax declared as a lazily-loaded plugin's dependency.*

### Added

-   **`:PKMSyntax [on|off|toggle]`** (bare = toggle) — manual highlighting control
    on the current buffer, independent of PKM mode and `highlight_all_markdown`. A
    vault note enables with the full note look (fold + window options); any other
    markdown gets the pure highlighting (`highlight_only`). Optional
    `keymaps.toggle_syntax` (default `false`) maps `:PKMSyntax toggle`.
-   **`pkm-syntax.is_active(bufnr)`** — new public API so a consumer can read the
    on/off state without tracking its own (used by the toggle). Cross-repo: added
    to the pkm-syntax contract in lockstep.

### Fixed

-   **`pkm.syntax` facade now resolves `pkm-syntax` lazily.** It ran
    `pcall(require,'pkm-syntax')` once at module load and cached a no-op stub on
    failure — so if the plugin manager had not yet put pkm-syntax on the runtimepath
    at that first call, highlighting was disabled for the whole session. It now
    retries per access and caches only success, degrading to a no-op (one warning)
    only while pkm-syntax is genuinely absent.

### Notes

-   Author config: `Vitruvia/pkm-syntax` moved to be a dependency of **pkm-nvim**
    (`lazy=false`, on the rtp at startup) instead of hanging off telescope (lazy).
-   `test_v1470_p1`; the command-surface audit (`test_v1130_p8`) gained the new
    context. Suite 75/0, no new luacheck warnings.

## [1.46.0] - 2/8/2026

*Closes the last Area-2 wrap open question (author delegated the call: "best
practices or defer"). Fenced-code content wrapped word-based, collapsing internal
runs of spaces — fine for prose, wrong for code, where indentation and column
alignment carry meaning.*

### Changed

-   **Fenced-code content now wraps whitespace-preserving.** `markdown.wrap_range`
    keeps each code line's leading indentation **and** internal whitespace; it
    breaks only at a space that fits `textwidth`, and an over-long token overflows
    rather than being split (matching the prose wrap). Continuation segments repeat
    the leading indent; code lines are still never joined, so the wrap stays
    idempotent. A code line that already fits is left byte-for-byte unchanged (bar
    trailing whitespace). New helper `wrap_code_line`; the fenced branch no longer
    routes through the space-collapsing `reflow`.

### Notes

-   Prose, list, and blockquote wrapping are unaffected (single-space text wraps
    identically). `test_v1460_p1.lua`; suite 74/0, no new luacheck warnings.
-   This resolves the deferred item flagged in v1.45.0 — Area 2 (wrapping) has no
    open questions left.

## [1.45.0] - 2/8/2026

*Area 2 (wrap) polish: blockquotes now reflow. Previously `wrap_range` skipped
`> ` lines entirely (left untouched, deferred). Author spec: a blockquote is
indented one `>` plus three spaces — a **4-column indent per nesting level** —
and the marker repeats on every wrapped line (Neovim's standard).*

### Added

-   **Blockquote reflow in `markdown.wrap_range`** (`:PKMList wrap` / `gq`). A
    quoted paragraph joins its lazy continuations and reflows to `textwidth`, at a
    normalised prefix of `>` + 3 spaces per level (`>   ` at depth 1, `>   >   ` at
    depth 2), with the prefix on every wrapped line. A bare `>` line is kept as a
    paragraph break; a **quoted list/marker line** (`> - item`, `> i. sub`) is
    re-prefixed but *not* folded into prose — reflowing structure inside a quote
    is deliberately out of scope for now. A non-quote line ends the quote.
    Idempotent.

### Notes

-   `wrap_structural` no longer treats `^%s*>` as untouchable; a dedicated branch
    in the `wrap_range` loop accumulates and flushes the quote block.
-   Deferred (author "best practices or defer"): the code-block **whitespace**
    question — fenced-code content still wraps word-based (internal space runs
    collapse). A whitespace-preserving hard break for real code remains open.
-   Suite green (73 files) incl. the new `test/test_v1450_p1.lua`; the stale
    "blockquotes left untouched" case in `test_v1410_p1.lua` was updated to assert
    the reflow. No new luacheck warnings.

## [1.44.0] - 2/8/2026

*Phase X completed: the markdown highlighting is now a **separate plugin**,
`pkm-syntax`, and pkm-nvim depends on it. Author decision: separate repos (not a
monorepo); renamed `pkm-highlight` → `pkm-syntax` for the broader scope (folding
and more to come).*

### Changed — ⚠️ new dependency

-   **`pkm-nvim` now requires the `pkm-syntax` plugin** (github.com/Vitruvia/pkm-syntax)
    for markdown highlighting. **Add it to your plugin manager as a dependency of
    pkm-nvim** (e.g. lazy.nvim `dependencies = { "Vitruvia/pkm-syntax" }`). Without it,
    highlighting is absent but pkm-nvim still loads — `pkm.syntax` degrades to a no-op
    stub with a one-time warning, so nothing else breaks.
-   `lua/pkm/syntax.lua` is now a **thin facade** that re-exports `require('pkm-syntax')`
    unchanged, so every caller — `enable`/`disable`/`refresh_fold`/`foldtext` and the
    `*_list_pattern` / `_find_*` exports — keeps working. The highlighting code and
    `queries/markdown/*.scm` **moved out** of this repo into pkm-syntax (kept in only
    one place so the `; extends` query is not applied twice).
-   `test/min_init.lua` prepends the sibling `../pkm-syntax` to the runtimepath, so the
    suite (and smoke sessions) load the plugin like a real install.

### Notes

-   pkm-syntax is a standalone plugin: it highlights **any** markdown via
    `require('pkm-syntax').setup()`, with no dependency on pkm-nvim. The
    `highlight_all_markdown` flag (v1.42.0) still works through the facade.
-   Whole suite green (74) through the facade; behaviour is unchanged (the code was
    moved verbatim). No new luacheck warnings.

## [1.43.0] - 2/8/2026

*Autowrap follow-ups from the smoke: fenced-code content now wraps, and `gq` routes
through the structure-aware wrap.*

### Changed

-   **Fenced-code content now wraps** (`markdown.wrap_range`). Previously the whole
    fenced block was skipped; now the ``` / ~~~ fences are left untouched (like
    headings) but the code lines inside wrap **per line** — each line on its own, at
    its own indent, never joined and with no marker detection. (Word-based, so runs
    of internal spaces collapse; suited to prose-in-code-blocks. Tell me if you want a
    whitespace-preserving hard break instead.)

### Added

-   **`markdown.formatexpr()` and `formatexpr` on PKM notes** — `gq`/`gw` and every
    motion (`gqq`, `gq3j`, `gqap`, visual `gq`) now route through the structure-aware
    wrap automatically, so the existing muscle memory just works — no new keymap, no
    extra keystrokes. Insert-mode auto-wrap (`fo` t/a) falls back to Neovim's internal
    formatter. Wired in `mode.lua` at the note-enable path (`enable_note_buffer`).

### Tests

-   `test_v1410_p1` updated: fenced-code content wraps while fences/headers/tables stay
    intact, and `gqq` reflows an item exactly like `:PKMList wrap`. Whole suite green
    (74). No new luacheck warnings.

## [1.42.0] - 2/8/2026

*Phase X of the legal-lists arc: prepare the highlighter for extraction as a
standalone plugin, and let it highlight all markdown behind a flag. Author decision:
in-repo preparation now; all-markdown behind a config flag, default off.*

### Added

-   **`syntax.enable(bufnr, highlight_only)`** — a pure-highlighting mode. With
    `highlight_only = true`, the buffer gets the tree-sitter highlighting, matchadd /
    extmark markers and YAML injection, but **not** the PKM-note behaviour
    (frontmatter fold, window options, the `zE` remap). This is the seam for
    highlighting arbitrary markdown and for pulling `syntax.lua` out as its own
    plugin — the highlighting path keeps `Dependencies: none` and never touches
    note-specific state. The existing full path (`enable(bufnr)`) is unchanged.
-   **`pkm_mode.syntax.highlight_all_markdown`** (default **false**) — when true, a
    `FileType markdown` autocmd (in `mode.lua`, which owns the vault-path check)
    pure-enables every markdown buffer that is *not* a PKM note; PKM notes stay on
    the full path. Off by default, so opening an unrelated README is untouched.

### Notes

-   The physical split into a separate published repo is a follow-up the author owns;
    this version makes the code ready for it (self-contained module + a pure entry
    point + the all-markdown activation).

### Tests

-   `test_v1420_p1` (highlight_only places markers but creates no fold; full enable
    creates the fold; the flag defaults off). Whole suite green (74). No new luacheck
    warnings. No required smoke — default behaviour is unchanged; the all-markdown
    path is opt-in (set the flag and open a non-note `.md` to see pure highlighting).

## [1.41.0] - 2/8/2026

*Structure-aware autowrap (Area 2). Author decision: **Option A** — continuation
lines at the level indent, never the prefix width.*

### Added

-   **`markdown.wrap_range(l1, l2)` / `wrap_at_cursor()` and `:PKMList wrap`** — a
    reflow to `textwidth` (or 80) that understands PKM/legal structure:
    -   a **list item**'s continuation lines are re-indented to **marker_indent + 4**
        (never the marker width); a short marker is padded to the 4-space tab stop
        (`1.`+2, `-`+3), a long marker (`xiii.`, `100.`) overflows only the first line
        while the continuation stays at marker_indent + 4 (**Option A** — no false
        level-alignment);
    -   a **plain paragraph** reflows at its own indent;
    -   **left untouched**: ATX headers, table rows, fenced code (```/~~~), frontmatter
        `---`, thematic breaks, and blockquotes (blockquote reflow deferred);
    -   all marker families are recognised (digit, bullet, and the five legal
        markers), the subalínea validated as canonical roman so `civil.` reflows as
        prose; the reflow is **idempotent**.
-   This **resolves the Area-2 wrapped-number issue at the source**: a continuation
    line is indented content, never a line that begins with `N. `, so there is
    nothing for the highlighter to false-positive on.

### Tests / smoke

-   `test_v1410_p1` (short/long-marker Option-A indent, plain paragraph, tight list,
    structural skips, the `civil.`/`iv.` validity split, idempotency). Whole suite
    green (73). **Signals a smoke** (feel of the wrap) — note 0282 (`00 - NotesTeste`).

## [1.40.0] - 2/8/2026

*The highlighting phase (Area 4) begins: the legal markers tree-sitter cannot see —
artigo, parágrafo, subalínea — now highlight, completing visual parity with the
renumber. Author decision: standalone forms + our own highlight (not the `- ` dash
workaround).*

### Added

-   **Artigo and parágrafo highlighting** (`Art. Nº`/`Art. N`, `§ Nº`/`§ N`) via
    matchadd through the `PKMListMarker` group — `syntax.artigo_list_pattern` /
    `syntax.paragrafo_list_pattern`, `\C`-led, `º` optional. Both require a digit
    after the prefix, so prose (`Art. is short for…`, `§ is a symbol`) never matches;
    no validity check is needed (the prefix + number is unambiguous).
-   **Subalínea highlighting** (`i.`, `ii.`, `xiii.`) via a validated **buffer scan +
    extmarks** (`find_subalinea_markers` / `refresh_subalinea_markers`), reusing the
    meta-comment mechanism — matchadd cannot apply the canonical-roman check, so words
    made of roman letters (`civil.`, `mil.`) are validated out. Rescanned on enable,
    save, and (debounced) text change; the namespace is cleared on `disable`. The
    roman validator is **self-contained in `syntax.lua`** (no `require('pkm.markdown')`)
    so the module keeps `Dependencies: none` for the planned extraction.

### Convention

-   Legal markers are **standalone** — `§ 1º`, `i.` — not `- § 1º`/`- i.`. The `- `
    dash was only ever a way to borrow the native bullet's highlight; with these
    markers highlighting on their own it is retired. A `- iii.` line remains a plain
    markdown bullet whose text starts with `iii.`, intentionally not a legal marker.

### Tests / smoke

-   `test_v1400_p1` (artigo/§ pattern match+reject; the subalínea scan finds
    `i./ii./iii./iv./xiii.` and rejects `civil./mil./a)`/inline; live extmark
    placement). Whole suite green (72). **Signals a smoke** — the five legal markers
    highlighting is interactive; smoke note 0280 (`00 - NotesTeste`) walks every level
    and the must-not-highlight negatives.

## [1.39.0] - 2/8/2026

*Parallel work (Area 5), the headline of the legal hierarchy: a **one-pass nested
legal renumber** that walks all five levels at once, plus the artigo and parágrafo
markers.*

### Added

-   **`markdown.renumber_legal(l1, l2)`** — renumbers a Brazilian legal-text block
    across the full hierarchy in a single pass: **artigo** `Art. Nº`/`Art. N` →
    **parágrafo** `§ Nº`/`§ N` → **inciso** `R -` → **alínea** `a)` → **subalínea**
    `r.`. Each line is classified by marker **type**; a counter is kept per level and
    every deeper level resets when a shallower one appears, so nesting is correct
    regardless of indentation (which is preserved, never reflowed). Non-legal lines
    (prose, headings, blanks) are preserved and do not count. The **ordinal rule**
    (LC 95/1998, art. 10, III) is applied to artigo and parágrafo: ordinal with the
    `º` indicator up to the ninth, cardinal from the tenth (`Art. 9º`, `Art. 10`).
    Subalíneas keep the canonical-roman validity check (`civil.` is skipped).
-   **`markdown.renumber_range(l1, l2)`** — routes a range: a genuine legal hierarchy
    (**≥2** distinct legal levels) → `renumber_legal`; a flat list (digit, emphasis,
    header, or a single legal level, which keeps its indentation-based nesting) →
    `renumber_sequence`. `:PKMList renumber` over a visual range now goes through it,
    so the right behaviour is chosen automatically — no new verb.

### Internal

-   The shared numbering helpers (`strip_bq`, `to_roman`, `to_alpha`, `from_roman`,
    `is_valid_roman`, new `legal_ordinal`) were hoisted to module level so
    `renumber_sequence` and `renumber_legal` share one copy; a duplicate `strip_bq`
    in `convert_list` was removed.

### Tests / smoke

-   `test_v1390_p1` (full nested block, the ordinal rule past the ninth, blockquotes,
    and the router's three cases: multi-level → nested, single legal level → flat,
    plain digit list → flat). Whole suite green (71). **Signals a smoke** — the format
    (`Art. 1º`, `§ 1º`, cardinal from 10, no forced trailing period) is a choice worth
    confirming; smoke note 0281 (`00 - NotesTeste`) has a scrambled block to renumber.

## [1.38.0] - 2/8/2026

*Parallel work (Area 5), the legal hierarchy continues: the **subalínea** family
(lowercase roman + '.'). Renumber only — highlighting deferred to the highlighting
phase (it needs a validity check the matchadd regex cannot do).*

### Added

-   **Subalínea renumbering** (`markdown.renumber_sequence`): a lowercase-roman + `.`
    list — `i.`, `ii.`, `iii.` … — is recognised and renumbered, with the same
    per-depth counters (nested subalíneas restart under each parent) and blockquote
    handling as the other families. The marker token is **validated as a canonical
    roman numeral** (it must round-trip through `to_roman`), so ordinary words made
    of roman letters — `civil.`, `mil.`, `mix.`, `did.` — are *not* mistaken for
    markers and are left untouched even mid-range. Backed by new `from_roman` /
    `is_valid_roman` helpers. `test_v1380_p1` (out-of-order renumber, counts past x,
    nesting, the `civil.` validity guard, and the alpha/subalínea disambiguation).

### Disambiguation

-   The subalínea family is tried **before** the alpha family, so `i.` reads as
    roman *i* (not the 9th letter). The alpha family keeps `.` for **non-roman**
    letters (`a.`, `g.`) and `)` for all letters. Consequence: a `.`-form list whose
    first item is a valid lowercase roman numeral (`i.`, `v.`, `x.` …) renumbers as
    roman; one starting at a non-roman letter (`a.`, `b.` …) renumbers as letters.
    Lists start at `a`/`i` in practice, so this matches intent.

### Deferred

-   **Subalínea highlighting** is not in this version. Highlighting lowercase-roman
    markers via matchadd would paint prose (`civil.`), and the regex cannot apply the
    roman-validity check the renumber path uses. It will land in the highlighting
    phase via a buffer scan + extmarks (the meta-comment mechanism), where the
    validity check runs in Lua.

## [1.37.0] - 2/8/2026

*Parallel work (Area 5), the first increment of the **Brazilian legal-text list
hierarchy**: the roman *inciso* family is retargeted to its canonical form. Author
decision (AskUserQuestion): legal `-` form only.*

### Changed

-   **Roman incisos now use the legal `-` separator (`I -`, `II -`), not `.`/`)`.**
    LC 95/1998 writes incisos as an uppercase roman numeral followed by ` - `; the
    v1.33.0 generic roman list (`I.`/`I)`) was a first approximation. The renumber
    family (`markdown.renumber_sequence`) and the highlight
    (`syntax.inciso_list_pattern`, renamed from `roman_list_pattern`) both now match
    `I - ` and no longer match `I.`/`I)`. The ` - ` separator (spaces required around
    the hyphen) keeps incisos distinct from the lowercase-roman *subalínea* (`i.`)
    coming next. Nesting, blockquote handling, and the `\C` case-sensitivity fix
    (v1.36.1) carry over. `to_roman` is unchanged.

### Migration

-   Notes written with the old `I.`/`I)` roman list form will no longer renumber or
    highlight as incisos; rewrite them as `I - ` (or use a plain digit list). This is
    the deliberate "legal `-` only" choice — the `.`/`)` roman form is dropped, not
    kept as an alias.

### Tests / smoke

-   `test_v1330_p1` (renumber) and `test_v1350_p1` (highlight) retargeted to the `-`
    form, asserting the dropped `.`/`)` form no longer matches; `test_v1340_p1`'s
    additive roman case updated. Smoke note 0280 (`00 - NotesTeste`) updated via
    `pkm.api` to the `I -` inciso form, with `I.`/`I)` moved to the "must not
    highlight" section. Whole suite green (69).

## [1.36.1] - 2/8/2026

*Fix for the list-marker highlighting shipped in v1.35.0 / v1.36.0.*

### Fixed

-   **Roman list-marker highlighting no longer paints lowercase words.** `matchadd`
    honours `'ignorecase'`, which the real config sets, so the `[IVXLCDM]`
    collection was folding case and matching lowercase roman letters — a line
    beginning `civil.` or `id.` was highlighted as an inciso. Both marker patterns
    now lead with `\C` (force case-sensitive): roman matches uppercase only, alpha
    lowercase only (`A)` is not painted as an alínea). Caught while building the
    v1.36.0 smoke fixture (the highlight prediction over the real note showed a
    lowercase `c)` matching the *roman* pattern). `test_v1350_p1` / `test_v1360_p1`
    now set `'ignorecase'` and assert the case-sensitivity (`civil.`, `id.`, `i.`
    reject for roman; `A)`, `C)` reject for alpha).

## [1.36.0] - 2/8/2026

*Parallel work (Area 4, syntax highlighting): lettered list markers now highlight,
completing the visual parity with the v1.34.0 alínea renumbering and the v1.35.0
roman marker highlighting.*

### Added

-   **Lettered list markers are highlighted** (`a)`, `b)`, `aa)` … — legal
    *alíneas*). Like roman markers, tree-sitter emits no list node for
    lowercase-letter markers (verified), so they are highlighted via a per-window
    `matchadd` through the existing `PKMListMarker` group. `syntax.alpha_list_pattern`
    (exposed for tests) matches a lettered marker at line start behind optional
    indentation and blockquote `>` prefixes. `test/test_v1360_p1.lua` asserts the
    pattern matches the intended markers and rejects near-misses.

### Known limitations (this feature)

-   **The `)` form only.** Unlike roman (which highlights both `.` and `)`), the
    lettered highlight covers only the paren form. The `.` form of a lowercase label
    collides with two-letter abbreviations that can begin a line (`vs.`, `cf.`,
    `ed.`, `pp.`), and an always-on highlight there would paint prose; the paren form
    is how alíneas are actually written and is clean at line start. (Renumbering
    still handles both `a.` and `a)` — this limit is only about which form is
    *highlighted*.)

## [1.35.0] - 2/8/2026

*Parallel work (Area 4, syntax highlighting): roman-numeral list markers now
highlight, closing the visual half of the v1.33.0 roman *inciso* renumbering.*

### Added

-   **Roman-numeral list markers are highlighted** (`I.`, `II.`, `VII)` … — legal
    *incisos*). A live tree-sitter probe confirmed the markdown grammar emits **no**
    `list_marker_*` node for uppercase-roman markers, so a `.scm` capture cannot
    reach them; they are highlighted via a per-window `matchadd` instead — the same
    mechanism as `PKMCitation`. A new `PKMListMarker` group links to `@markup.list`,
    so a roman marker reads exactly like the native list markers from
    `queries/markdown/highlights.scm`. The pattern (`syntax.roman_list_pattern`,
    exposed for tests) matches an uppercase-roman marker at line start, behind
    optional indentation and blockquote `>` prefixes, and limits the highlight to
    the marker itself. `test/test_v1350_p1.lua` asserts the pattern matches the
    intended markers and rejects near-misses (`I.e.`, arabic `1.`, lowercase `a)`,
    plain prose).

### Notes / non-changes

-   **The "resume a list after a break" case needed no code.** The same probe showed
    tree-sitter *already* emits a `list_marker_*` node for an arabic marker that
    resumes a list across a blank-line break, a lazy (no-blank-line) break, or an
    intervening heading — and for every marker in the real `ringforge-magia` note.
    The only shape it drops is a marker with number ≠ 1 that directly abuts a
    non-list paragraph (`paragraph\n2. x`), which is CommonMark-correct; forcing a
    highlight there would require matching *every* physical line beginning `N. `,
    reintroducing the Area-2 wrapped-number false positive. So no arabic `matchadd`
    was added — the residual gap is the structural-autowrap domain (Area 2), not the
    highlight layer.

### Known limitations (this feature)

-   `matchadd` has no block context, so a roman marker at the start of a
    hard-wrapped prose line would highlight (the roman analogue of the Area-2
    wrapped-number case). Uppercase roman at line start in prose is rare; this is the
    same accepted heuristic the renumber detector uses.

## [1.34.0] - 2/8/2026

*Parallel work (Area 5, markdown editing): lettered ordered lists (Brazilian legal
*alíneas*), the next legal ordinal after the v1.33.0 roman *incisos*.*

### Added

-   **Lettered list family in `markdown.renumber_sequence`.** A lowercase-letter
    ordered list — `a)`, `b)`, `c)` … (legal *alíneas*) — is now recognised and
    renumbered, each position rendered as its letter label (bijective base-26:
    `a … z`, then `aa`, `ab` …), with the same per-depth counters as the other list
    families (nested alínea sub-lists restart under each parent) and the same `.`/`)`
    separators and blockquote handling. A `to_alpha` converter backs it. Additive: it
    is detected **last** — after the digit / emphasis / header / roman families — so
    nothing they match changes. `test/test_v1340_p1.lua` (out-of-order renumber, `.`
    separator, the past-`z` two-letter wrap, nesting, the additive guarantees for
    digit and roman lists, and a prose line left intact).

### Known limitations (this feature)

-   **The alpha family is bounded to one or two leading letters.** Detection and the
    renumber branch match `%l%l?` before the separator, so alínea labels (`a … z`,
    `aa …`) are recognised while an ordinary prose line (`word) text`) is not swept.
    A list whose labels run three letters deep (`aaa)`) is out of scope — alíneas
    never do.
-   **A lowercase list that *starts* at `i`/`v`/`x`/`l`/`c`/`d`/`m` is ambiguous**
    with lowercase roman and is not disambiguated. Alíneas start at `a`, the
    unambiguous case; uppercase roman (incisos) is a separate family, so there is no
    collision with it.
-   **One family per renumber pass.** `renumber_sequence` detects a single family from
    the first matching line, so a mixed roman-inciso + alpha-alínea block renumbers
    only the detected level in one pass; a true legal hierarchy is renumbered a level
    at a time (or a selection at a time). Full one-pass nested-hierarchy renumbering
    is a later step.

## [1.33.0] - 1/8/2026

*Parallel work (Area 5, markdown editing): roman-numeral ordered lists, the first
step toward Brazilian legal-text list support (incisos).*

### Added

-   **Roman-numeral list family in `markdown.renumber_sequence`.** An uppercase-roman
    ordered list — `I.`, `II.`, `III.` … (legal *incisos*) — is now recognised and
    renumbered, each position rendered in roman form, with the same per-depth counters
    as the other list families (so nested roman sub-lists restart under each parent)
    and the same `.`/`)` separators and blockquote handling. Additive: it is detected
    **after** the digit / emphasis / header families, so nothing they match changes;
    uppercase-only, so it never collides with a (future) lowercase-letter family. A
    `to_roman` converter (subtractive form, 1..3999) backs it. `test/test_v1330_p1.lua`
    (out-of-order renumber, `)` separator, counts past X, nesting, and the additive
    guarantees). *(Letters — alíneas a/b/c — and the full nested legal hierarchy are
    left for a later step; letters carry prose-vs-ordinal ambiguity that wants its own
    design.)*

## [1.32.0] - 1/8/2026

*Revision/evolution thread, step 5b (ROADMAP Area 1): the near-duplicate detector,
which pairs with the v1.31.0 merge write — detect, then fold together. This
substantially completes the revision thread.*

### Added

-   **`api.duplicates(opts?)`** — near-duplicate notes: pairs whose content is
    substantially the same, the candidates for `merge`. Where `unlinked_pairs` finds
    notes that are *related*, this finds notes that are nearly the *same*. Similarity
    is a weighted Jaccard blend of **body** words (0.5 — the truest signal: same body
    ⇒ duplicate), **title** terms (0.3), and **tags** (0.2, the `by-claude` marker
    ignored), over every pair of substantive `note`/`agg` notes (bodies from the
    index, no file reads). All pairs are compared, so a body copy under a different
    title is still caught — quadratic in the substantive-note count, a deliberate
    sweep. Each pair: `{ a, b, similarity, body_sim, title_sim, tag_sim }`,
    most-similar first, at/above `opts.threshold` (0.5); `opts.limit` (10). Advisory
    and read-only; single-vault. `test/test_v1320_p1.lua` (detection, non-duplicate
    exclusion, threshold, and the detect→`merge`→gone round-trip).

### Changed

-   **`skills/pkm-notes/SKILL.md`, `doc/PKM_API.md`** document `duplicates`. **Re-run
    `:PKMAgentProtocol install`** for the skill.

## [1.31.0] - 1/8/2026

*Revision/evolution thread, step 5a (ROADMAP Area 1): the note-merge lifecycle
write — the missing primitive to *act* on duplicate findings. The near-duplicate
detector (5b) builds on it next.*

### Added

-   **`api.merge(survivor_ref, absorbed_ref, opts?)`** (over `notes.merge_notes`) —
    fold the `absorbed` note into the `survivor`: append its body (under
    `opts.heading` if given), **redirect its citation graph** onto the survivor
    (every note that cited the absorbed note is re-pointed at the survivor; the
    survivor gains the absorbed note's outbound cites via the copied body), union its
    topical tags, then trash it through the deletion guard. Because trashing
    *preserves* backlinks for restore (`trash.trash_note`), the graph is redirected
    **before** the trash, so no dangling edge is left — and a copied token pointing
    back at the survivor is stripped, so a merge never yields a self-citation. **Both
    notes must be assistant-authored** (the survivor's body is rewritten and the
    absorbed note deleted). Returns `{ ok, survivor, redirected, absorbed_title }`.
    Reuses `write_body` + `citations.cite`/`uncite` + `agent_delete`; no core
    reimplemented. `test/test_v1310_p1.lua` (inbound redirect, outbound carried,
    no-dangling, self-citation stripped, tag union, and the guards).

### Changed

-   **`skills/pkm-notes/SKILL.md`, `doc/PKM_API.md`** document `merge` (flagged
    destructive). **Re-run `:PKMAgentProtocol install`** for the skill.

## [1.30.0] - 1/8/2026

*Revision/evolution thread, step 4 (ROADMAP Area 1): the stale/provenance review
queue. Surfaces notes to re-check against § 10 (a vault is provisional knowledge).*

### Added

-   **`api.stale(opts?)`** — substantive `note`/`agg` notes that likely need
    re-checking, ranked. The strong, actionable signal is a **provenance gap**: a
    note with a real body but **no references** — neither a bib citation nor a
    `## References`/`## Sources` section — cannot be weighed (weight 3), as cannot one
    with **no date** (weight 1). **Age** is a weak secondary signal: it only ranks
    among flagged notes (+1/yr, capped) and never flags on its own, unless
    `opts.min_age_days` is set (then every substantive note older than that is
    included — the plain review-queue use). Each result: `{ path, title, note_type,
    score, reasons = { no_references?, no_date?, age_days? } }`. Advisory and
    heuristic — it says "look again", never "this is wrong"; the judgement is the
    assistant's, cross-checking against current knowledge and sources. Bib notes
    (sources) and journals/scratch (logs) are out of scope. `opts.limit` (20),
    `opts.min_score` (1). Reads each candidate's frontmatter for dates and bib
    citations; body comes from the index. `test/test_v1300_p1.lua`.

### Changed

-   **`skills/pkm-notes/SKILL.md`, `doc/PKM_API.md`** document `stale`. **Re-run
    `:PKMAgentProtocol install`** for the skill.

## [1.29.0] - 1/8/2026

*Revision/evolution thread, step 3 (ROADMAP Area 1): the vault-wide sweep. Where
`related_unlinked` answers "what should this note link to", `unlinked_pairs` answers
"where across the whole vault are links missing".*

### Added

-   **`api.unlinked_pairs(opts?)`** — every **pair** of notes that is related (shared
    tags, title terms, or co-citations) but has no citation edge between them, ranked
    — the review-the-whole-vault-for-missing-links pass. Same signals, weights, and
    exclusions as `related_unlinked` (shared tag 2, title term 1, co-citation 2;
    `by-claude`/near-ubiquitous tags and already-linked pairs excluded), computed
    over all pairs through inverted buckets. To stay bounded, a signal bucket (a tag,
    a term, a shared source) with more than `opts.bucket_cap` (30) members is skipped
    as too common to implicate any specific pair. Each pair: `{ a, b, score, shared =
    { tags, terms, co_citations } }`. `opts.limit` (20), `opts.min_score` (3),
    `opts.graph` (true). Cost: one read of every note's edges, then a co-occurrence
    accumulation — a deliberate sweep, not a hot path. `test/test_v1290_p1.lua`.

### Changed

-   **`skills/pkm-notes/SKILL.md`, `doc/PKM_API.md`** document `unlinked_pairs`
    alongside `related_unlinked`. **Re-run `:PKMAgentProtocol install`** for the skill.

## [1.28.0] - 1/8/2026

*Revision/evolution thread, step 2 (ROADMAP Area 1): the graph signal for
relatedness. `related_unlinked` now uses the citation graph, not just tags/titles.*

### Added

-   **Co-citation in `api.related_unlinked`.** A third relatedness signal beyond
    shared tags and title terms: a **co-citation** (weight 2 each) is a source both
    the focus and the candidate cite (or are cited by), so two notes that lean on the
    same references surface as related even with no shared tag — the graph-native
    case the content signals miss. Each candidate now carries `co_citations`. It
    reads each candidate's edges, so it is behind **`opts.graph`** (default `true`);
    pass `graph = false` for the previous cheap index-only pass (tags/titles plus one
    read of the focus note's edges). `test/test_v1280_p1.lua` (notes related *only*
    by a shared source, ranked by how many they share, absent under `graph = false`).

### Changed

-   **`doc/PKM_API.md`** documents the co-citation signal and `opts.graph`. The skill
    text is unchanged (it already points at `related_unlinked` for linking relations).

## [1.27.0] - 1/8/2026

*Revision/evolution thread, step 1 (ROADMAP Area 1): the first tool that surfaces
what to revise, not just what to retrieve. Operationalises the "revise and rearrange"
half of § 11.6 — a vault is a graph, not a pile.*

### Added

-   **`api.related_unlinked(ref, opts?)`** — for a focus note, the notes **related to
    it but not linked to it**: those sharing its tags or title terms yet with no
    citation edge in either direction. Returns `{ ok, note, candidates }`, each
    candidate `{ path, title, note_type, score, shared_tags, shared_terms }`, ranked
    (shared tag = 2, shared title term = 1). The assistant reviews and `cite`s the
    ones that belong together — the exact gap the formal eval flagged (the user's
    magic notes were related yet ungraphed). **Non-topical tags are excluded** so
    they cannot make everything look related: the `by-claude` authorship tag (on
    every assistant note) always, and any tag on more than 80% of the vault. Already-
    linked notes are excluded (that is the point). `opts.limit` (10), `opts.min_score`
    (2). Advisory and read-only; single-vault; cheap (index tags/titles plus one read
    of the focus note's own edges). `test/test_v1270_p1.lua`.

### Changed

-   **`skills/pkm-notes/SKILL.md`** names `related_unlinked` as the tool for "link
    newly-seen relationships" (§ 11.6). `doc/PKM_API.md` documents it under a new
    Revision section. **Re-run `:PKMAgentProtocol install`** to redistribute the skill.

## [1.26.2] - 1/8/2026

*Two more keymap-help follow-ups after the v1.26.1 smoke (author-reported).
Interactive surface — rests on a real-config smoke.*

### Fixed

-   **A help float left open by switching away can no longer be orphaned.** The help
    window is a float — off the buffer bar and skipped by window motions — so leaving
    it without pressing `q`/`Esc`/`?` (a window switch, a click elsewhere) previously
    stranded it open until restart. It now closes on `WinLeave`. The dismiss keys run
    the return hook (Telescope resume); a bare leave only cleans up, so switching away
    never resumes a picker behind the user.
-   **The two-chord `<C-y><C-v>` / `<C-y><C-x>` help row now aligns with the rest.** Its
    wide key column pushed the description far right; it is now an aligned continuation
    line under the `new note` entry — `the same, split right (<C-y><C-v>) / left
    (<C-y><C-x>)` — at the shared description column, across all five help panels.

## [1.26.1] - 1/8/2026

*Two keymap-help panel fixes (author-reported). Interactive-surface change: the
headless suite cannot exercise the Telescope pickers, so this rests on a real-config
smoke.*

### Fixed

-   **Closing a Telescope picker's `?` help now returns to the picker, not the bare
    editor.** Opening the help float stole focus, which makes Telescope drop its
    picker, so dismissing help left the reader in the editor and forced a reopen. The
    three Telescope `?` handlers (a view's note list, browse-all-notes, the views
    tree) now route through a `telescope_help` helper that closes the picker cleanly,
    shows the float, and **resumes** the picker (prompt and selection intact) when
    help closes. The split-panel and sidebar help never had this problem — their
    window stays open, so focus returns on its own — and are unchanged in behaviour.
-   **Help lines no longer overflow into a horizontal scroll.** `show_keymap_help`
    hard-capped the float at 60 columns; longer rows (notably the sidebar help) ran
    off the edge. The width now fits the longest line up to the editor width, and
    measures display width (`strdisplaywidth`) so accented text is sized correctly.

## [1.26.0] - 1/8/2026

*Retrieval thread, step 4 (ROADMAP Area 1): the RAG assembly. The retrieve-before-
working surface (§ 11.6) reaches one call — give it a subject, get back the relevant
notes and everything linked to them, ready to read.*

### Added

-   **`api.context(term, opts?)`** — the one-call RAG assembly. It composes the two
    retrieval reads: `find`s the top `opts.seeds` (default 3, relevance-ranked in
    the active vault), expands each by its citation `neighborhood`
    (`opts.cites_depth` / `cited_by_depth`, default 1 each), then merges,
    de-duplicates, and annotates the result — every note carries `relation`
    (`'seed'` for a search hit, `'linked'` for a graph pull-in), seeds first by
    score, then linked by title. Returns `{ ok, query, seeds, notes }`. A note
    reached both ways stays a `seed` (no duplicate row). Purely a composition of
    `find` + `neighborhood`; single-vault. `test/test_v1260_p1.lua`.

### Changed

-   **`skills/pkm-notes/SKILL.md`** names `context` as the one-call
    retrieve-before-working option (§ 11.6). `doc/PKM_API.md` documents it. **Re-run
    `:PKMAgentProtocol install`** to redistribute the skill.

## [1.25.0] - 1/8/2026

*Retrieval thread, step 3 (ROADMAP Area 1): the RAG/OKF navigation reads. The
protocol's "retrieve before working" (§ 11.6) becomes two calls — read a note in
full, and read the cluster of notes linked to it — over the citation graph the
assistant builds.*

### Added

-   **`api.read(ref)`** — one note in full, the retrieval *atom*. Unlike `get` (an
    index entry) it returns the note's **body** plus its **resolved** citation
    edges: `cites` and `cited_by`, each `{ ref, title, path, note_type }` that can
    be handed straight to another `read`. Accepts a path or a citation reference;
    single-vault. Falls back to parsing the file directly for a readable note the
    active index does not hold.
-   **`api.neighborhood(ref, opts?)`** — the citation-connected **neighbourhood** of
    a note, the navigation aid for "retrieve everything linked before working". It
    walks the graph to `opts.cites_depth` / `opts.cited_by_depth` (default 1 each —
    what the note cites and what cites it, one hop) and returns the reachable notes
    as readable `{ path, title, note_type }` entries, seed returned separately and
    excluded. Built on `export.collect_deep`; single-vault. `test/test_v1250_p1.lua`
    (a `Referrer → Hub → { two sources }` graph: resolved edges, ref-not-just-path,
    seed exclusion, depth honoured, guards).

### Changed

-   **`skills/pkm-notes/SKILL.md`** now names `read` + `neighborhood` as the
    retrieve-before-working mechanisms (§ 11.6). `doc/PKM_API.md` documents both.
    **Re-run `:PKMAgentProtocol install`** to redistribute the skill.

## [1.24.0] - 1/8/2026

*Retrieval thread, step 2 (ROADMAP Area 1): relevance ranking. `find`/`find_all`
now surface the closest match first, not whatever order the index iterated.*

### Added

-   **Relevance ranking in `api.find` and `api.find_all`.** Each matched note now
    carries a `score` and the `notes` list is ordered best-first. Clear tiers,
    strongest first: an exact title (100), a title prefix (70), a word-boundary hit
    mid-title (50), a substring mid-word (35), then a filename prefix (25) /
    substring (15); an earlier position adds a small within-tier bonus, and a
    matching tag boosts (exact +15, partial +5) — a tag only *lifts* a note already
    matched by title/filename, never makes one a match on its own. Recency (mtime)
    breaks ties. `tags` now lead with the exact match, then prefix, then
    alphabetical. Shared `score_note` / `ranked_notes` / `ranked_tags` helpers back
    both functions. `test/test_v1240_p1.lua`. (`query` is a boolean filter DSL, so
    it is deliberately not ranked.)

### Fixed

-   **`api.find_all` returned no vaults when none were registered** (or when the
    active root was itself unregistered). The active-root fallback read
    `require('pkm.config').root_path`, which is always `nil` — the resolved config
    lives at `require('pkm').config`. Registered-vault sweeps were unaffected (they
    never reached the fallback), so v1.23.0's registry case was correct; this fixes
    the root_path-only and unregistered-active cases. Caught by the ranking test's
    no-registry `find_all` assertion.

## [1.23.0] - 1/8/2026

*Retrieval thread, step 1 (ROADMAP Area 1): cross-vault search. Closes the gap the
formal eval confirmed — `find`/`query` read only the active vault, so "which of my
vaults holds X" forced a filesystem grep.*

### Added

-   **`api.find_all(term)`** — the cross-vault twin of `find`. It sweeps every
    registered vault (and the active root, even if unregistered) and groups the
    matches per vault: `{ ok, term, vaults = { { vault, number, root, active,
    notes, tags } } }`. Case- and accent-insensitive over note titles, filenames,
    and tags (views are per-vault; `find` covers the active vault's). Only vaults
    with a match appear. `test/test_v1230_p1.lua` (the decisive case: a term unique
    to the *non-active* vault, which `find` misses and `find_all` catches; plus the
    shared-term grouping and the guards).
-   **`index.scan_root(root, folders?)`** — reads an arbitrary vault root's note
    entries **without** building or touching the active singleton index, reusing
    the same per-file reader as the index build. This is the non-disruptive seam
    `find_all` relies on: searching another vault switches neither the active root
    nor the live index.

### Changed

-   **`skills/pkm-notes/SKILL.md`** now sends the agent to `api.find_all` for
    cross-vault discovery instead of a filesystem grep (grep stays a documented
    deeper fallback for body text). `doc/PKM_API.md` documents `find_all`. **Re-run
    `:PKMAgentProtocol install`** to redistribute the skill.

## [1.22.0] - 1/8/2026

*Bib & sources — the first code thread of the post-eval plan (ROADMAP Area 1).
Closes the reference-recording gap the dogfood and the formal eval both flagged:
a source is now a citable **bib note**, not a freetext `## References` line.*

### Added

-   **`api.cite_source(citing_ref, source, opts?)`** — record a source in one call.
    It finds the source's bib note (by `source.title`, exact then substring, among
    indexed `bib` notes in the active vault) or **creates** one with the standard
    citation at the top (`source.bibtex`, BibTeX preferred; optional `source.notes`
    below it; `by` defaults to `claude`), then cites it. The citation token is
    placed **under `opts.heading`** (default `References`, created if absent) or, with
    `opts.heading = false`, at the body's end — which fixes the dangling-token nit
    where `cite` appended after an appendix section. Idempotent (`cited = false` when
    the token is already present); single-vault, like every citation. Returns
    `{ ok, bib = { path, number, title, created }, cited, heading, token }`. Wraps
    `notes.write_new_note` + `citations` + `notes.write_section`/`write_body`; no
    core reimplemented. `test/test_v1220_p1.lua` (creation, placement, graph
    symmetry, idempotency, reuse-by-title, end-of-body fallback, guards).

### Changed

-   **The bib doctrine — `doc/AGENT_PROTOCOL.md` § 10.** A reference is recorded as a
    **bib note**, not a prose line: consult `P:\Resources` (WSL `/mnt/p/Resources`) and,
    where warranted, the web; find-or-create the source's bib note (standard citation
    at the top) via `cite_source`. A **precise bib note is the one encouraged
    exception to "don't write the user's vault"** — the citation must be exact, any
    added summary carries a `By Claude:` header, bib notes may be copied between
    vaults with the right markers, and a user-authored bib note is never altered
    without permission. § 7's "user's note" rule now names this exception.
-   **`doc/CONVENTIONS.md` § Bibliography Notes (new).** The bib note shape: standard
    citation (BibTeX preferred) at the top; optional, authorship-marked summaries
    after it; the copy-between-vaults and don't-alter-user-bib rules.
-   **`skills/pkm-notes/SKILL.md`, `doc/PKM_API.md`** updated for `cite_source` and
    the bib doctrine. **Re-run `:PKMAgentProtocol install`** to redistribute the skill.

## [1.21.0] - 1/8/2026

*Protocol evolution driven by the first formal evaluation (the "ringforge" task,
verified on disk): a memory-organization doctrine, and three behavioural
refinements. Docs only — no code change.*

### Changed

-   **`doc/AGENT_PROTOCOL.md` § 11 (new) — memory organization and the memory↔vault
    relationship.** Memory is the lean *index/pointer* layer (facts about the user,
    how to operate, project state, pointers); the vault is the *body* of studied
    knowledge. What earns a write scales **by seriousness tier** (serious/durable →
    vault with rigor + a memory pointer; light/for-fun → memory-only or a light
    note; explicit task overrides the tier; ephemeral → neither). Memory is
    organized **by life-area** (career · personal · worldbuilding/fun · meta) with
    related items linked, not duplicated. **Authority:** the vault is authoritative
    for studied knowledge, memory for facts-about-the-user and how-to-operate; the
    stale side is reconciled; both cross-checked per § 10. Building writes durable
    knowledge to the vault and leaves memory a pointer (never a copy); retrieval
    checks memory first, then opens the vault for depth.
-   **`doc/AGENT_PROTOCOL.md` § 5.3 directive 6 — ask only for genuine forks.** Do
    not put a question to the user that the protocol's own defaults already settle:
    a learning task defaults to the assistant's own vault, and "connect related
    notes" can only mean *within* that vault (cross-vault graphs being impossible).
    From the eval: the agent asked where to store a learning-task result when the
    default already answered it.
-   **`SKILL.md` — memory doctrine + finding + titles.** The "Memory and the vault"
    section now carries the tiered/by-area/authority rules; "Finding notes"
    blesses **filesystem search for cross-vault discovery** (`find`/`query` read
    only the active vault) and notes titles default to the filename (no forced
    prose title). **Re-run `:PKMAgentProtocol install`** to redistribute.

---

## [1.20.0] - 31/7/2026

*Two agent-facing additions: a UI-inspection surface that lets the assistant help
run the interactive smoke the headless unit suite can't see, and the epistemic
stance for reading and writing vault knowledge (author's note, 31/7).*

### Added

-   **`api.ui_state()`** — a plain, JSON-encodable snapshot of the interactive UI:
    the current buffer (with title/type resolved from the index), whether the
    views sidebar and the buffer panel are open, and the sidebar's rendered lines
    plus the view highlighted under the cursor. The *inspect* half of
    **agent-assisted smoke testing**: an assistant drives a headless Neovim's real
    mappings with `nvim_feedkeys`, then reads `ui_state()` to assert the
    interactive path behaved — the part `test/min_init.lua`'s unit suite cannot
    observe. Proven end-to-end (open the sidebar via `<leader>vs`, read the state
    back) in `test/test_v1200_p1.lua`. It complements the human smoke run, it does
    not replace it (prompts / `vim.ui.select` still block unless fed or stubbed).

### Changed

-   **`doc/AGENT_PROTOCOL.md` § 10 (new) — notes as provisional knowledge.** A
    vault is dynamic note-taking to *enhance learning*, not settled fact. Codifies:
    cross-check a retrieved note against current knowledge and authoritative
    sources before relying on it; read a user's note as situated, partial
    knowledge; record provenance (author, date, references — book/paper by edition
    and year, website by visit date) on every note written; and the three-level
    framing (core model / agent / agent-plus-external-tools) that makes `pkm.api`
    a transparent local tool whose contents are still compared *both* ways against
    training and sources. General directive 9 points at it. Manager mode gets
    explicit latitude to adapt its own note form to LLM-learning best practice.
-   **`doc/CONVENTIONS.md` § Assistant-Authored Notes** — a *Provenance and
    references* format: author + date, and references with edition/year or visit
    date, usually in a `## References` section.
-   **`SKILL.md`** — a "Notes are provisional" section (cross-check on read,
    provenance on write) and the smoke-assist technique. **Re-run
    `:PKMAgentProtocol install`** to redistribute.

---

## [1.19.0] - 31/7/2026

*The permission-gated write into a **user's** note: `pkm.api.annotate` adds a
marked comment to a note that is not the assistant's own — the last note-writing
mechanism the protocol described but the API did not yet carry.*

### Added

-   **`api.annotate(ref, content, opts)`** — add a **marked comment** to a note
    that is not the assistant's own. The `By <Author>: ` marker is baked in (not
    optional, unlike `set_body`/`append_body`), and the block lands at a
    boundary — the end of `opts.heading`'s section, or the note's end — never
    woven inline. It writes only the assistant's own block; the user's text is
    untouched. Backed by `notes.annotate`, which delegates to
    `write_section`/`write_body`, so the frontmatter is preserved, the citation
    graph reconciled, and the unsaved-buffer guard applies. Authorisation stays
    the caller's (protocol §§ 5.3, 7); the function supplies mechanism + marker,
    not permission. In `doc/PKM_API.md`, `doc/AGENT_PROTOCOL.md` § 7 (Writing into
    notes), and the skill — **re-run `:PKMAgentProtocol install`** to redistribute
    the updated `SKILL.md`. Driven by `test/test_v1190_p1.lua`.

---

## [1.18.0] - 31/7/2026

*The note-lifecycle **writes** reach `pkm.api`, so a gestor-mode agent can
restructure a vault through the surface — not just create and annotate notes.
Three headless seams in `notes.lua` are the pure twins of the interactive
promote/transpose, changetype, and rename commands; the interactive paths keep
their pickers and prompts untouched (the `write_new_note` ↔ `create_new_note`
precedent).*

### Added

-   **Note-lifecycle writes in `pkm.api`:**
    -   **`api.rename(ref, new_name)`** — rename a note, keeping a consolidated
        note's number/type prefix (only the human name changes, sanitised for
        you), propagating through every citation.
    -   **`api.changetype(ref, new_type)`** — change a consolidated note's type
        (`note`/`agg`/`bib`): renames the file to the new prefix and propagates.
    -   **`api.transpose(ref, target, opts)`** — move a note to another PKM type
        (`note`/`journal`/`scratchpad`). Covers **both** promote and transpose;
        the original is deleted unless `opts.keep_original`. For `target="note"`,
        `opts.subtype` and `opts.title` shape the consolidated result.
-   **The pure seams they wrap** (`lua/pkm/notes.lua`): `convert_file`,
    `changetype_file`, `rename_note_at` — each takes an explicit path, reads from
    a buffer holding the file when one exists (unsaved edits survive) and from
    disk otherwise, prompts for nothing, and opens no buffer.
-   **Adjacent gestor wraps:** **`api.set_membership(path, view, kind)`** and
    **`api.save_subproject(name, parent, filter)`** (over the already-headless
    view cores), and **`api.rename_tag(from, to)`** — a vault-wide tag rename that
    **merges** onto an existing destination, subsuming the roadmap's `tags.merge`.
-   Documented in `doc/PKM_API.md` (reference tables + Coverage) and driven
    end-to-end by `test/test_v1180_p1.lua` (34 assertions, all headless).

---

## [1.17.0] - 31/7/2026

*Placement-aware writing and a standing highlight-bug fix, on top of the v1.16.0
pkm.api stack.*

### Added

-   **`pkm.api.insert_section(path, heading, content, {mode})`** — placement-aware
    body writing: locate a section by its heading and `append` at its end
    (default) or `replace` its body, keeping the heading. The section stops at the
    next same-or-shallower heading, and headings inside code fences do not count
    (reuses the now-exported `markdown.scan_headings`). Backed by
    `notes.write_section`; frontmatter preserved, citation graph reconciled,
    unsaved-buffer guard. In `doc/PKM_API.md` and the skill.

### Fixed

-   **`PKMCitation` highlighting never fired** (standing bug, found 27/7/2026).
    The `matchadd` regex `\v<…\[[\w\-_]+\>` was doubly wrong — `\w` excludes
    digits in a Vim collection (dropping ids like `0042`) and `\>` under `\v` is a
    literal `>`. Now `\v<(note|bib|journal|scratch)\[[0-9A-Za-z_-]+\]`, extracted
    to `syntax.citation_pattern` and asserted in `test_v1170_p1.lua`.

### Changed

-   **`doc/AGENT_PROTOCOL.md` § 5.1** — intra-vault citation guidance: the
    assistant should build its own vault as a graph (cite between its own notes);
    only cross-vault links are forbidden.

---

## [1.16.0] - 31/7/2026

*The `pkm.api` layer and the agent-protocol stack — the programmatic surface an
LLM assistant drives the vault through, and the policy and skill that point it
there. Validated by a real evaluation: with the skill installed, Claude read the
vault, discovered a subject that is a **view** (via `find`), wrote a
schema-correct, authored note **with a body** into its own vault, and never
grepped a raw file or touched user content — the exact failure of the first,
protocol-less run (`[[pkm-eval-first-run]]`) reversed. This release also carries
the global next-header (`:PKMHeader sibling`) planned as v1.15.0, which shipped
here rather than under its own tag.*

### Added

-   **`lua/pkm/api.lua` — `require('pkm.api')`**, the programmatic surface:
    returns data, never opens UI, headless-safe, wrapping the existing cores. It
    covers `create` (with `by=` authorship and a `body`), `set_body`/`append_body`,
    `delete` (guarded — trashes only agent-authored notes), `cite`/`uncite`/
    `resolve`, `tag`/`tag_preview`/`tag_note`, `find` (subject search across
    views + tags + titles, accent-folded), `query`/`get`/`notes`, `views`/
    `view_members`, `audit`, `collect`/`export`, the vault reads, and the
    enumerable `actions()`. Every write reports what it changed and keeps the index
    in step; body writes reconcile the citation graph. Backed by
    `notes.write_new_note`/`write_body`, the headless write seams.
-   **`doc/AGENT_PROTOCOL.md`** — the policy: the two-mode model (User / Manager),
    "always through `pkm.api`", authorship demarcation, the hard no-cross-vault
    rule, long-term learning modes, and writing-into-notes governance.
-   **`doc/PKM_API.md`** — the API reference and the headless JSON invocation
    contract.
-   **The `pkm-notes` skill** (`skills/pkm-notes/`) and **`:PKMAgentProtocol
    install|update|path`** (`lua/pkm/skill.lua`, `commands/agent.lua`), which
    deploys the skill to `~/.claude/skills` and the **`/pkm-learning`** command to
    `~/.claude/commands`. The twelfth verb-context.
-   **`:PKMHeader sibling`** — the global next-header: from any sibling it inserts
    `<prefix>-<max+1>` at the end of the enclosing block (`markdown.append_global_header`).

### Changed

-   **`doc/PHILOSOPHY.md`** — §4/§5 amended: automated note-generation is in scope
    in the *assistant's own* vault (its memory), out of scope in the user's
    knowledge base. **`doc/CONVENTIONS.md`** — assistant-authored-note formats.
-   **Authorship** now stamps three ways on an agent-created note: the
    `By<Author>` filename marker (other vaults), the `author` frontmatter, and the
    queryable `by-claude` tag — on both the API and the `:PKMNote new by=` paths.

### Notes

-   Installing the skill is the user's act (`:PKMAgentProtocol install`); the
    plugin ships the skill and installer, not the deployment.
-   Cross-vault citations are inert by design and are **not** an operation to
    consider — the evaluation confirmed the agent respects this.

---

## [1.14.0] - 30/7/2026

*The command clearup, part 2: delete the aliases. `:PKM<TAB>` now lists **15**
commands — eleven verb-contexts (`:PKMNote`, `:PKMTag`, `:PKMCite`, `:PKMView`,
`:PKMVault`, `:PKMBrowse`, `:PKMPanel`, `:PKMHeader`, `:PKMList`, `:PKMTrash`,
`:PKMExport`) and four standalone (`:PKMCheck`, `:PKMStats`, `:PKMToggleAutoSync`,
`:PKMTags`) — instead of 64. Smoke route passed in the real config
(`00 - NotesTeste/03-Consolidated/0275_note_smoke-v1140-o-corte-dos-aliases.md`):
the shrunk `:PKM<TAB>`, the removed names erroring (E492), the `:PKMTag`/`:PKMTags`
split, keymaps on the verb forms, and the reserved-verb refusal.*

### Removed

-   **The 46 alias commands** the previous version kept (`:PKMNewNote`,
    `:PKMRenameNote`, `:PKMAddTag`, `:PKMUncite`, `:PKMViewNew`, `:PKMVaultNew`,
    …). Every operation is now `:PKM<Context> <verb>`. Callers were migrated to
    the verb forms first — keymaps, the two internal `vim.cmd('PKMViewNew')`
    calls, the whole test suite, and every user-facing message — so the surface
    shrank without a functional gap.

### Changed

-   **`:PKMTags` is now the vault-wide bulk tag command**, no longer an alias:
    singular `:PKMTag` acts on one note (current buffer, or `note=<ref>` on
    disk); plural `:PKMTags add|remove|rename <tag>` acts across **all** notes
    with the change-list confirm. Its browse half is `:PKMBrowse tags`.
-   **`vault.validate_name` reserves the `:PKMVault` verbs** (new/rename/renumber/
    unregister/adopt) as names, the way it already reserves `Unregistered`, so a
    vault can't be shadowed by a verb.
-   **README, and the source/messages throughout, point at the verb forms.** The
    command reference is rewritten context by context.

### Known limitations

-   The add/remove tag panel is still the built-in list, not a Telescope picker
    (carried from v1.13.0). And the stale `PKMViewNewSub` references in
    `views.lua` name a command that never existed — a separate cleanup.

---

## [1.13.0] - 30/7/2026

*The command clearup, part 1: introduce the verb-contexts, keep every old name
as an alias. Smoke route passed in the real config
(`00 - NotesTeste/03-Consolidated/0274_note_smoke-v1130-a-limpeza-de-comandos.md`),
including the `:PKM<TAB>` tree, the prompt/picker/panel forms reached through
verbs, and alias parity — the parts the headless suite structurally cannot see.
Part 2 (v1.14.0) deletes the aliases, which is where the `:PKM<TAB>` list finally
shrinks.*

*The first agent evaluation drove this: given a real task, Claude used zero PKM
commands and hand-rolled notes on the filesystem. A tidier surface does not fix
that by itself, but the clearup builds the one surface a human and an agent both
reach for, with note-creation safe by default — the surface the agent protocol
will later point at.*

### Added

-   **`lua/pkm/commands/` — one file per command context** (Ph1). The 58 `:PKM*`
    registrations moved out of the single `commands.lua` into a directory
    (`note`, `tag`, `cite`, `browse`, `view`, `vault`, `trash`, `list`, `header`,
    `panel`, `export`, `misc`), wired by `init.lua`, which still exposes the one
    `register()` that `pkm.init` calls — so `require('pkm.commands')` is
    unchanged. Behaviour-identical; the enabling refactor that lets each context
    be its own phase.

-   **Eleven verb-contexts**, each `:PKM<Context> <verb>`, dispatched through
    `pkm.args` with completion drawn from the same verb table:
    `:PKMNote` (new/relative/journal/scratch/rename/delete/import/convert/promote/
    transpose/changetype/settitle), `:PKMTag` (add/remove/merge),
    `:PKMCite` (add/remove/goto/insert/update/link/follow/backlinks),
    `:PKMBrowse` ([filter]/recent/orphans/tags), `:PKMPanel` (explorer/buffers/
    sidebar/mode), `:PKMHeader` (append/next/prev/levelup/leveldown),
    `:PKMList` (convert/renumber), `:PKMTrash` (restore/empty),
    `:PKMExport` (simple/deep), and the already-dispatching `:PKMView` and
    `:PKMVault`, which absorbed their sibling commands as verbs.

-   **The safety slice** (Ph2). `:PKMNote new … by=<agent>` is the one safe
    creation path — it allocates the next number, writes schema-correct
    frontmatter, keeps the citation graph in step, and stamps the `By<Author>`
    authorship marker — while no argument stays the friendly prompt, so human
    use is untouched. Each context's verb and its alias share one core, so the
    two forms cannot drift.

### Changed

-   **Every old command name is kept as a working alias** (`:PKMNewNote`,
    `:PKMRenameNote`, `:PKMAddTag`, `:PKMViewNew`, `:PKMVaultNew`, …), driving
    the same cores as the new verbs. Nothing a user or script types today
    breaks; the `:PKM<TAB>` list does not shrink until part 2 removes them.

### Deferred to v1.14.0 (alias deletion)

-   `:PKMTags`' **batch and tag-rename** half must be homed on `:PKMTag`
    (`:PKMBrowse tags` already covers its browse half) before `:PKMTags` is
    removed; and `validate_name` must reserve the verbs as names, since a view
    or vault named exactly like a verb is shadowed by it.

---

## [1.12.0] - 29/7/2026

*Smoke route passed in full
(`00 - NotesTeste/03-Consolidated/0271_note_smoke-v1120-formas-tipadas.md`),
including the prompt and Telescope steps the headless suite structurally cannot
see. The evaluations follow next, then the command clearup.*

*Every operation that writes state grew a typed form, so the interactive and the
programmatic paths are the one command: no argument gives the friendly path,
an argument makes it deterministic and script-callable (Design Question 4.d).
This is the surface the agent protocol will drive, and the last version that
adds commands in bulk before the command clearup.*

### Added

-   **`lua/pkm/args.lua` — one reading of a command's arguments** (Ph1). The
    grammar `:PKM<Context>[!] <verb> [positional] [key=value]` was open-coded in
    each command; this is the single parser. It is not new — it generalises
    `views.parse_command_args` and `tags.parse_command_args`, both of which
    migrated onto it, which is the proof it serves both rather than becoming a
    third dialect. The one real difference between callers — whether a first
    word that is not a verb is a name or a mistake — it reports as `is_verb` and
    leaves to the caller. `complete_verbs` draws from the same table the parser
    reads, the property the clearup will lean on.

-   **The note lifecycle takes arguments** (Ph2). `:PKMNewNote note title=Foo`,
    `:PKMSetTitle <text>` and `:PKMRenameNote <name>` do straight through what
    they used to only prompt for. `title=` is one token (Neovim splits on
    whitespace); a spaced title is set with `:PKMSetTitle`, which takes the whole
    argument string. A supplied title also means "do not interact", so a bib note
    created with `title=` no longer stops to prompt for author and source.

-   **Cite and uncite by reference** (Ph3). `:PKMCite <target>` and
    `:PKMUncite <target>`, with the picker still there when no argument is given.
    The body text is the source of truth, so cite appends the token and uncite
    strips it, and both run `update_references` — the single engine that keeps
    `cites` here and `cited_by` there in step. The target resolves from a path,
    an identifier or a token; a bare number is refused as ambiguous.

-   **Tags and views on a named note** (Ph4). `:PKMAddTag <tag> note=<ref>` and
    `:PKMRemoveTag <tag> note=<ref>` write to a named note on disk (the buffer-only
    forms are unchanged without `note=`). `:PKMView add|remove <view> note=<ref>`
    makes a named note a member of a view by applying its tag condition — refusing,
    rather than guessing, when a view can be satisfied several ways.

-   **Agent authorship, and a deletion guard** (Ph5). `:PKMNewNote … by=Claude`
    marks a note `NNNN_type_By<Author>_slug` and records the author.
    `notes.agent_delete` — the path the agent protocol will call — trashes only
    notes carrying a `By<agent>` marker, read from the name so it survives a copy
    or a move: an agent inside a human's vault must not delete what a human wrote.

-   **`:PKMCheck` — a read-only vault audit** (Ph6). New pure module
    `lua/pkm/check.lua`: frontmatter validity, `cites`/`cited_by` symmetry,
    citations resolving to notes that exist, numbering collisions, cross-vault
    references naming an unregistered (or renamed) vault, and notes stranded in
    `Unregistered/`. Built to never cry wolf — verified by a system-produced
    corpus reporting zero findings, and by the real test vault's 49 findings
    being confirmed genuine (BibTeX imports and old journals that truly lack
    frontmatter, plus real graph asymmetries).

### Changed

-   **`views` and `tags` parse their command arguments through `pkm.args`.**
    Same behaviour, one parser; their public `parse_command_args` signatures and
    every contract are unchanged, which the suite confirms.

## [1.11.1] - 27/7/2026

*The v1.11.0 indicator reached the sidebar title, the vault picker and
`vim.g.pkm_vault`. It did not reach the two places a note is actually looked
at.*

### Added

-   **The buffer panel shows which vault each note is in.** `V01` per row, and
    the active vault named in the header — where you are, and where each buffer
    is, read by comparing two numbers rather than by learning a symbol. The
    column appears only when more than one vault is registered: with one it is
    noise on every row, and it starts meaning something exactly when confusion
    becomes possible. A file in no vault keeps the column blank rather than
    borrowing a number, so the type prefixes stay in one column.

-   **`pkm.vault.statusline()`**, returning `V01 Vitruvia`, and appending
    `[buf V02]` when the buffer in front of you belongs to a different vault.
    That second half is the part worth having: such a buffer sits outside the
    root, so `in_root` answers false and saving it stops stamping the timestamp,
    syncing citations and touching the index — it still looks like a note and
    has stopped being treated as one. The one state where the screen and the
    truth disagree, said continuously rather than at the moment of a switch.

### Known limitations

-   A note from **another** vault renders in the buffer panel as `[f]` with its
    filename rather than `[n]` with its title, because the index is per vault
    and that note genuinely is not in it. Honest, and it reinforces the signal,
    but it is a consequence rather than a decision.

---

## [1.11.0] - 27/7/2026

*Smoke route passed in full
(`00 - NotesTeste/03-Consolidated/0270_note_smoke-v1110-os-vaults-sao-enumerados.md`),
including the three Telescope screens the headless suite structurally cannot
see. Two defects were found and fixed during it, both recorded below: the
trailing separator, and the first run complaining about a path nobody chose.*

*The active vault stopped being a path written into `init.lua`. A registry
beside the vaults maps a number to a name, the folder is derived from the pair,
and everything that depends on the path feeds from that instead of from a
constant. Three phases: the registry and identity, the lifecycle, and choosing.*

### Added

-   **`lua/pkm/vault.lua` — the registry and vault identity** (v1.11.0 Ph1).
    `vaults.json` sits one level above the vaults and holds
    `{ number, name }` per vault; the folder `NN - Name` is **derived** and
    never stored, so renaming and renumbering are moves and neither touches a
    note. A note belongs to a vault **by path** — nothing is written into the
    note — so the 897 existing notes needed no migration, and moving a note
    between folders moves it between vaults, which is correct for something
    that *is* a folder.

    `of(path)` compares plainly, never as a Lua pattern: `00 - Alpha` read as a
    pattern is "00, then any spaces, then ` Alpha`", which matches the folder
    `00 Alpha` and fails to match `00 - Alpha` itself — wrong in both
    directions, and every vault folder carries the hyphen. Verified against the
    interpreter, and pinned by `test/test_v1110_p1.lua`.

    `Note-Vault/` is not a git repository (each vault is), so `vaults.json` is
    the one piece of state nothing can rebuild: written to a temp file and
    renamed over the original, keeping the copy it replaced as `.bak`, and
    validated before any of it reaches disk. New config key `vaults_path`, the
    directory the vaults sit in; **`root_path` alone keeps working exactly as
    before**, which the other 29 test files and `min_init` all depend on.

-   **The vault lifecycle, five commands** (v1.11.0 Ph2). `:PKMVaultNew`
    (folder, skeleton named from `config.folders`, `views.json`, `.gitignore`,
    `git init` unless `!`), `:PKMVaultRename` (keeps the number),
    `:PKMVaultRenumber` (keeps the name), `:PKMVaultUnregister` (moves the
    folder to `Unregistered/`, always confirms) and `:PKMVaultAdopt` (the way
    back, and the way a Note-Vault that predates the registry acquires one —
    contents taken as they stand).

    **Deleting a note is not reachable from any of them.** Unregistering moves
    the folder intact, because each vault is a git repository and a file manager
    removes one visibly and into the system's recycle bin. So there is no note
    orphaned from every vault, only one waiting in `Unregistered/`.

    The folder moves first and the registry second; a failed registry write puts
    the folder back. A move is refused while any buffer under the vault is
    unsaved — afterwards that buffer would still name a file in a folder that no
    longer exists, and `:w` would recreate the folder to hold it, resurrecting
    the vault as a ghost with one note in it. Renaming the vault you are working
    in is safe: `root_path` is mutated **in place**, which is what reaches the
    eight modules holding that same table, and open notes are re-pointed.

-   **`vault = "<name>"` at startup, and `:PKMVault` at runtime** (v1.11.0 Ph3).
    The name resolves through the registry into `root_path` before any module is
    handed that table — nothing derived exists yet, which is why the startup form
    needs none of the invalidation the runtime one does. `$PKM_VAULT` outranks
    the config for one session, which is what lets the ordinary configuration run
    against the test vault without being edited.

    `:PKMVault` has three guards. What the old root produced is discarded
    together — the index and **both** view caches, because `views.json` lives
    *inside* the root and a sidecar held across a switch resolves one vault's
    saved views against another vault's notes. The switch is refused while the
    vault being left holds unsaved work (`force` overrides; the refusal is a
    guard, not a wall). And the indicator, which the other two rest on: after a
    switch the two vaults are identical on screen and every destructive command
    acts on "the vault", so it is published to `vim.g.pkm_vault`, shown in the
    sidebar title, and marked in the `:PKMVault` list.

### Design notes

-   **No aliases.** A rename does not keep the old name as a second name; the
    old name stops meaning anything immediately. Keeping it is exactly what
    would let vault 01 be renamed to vault 02's old name and answer to it.
    Accepted consequence: a `[NomeAntigo::note{0042}]` written before a rename
    can, once someone reuses that name, point at the wrong vault silently.
    `history` records renames so a later `:PKMCheck` can say so, and is **never**
    consulted to resolve a name — not being a namespace is what stops it
    colliding with one.

-   **`doc/PHILOSOPHY.md` §2 was amended, by the author's decision.** It read
    that "physical project isolation (multi-wiki)" was out of scope, which the
    vaults made literally false while leaving the substance intact. It now says
    what it always meant — that *projects* are never separated physically, and
    that within a vault a project is still a view and never a folder — and names
    the four reasons a vault exists: the owner's own knowledge, testing,
    collaboration with LLMs, and genuine isolation as an edge case. Splitting a
    project across vaults is a misuse of the feature.

-   **Nothing outside the registry names a vault.** `vaults_path` names the
    *container* — the directory the vaults are siblings in — and that is the
    entire configuration. Which vault opens is `"default"` in `vaults.json`,
    set with `:PKMVault!`.

    It lives there rather than in `init.lua` for a reason that only the registry
    can satisfy: **the registry is what performs a rename, so it is the only
    place that can keep a reference true across one.** A name written in the
    user's config cannot be corrected by a rename, because a rename never reads
    the user's config. Stored by *number* so a rename does not touch it at all,
    and rewritten by `renumber()` in the same write that moves the folder;
    `unregister()` clears it rather than passing it to a neighbour, because
    which vault becomes the default is the user's to say. `create()` and
    `adopt()` set it when there is none, so the first vault registered is the
    one that opens.

    `vault = "<name>"` survives as an optional per-machine override, and
    `$PKM_VAULT` as a per-session one — most specific first. Renaming,
    renumbering, unregistering and adopting all leave `vaults_path` untouched,
    so nothing a vault command does can invalidate the configuration.

-   **A trailing separator on `vaults_path` or `root_path` is stripped.**
    `"P:/Note-Vault/"` is the natural way to write a directory and made every
    path built from it `dir//child`. Nothing errored — the OS opens such a path
    — but `of()` compared one separator against two, the prefix missed, and the
    vault silently stopped being recognised: no indicator, no active vault, and
    `:PKMVault` unable to say where you were. The worst shape a defect can take,
    since every individual operation appears to work.

    `vaults_root()` was briefly derived from `root_path`'s parent when
    `vaults_path` was unset. That was wrong and was removed before the version
    shipped: a root pointing anywhere at all — a stale one, a temporary one, a
    plain `~/Notes` — would silently designate its parent as the directory this
    module lists vault folders from and writes the registry into. A path chosen
    for one purpose must not become a write location for another. Unset now
    means no registry, which is a supported state and not a fallback.

### Fixed

-   **`:PKMVaultAdopt` could not find the folders it accepts.** It already took
    a folder sitting beside the vaults — the bootstrap path, since the existing
    vaults are already in their folders and must not move to be registered — but
    completion offered only `Unregistered/`. For a first use, invisible and
    missing are the same thing.

---

## [1.10.1] - 27/7/2026

*The defect queue, five phases. A note’s text stopped being read as
configuration; two assertions that had outlived what they described were
retired; `:PKMOrphans` stopped rebuilding and sorting a set it only tests
membership on; and the trash learned twice over that it holds a place in the
vault rather than a place on the disk — once for where a note came from, once
for where its text can still be read.*

### Fixed

-   **A note's text is no longer read as configuration** (v1.10.1 Ph1). A line
    like `um exemplo ex: Será` is a Vim modeline — text, whitespace, the `ex:`
    marker, and what Vim then takes for an option name — so opening or saving
    such a note raised `E518: Unknown option`. Two triggers, closed separately:
    Neovim applies modelines when it reads the file, and PKM re-fired them on
    **every save**, because `:doautocmd` applies modelines unless given
    `<nomodeline>` and the Syntax refire in `BufWritePost` did not give it.
    Notes now carry `modeline = false` buffer-locally (set on `BufReadPre` /
    `BufNewFile` under the root, the last moment that can prevent them), and the
    refire is `doautocmd <nomodeline> Syntax`. The global option is untouched:
    files outside the vault keep their modelines.

    The comment in `init.lua` claimed this risk had left with `noautocmd e`. It
    had not — `:e` was one trigger, the refire was the other. The bug also
    reproduces only in the form that has text *before* the marker: a line
    starting with `ex:` is not a modeline, which is why a first reproduction
    attempt wrongly suggested the defect was already gone.

-   **Two assertions that outlived what they described** (v1.10.1 Ph2). Test
    drift, not code defects, and the whole suite is green again for the first
    time since v1.5.4. `test_phase1_old.lua` asserted that an unknown field
    prefix is rejected; since v1.5.4 it is not a field at all but the value of
    an `any:` predicate, without which `http://x` and `TODO:` are unsearchable.
    The assertion now states that, and checks the *value* too — a parser that
    dropped the `body:` part would also report `field == 'any'`, and would be
    wrong. `test_v160_p3.lua` demanded `Views` and `browse all` on one header
    line; the panel never rendered them together — the header names the panel
    and points at `?`, and the hint lives in the `?` overlay. The check now
    presses `?` and reads the overlay, which is the only route to the hint.

-   **`:PKMOrphans` no longer rebuilds and sorts what it only counts as a set**
    (v1.10.1 Ph3). It called `views.match_all` once per view, so it read the
    index V times and paid V basename sorts — an ordering it then discarded,
    since all it does with the result is test membership. New
    `views.match_set(names)`: the batch, unordered counterpart of `count_many`
    — one `index.get_all()`, V filter passes, a set of normalized paths, with
    the same notify-and-contribute-nothing behaviour on an unknown view.

-   **`bench.lua` resolves its bench directory in one separator** (v1.10.1
    Ph3). A caller-supplied Unix-style dir on Windows (`/tmp/pkm_bench`) was
    joined with the *native* separator, so every derived path mixed the two.
    New `bench._resolve_bench_dir(supplied, suffix)`, called by all four entry
    points. Worth recording how this was verified: the files always came out
    right, because `mkdir` and `glob` both accept mixed separators — so a test
    that created files and found them would have passed with the bug still in
    place. The check is on the resolved string.

-   **The trash remembers a place in the vault, not a place on the disk**
    (v1.10.1 Ph4). A manifest entry recorded an absolute `original_path`, which
    tied the trash to one directory: copy a vault and the copy's manifest still
    points at the original, so restoring from the copy writes into the vault it
    was copied from. `NotesTeste` was in exactly that state — entries reading
    `P:\Notes\03-Consolidated\…` with the files sitting in its own
    `.pkm-trash/`. The location is now stored **relative to the root**, with
    `/` separators so a manifest travels between platforms, and read back
    through the new `trash.resolve_original(entry)`, which re-roots whichever
    form it finds: relative onto the current root; absolute-and-already-inside
    taken as it stands; absolute-from-elsewhere re-rooted from the first
    recognised note folder; and anything unrecognisable placed in the
    consolidated folder, because writing outside the current root is the one
    thing restore must never do. No existing manifest needs rewriting.

    Measured against the real entry still in `NotesTeste`: the old target was
    `P:\Notes\03-Consolidated\0131_note_test2.md` (outside the session's root),
    the new one is `P:\NotesTeste\03-Consolidated\0131_note_test2.md`. This is
    also what unblocks vault switching. `test_v160_p2` was matching entries by
    the raw field and now goes through `resolve_original` — the contract.

-   **Emptying the trash no longer opens a file that is not there** (v1.10.1
    Ph5). `citations.cleanup_deleted_note()` took one path and used it for two
    different things: the note's *identity*, read off the filename, and the
    place its *text* can be read, to learn what it cited. For a note deleted in
    place those coincide; for a trashed note they do not — it has already left
    its original path, and its content sits in `.pkm-trash/`. So `readfile()`
    raised `E484: Can't open file`, which took down step 2 as well — the part
    that strips references *to* the deleted note. `trash.empty()` aborted on
    its first entry with the manifest and the trashed files untouched, and
    `purge_old()`, which runs by itself five seconds after `setup()` whenever
    `trash.max_age_days > 0`, failed in the background the same way.

    The function now takes an optional second argument, where the text can be
    read, and the trash passes the copy it still holds; an unreadable one skips
    step 1 instead of aborting. The phase test asserts the thing that separates
    a fix from a silencer: the cited note must actually **lose its backlink**,
    which can only happen if the frontmatter was read — from the copy. The
    graph it checks is built by the plugin's own `update_references`, not by
    hand.

-   **A modeline probe must not measure an option someone else writes**
    (v1.10.1 Ph1 follow-up). The Ph1 control asserted that a modeline had
    fired by reading `shiftwidth`, and Neovim's markdown ftplugin ends with
    `setlocal expandtab tabstop=4 softtabstop=4 shiftwidth=4`, running *after*
    the modeline. On a real session `shiftwidth` therefore reports 4 from
    `markdown.vim` whether the modeline fired or not — the expected value and
    the unexpected one both arrive from the wrong author, and `:verbose` names
    that author either way. The control and the smoke note now use
    `numberwidth`, which no ftplugin touches. Verified in one buffer at one
    moment: `nuw=7` sourced from the modeline while `sw=4` is sourced from
    `markdown.vim`. Found by the author running the smoke in his own config,
    where the ftplugin is active; headless had passed for the right reason and
    so could not see it.

---

## [1.10.0] - 26/7/2026

*Header navigation, one phase — the orphan of v1.7.0. Same-level jumps on `]h`
/ `[h`, which is the gap Neovim's native `]]` / `[[` actually leaves, plus the
commands, the count and the level argument.*

### Added

-   **Header navigation** (v1.10.0 Ph1). `markdown.find_heading_target(lines,
    cursor, opts) → lnum?` is pure: no buffer, no window, no state. It takes a
    direction, a count, and an optional level — `1`-`6`, or `same`, which
    resolves to the level of the header the cursor sits under. A count that
    overshoots stops at the last header rather than refusing to move; nil means
    there is no header that way at all. Headers inside YAML frontmatter (where
    `#` opens a comment) and inside fenced code blocks (where it usually opens
    a shell line) are not targets, nor is a `#hashtag` with no space after it,
    nor seven hashes; three leading spaces and a bare `#` still count.
    `markdown.goto_heading(opts)` is the cursor wrapper: it lands on the `#`,
    leaves a jumplist entry so `<C-o>` returns, and is silent at the boundary —
    a motion that cannot move is not an error — but says so when the buffer has
    no header at all.

-   Commands `:[count]PKMHeaderNext [same|h1-h6]` and `:[count]PKMHeaderPrev`,
    and keymaps `header_next_same` `]h` and `header_prev_same` `[h` — normal
    **and** visual mode, buffer-local on markdown the way `ftplugin/markdown`
    binds `]]`, wired as Lua callbacks so `v:count1` is read at press time and
    the selection extends instead of collapsing. `header_next` / `header_prev`
    exist but are unbound: any-level jumping **is** `]]` / `[[`, and a key that
    repeats the editor is a key spent for nothing. Same-level motion has no
    native equivalent, so it is what gets the keys — unmodified, in the bracket
    family the native motion already lives in.

    The level argument is spelled `h2`, not `2`, because these commands take a
    count and Vim reads a leading number in the arguments **as** the count:
    `:PKMHeaderNext 6` means six headers ahead and always did. The first
    self-guiding smoke note is what caught it — the assertion that was supposed
    to cover it started at a line where both readings gave the same answer, so
    it had been passing over the defect. See `doc/PRINCIPLES.md` § The smoke
    note.

    **What Neovim already does, checked in the runtime rather than assumed.**
    The ROADMAP recorded that Neovim's native motion was *same-level* and that
    PKM should add the any-level complement. That is backwards.
    `ftplugin/markdown.lua` maps `]]`/`[[` to `vim.treesitter._headings.jump`,
    which moves to the next/previous heading of **any** level. What it does not
    do is honour a count (`todo(clason): support count`, in the runtime file),
    restrict the jump to a level (`jump()` accepts `opts.level`, but the
    mappings never pass it, so same-level motion is unreachable), leave a
    jumplist entry, work in Visual mode (there an older regex mapping takes
    over, and it misses `######`), or work at all without the tree-sitter
    markdown parser. This ships the complement as it actually stands.

### Changed

-   `:PKMNextHeader` is now **`:PKMHeaderAppend`**. It edits the buffer, while
    the new `:PKMHeaderNext` only moves the cursor, and under the old pair of
    names the wrong one was one completion away — and the wrong one writes.
    Every header command is now `PKMHeader*`. The config key stays
    `next_header`, so an existing `<leader>Mh` keeps working untouched.

---

## [1.9.0] - 26/7/2026

*Views reached from where you already are: `:PKMView add|remove <name>` acting
on the note in front of you, and a note created already inside a view. Two
phases, plus the window-placement work the second one turned out to need.*

### Added
-   **The new note can say where to open (v1.9.0 Ph2).** `[count]N` puts it in
    the *count*th editing window from the left, exactly as `[count]<CR>` already
    opens an existing note there; `<C-y><C-v>` and `<C-y><C-x>` put it in a
    split to the right or the left, mirroring `<C-v>`/`<C-x>`. A bare `N` keeps
    firing immediately — only `<C-y>` carries the chords, so the common key
    never waits out `timeoutlen`.
-   **`:PKMNewNote [note|agg|bib] [left|right|N]`** — the same placements from
    the command line, as arguments rather than a second command. Both arguments
    are optional and order-free: the type comes from a closed set and the
    placement is a side or a number, so neither can be read as the other. An
    argument that is neither says so instead of being ignored.

-   **A note can be born inside a view (v1.9.0 Ph2).** `N` in the views panel
    and the sidebar — `<C-y>` in the Telescope pickers, where a bare letter
    would just be typed into the prompt — creates a new note whose tags already
    satisfy the view under the cursor. It is the same question `view_flow`
    asks, put before the note exists: because a new note carries no tags, only
    the tags to *add* matter, and they are **seeded at creation**
    (`notes.create_new_note(type, { tags = … })`) rather than written
    afterwards. The note is born matching instead of being edited into place.
-   **`tags.new_note_in_view(name, on_done?)`** — one alternative goes straight
    through, several ask which. A view tags cannot fully reach does **not**
    block creation: the note is created with whatever tags do apply and the
    condition in the way is named, because "this will not match until you write
    the title" is something the author needs to know *while* writing the note,
    not instead of it.
-   **Wired at every view surface in one pass**, through a single helper: the
    Telescope views tree, a view's own note list in both back-ends, the
    no-Telescope views panel, and the sidebar in both modes. Browse-all-notes
    is deliberately excluded — there is no view under the cursor there. This is
    the sweep `<C-a>` needed three attempts to get right, and the helper exists
    so it stays one edit rather than six.
-   `test/test_v190_p2.lua` — seeding for a single tag, for two, and for a
    chosen branch of an `OR`; the partially-reachable view (tag seeded, blocker
    named, note still created); the title-only view; an unknown view creating
    nothing; and the two surfaces that are plain buffers actually carrying the
    key. The Telescope panels stay smoke-only, as always.
-   **`:PKMView add|remove <name>` acts on the note you have open (v1.9.0
    Ph1).** No new command: the verbs are arguments, so `:PKMView leituras`
    still opens a view and nothing that worked before reads differently. It is
    the quick way to give a note the several tags a view requires — the note is
    born belonging to it instead of being tagged by hand afterwards.
-   **`views.parse_command_args(fargs, names)`** — pure, so the command's
    contract is testable on its own and reads the same way for a script.
    One command carries three meanings, resolved by a rule rather than by
    guesswork: **if the arguments spell an existing view name exactly, it is an
    open**; only then are `add` and `remove` read as verbs. A view actually
    named `add` therefore keeps working, and a name containing spaces needs no
    quoting, because the argument list is joined before it is compared.
    Completion follows the same reading: verbs and names before a verb, names
    only after one.
-   **`ctx.target` in `tags.view_flow`** — a view the user *named* is an answer,
    and no menu is shown. It is deliberately a different field from `ctx.view`,
    which is where the notes came *from* and only ever orders the menu: the
    v1.8.1 defect was those two being the same thing, and keeping them apart is
    what stops it growing back. Removing from a view the note is not in reports
    that instead of writing, and an unknown name is refused before anything is
    computed.
-   **A batch of one note gets a gate, not a note picker.** With a single note
    there is nothing to narrow, so the ordinary confirmation promised a
    per-note choice the operation did not have — `:PKMView add` ended in a
    Telescope list holding one entry. It is now `picker.confirm`: the change on
    one line, `<CR>` or `q`. And when the user typed the whole operation
    (`:PKMView add <name>`) there is **no screen at all** — typing was the
    operation. Removal keeps its gate either way, per `doc/PRINCIPLES.md`.
-   **An alternative now says what it would *change*, not what the view
    requires.** `filter.tag_sets` answers "what does this view need", so a
    choice read `+administração-financeira-orçamentária, +concursos-públicos`
    even for a note already carrying the first. A tag is dropped from the
    wording only when it is redundant for **every** note in the batch, so the
    reduced form stays accurate for all of them; the operation still applies
    the full set, which is idempotent.
-   `test/test_v190_p1.lua` — the argument rule across every shape (bare name,
    multi-word name, either verb, a verb with no name, an unknown name, and a
    view actually called `add`), then the flow over a real corpus: a named view
    opens no menu, a wrong one is refused, and provenance does not override it.

### Fixed
-   **Creating a note from a panel crashed with E1513 (v1.9.0 Ph2).** Panels set
    `winfixbuf`, so `:edit` from one is a hard error rather than a hijacked
    panel — the intended trade — but `create_new_note` opened the new note in
    whatever window was current. `:PKMNewNote` guarded itself with its own
    private `focus_main_win()`; nothing else did, so creating from the sidebar
    (and `<leader>nn` from the buffer panel) failed at the last step.
    **`create_new_note` now owns the guard**, since it is the function that
    opens a buffer, and every caller is covered by construction.
-   **`utils.focus_editing_win(where)`, `utils.editing_wins()`,
    `utils.is_editing_win(win)`** — the search for "a window a note may be
    opened in" existed twice already (`commands`, `views`) and creation needed a
    third copy. It lives in `utils` now. When no such window exists it makes
    one **against the panel it is leaving**: beside a sidebar, above a buffer
    panel, so the result lands where the eye expects it.

-   **The frontmatter fold broke after a bulk tag write (v1.9.0 Ph1).** Adding
    a note to a view changes the frontmatter's line count, and the fold is
    `foldmethod=manual` — it does not survive a buffer reload at all — so the
    bottom of the block sat outside its own fold until the next save happened
    to rebuild it. `bufsync.reload` now calls `syntax.refresh_fold` on every
    buffer it re-reads, which is what the rest of the plugin already did after
    a frontmatter mutation.


## [1.8.1] - 26/7/2026

*The defects the v1.8.0 smoke pass found, and the standing rule one of them
produced. Three phases: view membership offering the wrong views, confirmation
on every removal, and the undo cursor — the last reproduced before it was
touched, which is what finally ended a bug that had been "fixed" three times.*

### Fixed
-   **`u` landed on the frontmatter timestamp (v1.8.1 Ph3).** Fixed three times
    before and back every time, because every attempt adjusted the cursor. The
    reproduction settles it: Neovim positions the cursor after `u` on the
    **first changed line of the undo block**, recomputed from the changed
    region — so saving and restoring the cursor around the rewrite, which is
    what `BufWritePre` did, provably cannot work. Measured on all four
    strategies: `undojoin` → frontmatter; no join → frontmatter; cursor
    restored first → frontmatter; `undolevels = -1` → right cursor but the undo
    history is **discarded**, which is worse than the bug.

    The cause was structural: `yaml.save_frontmatter` replaces the *whole*
    frontmatter block, and `BufWritePre` merged that into the user's undo block
    on every save. The frontmatter sits above the body, so `u` always landed
    there. **`BufWritePre` no longer touches the buffer.**
-   **`last_updated_on` is now written to the file when the note is released**
    (`BufDelete`, `VimLeavePre`), and only for notes actually saved during the
    session — opening a note and closing it leaves it untouched. The buffer is
    never rewritten while it is being edited, so buffer and disk stay identical
    throughout, and `u` lands on the edit at the first press. Nothing in the
    plugin reads this field: recency comes from the filesystem mtime the index
    already stores (`index.lua`), which is what `:PKMBrowseRecent` and the
    sidebar sort by. `yaml.update_timestamp()` remains dead code — it had no
    callers before this change either.
-   **The post-write reload was swallowing the user's next edit (found while
    fixing the above).** After the reload replaced the buffer, the undo block
    was left *open* — Neovim closes one when a command finishes in the main
    loop, and a scheduled callback is not a command — so whatever the user
    typed next was absorbed into the reload's undo state, and one `u` reverted
    the edit *and* the reload together. The reload now forces the break
    (`let &undolevels = &undolevels`, which unlike setting it to `-1` keeps the
    history) and no longer joins the user's block at all. The buffer *replace*
    is also skipped when the file on disk already matches it, which is every
    save that did not change a backlink.
-   **Repeated saves stopped to ask for confirmation** — introduced by that skip
    and caught in the smoke pass. The citation passes write the note on disk
    after Neovim's own write, leaving Neovim's record of the file stale, and a
    stale record makes a later `:w` stop with W11 ("changed since editing
    started, really write?") on a note nothing else had edited. The buffer is
    now written back on every save, whether or not the content differed; only
    the buffer *replace* is conditional. The two are separate concerns and were
    wrongly folded into one branch.
-   `test/test_v181_p3.lua` — the reproduction, kept as the regression test:
    edit a body line, save, undo, and ask only where the cursor is. Covers a
    fresh note (whose first save legitimately expands the frontmatter), the
    same buffer in two windows, the steady state of an already-normalised note,
    and the stamp itself — present after release, absent when the note was only
    read. The W11 regression is guarded by a child Neovim started **on a pty**
    with a deadline: on an ordinary pipe the prompt reads EOF and the child
    sails past it, so the guard would pass with the bug present. It was checked
    both ways — failing on the defect, passing on the fix.
-   **`D` in the buffer panel threw away unsaved work without asking
    (v1.8.1 Ph2).** It ran `bdelete!` straight through, so force-closing a
    modified buffer lost the edits silently — which was the entire difference
    between `D` and `d`, and the one place in the plugin where something
    irreversible happened with no screen in front of it. `D` now asks *only*
    when the buffer is modified: force-closing a saved one still costs nothing
    and so still asks nothing. The question states what is lost ("close and
    lose its unsaved changes?") rather than warning about itself, and defaults
    to Cancel.
-   **Every removal confirms — now a standing rule**, recorded in
    `doc/PRINCIPLES.md` § *Standing bug-prevention design rules* after an audit
    of every path that removes anything. It is the deliberate counterweight to
    "one panel, not a wizard": **a menu asks *what*, a confirmation guards the
    *irreversible***, so one-option menus go and confirmations stay. Neither a
    command called with explicit arguments nor a "force" key is exempt. The
    audit found the rest already compliant — note deletion, `:PKMEmptyTrash`,
    both view-deletion paths, and every `tags` batch, whose preview list *is*
    its confirmation. Deliberately exempt and documented as such: buffer-only
    changes `u` reverses (`:PKMRemoveTag`), and configured maintenance that
    reports instead of asking (`trash.max_age_days`).
-   `views.delete()` documents that it deletes without asking and that the
    confirmation belongs to its callers — both of which have one.
-   `test/test_v181_p2.lua` — drives the panel for real: the question is absent
    on a saved buffer, present on a modified one, cancelling keeps the buffer
    *and* its edits, discarding closes it, and `d` still offers to save.
-   **View membership only ever reached the view you came from (v1.8.1 Ph1).**
    Selecting notes inside a view, the only available operations were adding
    them to *that* view — where they already were — and removing them from it.
    Another view was unreachable in both directions, including removing a note
    from a second view that also contained it. The design error was treating
    `ctx.view` as an answer: where a selection came from says nothing about
    where it should go.

    `ctx.view` now **orders the menu and never makes the choice**. *Add* offers
    every view, with the ones the selection is already wholly in sunk to the
    bottom and labelled as such, since those are the one useless answer.
    *Remove* offers **only the views the selection is actually in** — computed
    per view rather than assumed — with the context view leading, and it acts
    on exactly the notes that are in the chosen view rather than on the whole
    selection. A selection belonging to no view says so instead of opening a
    menu of impossible choices, and a single candidate still opens no menu at
    all: cutting a menu that decides nothing and cutting the choice itself are
    different things, and conflating them is what caused this.
-   **The view menu is a Telescope panel, not the command line (v1.8.1 Ph1).**
    It was reached through a bare `vim.ui.select`, so a Telescope user dropped
    into the plain command-line list in the middle of an otherwise Telescope
    flow — and the same happened one screen later, choosing which way out of a
    filter to take. Both now run through **`picker.choose(rows, opts,
    on_choice)`**, the generic one-of-N menu this module was missing: it knows
    nothing about notes or tags, preserves the caller's order exactly (the
    ranking *is* the information), filters by substring as you type, and shows
    a preview of the row under the cursor — for a view, which of your selected
    notes it holds and which it does not. Without Telescope it degrades to the
    same `vim.ui.select` as before, same rows, same rendering.
-   **`tags.view_membership(paths)`** — read-only: which of the defined views
    currently hold each of the given notes, as `{ name, paths, total }` rows.
    One index lookup per path and one filter pass per (view, path); it builds no
    sorted path array, because a selection is a handful of notes rather than the
    vault.
-   `test/test_v180_p9.lua` grew the cases that would have caught this: the
    membership rows themselves (including a path absent from the index), adding
    from inside a view the notes already fill, removing with the notes in two
    views at once, and removing with them in none.

---

## [1.8.0] - 25/7/2026

*Bulk metadata operations, in nine phases: tags, titles, filenames and view
membership, all starting from a note selection. This entry also carries the work
that never got a release of its own — the `:PKMViews` counting path (planned as
v1.6.1 Ph3), the faster index build (v1.6.2 Ph1), and deep export with the
relative note (v1.7.0 Ph1–Ph2). Those numbers stayed planning labels and were
never tagged; header navigation, the v1.7.0 phase that did not ship, is now a
MINOR of its own in `doc/ROADMAP.md`.*

### Added
-   **View membership by tags (v1.8.0 Phase 9).** `<C-a>` → *Add to a view* /
    *Remove from a view*. A view is a filter, so belonging to one means
    satisfying it — and tags are the only part of a note a bulk operation may
    rewrite for that purpose, since a title or a body cannot be invented. The
    action works out which tags to add and which to remove, previews it like any
    other tag batch, and writes it.
-   **`filter.tag_sets(tree)`** — pure, and where the whole difficulty lives.
    It returns the expression in disjunctive normal form: a list of
    alternatives, any one of which satisfies the filter, each saying which tags
    must be present, which must be absent, and which conditions **no tag can
    reach**. Negation is pushed down as it goes, so `NOT (a AND b)` becomes a
    choice of removals and `NOT (a OR b)` requires both. A combination that
    contradicts itself (`tag:a AND NOT tag:a`) yields no alternative at all.
-   **A view tags cannot satisfy says so.** When every alternative depends on a
    `title:`, `text:`, `type:`, `filename:` or `any:` condition, the action
    names the condition in the way and writes nothing — adding tags that will
    not make the note match would be worse than refusing.
-   **Removal is the same question, mirrored:** the tag sets that make the
    filter *false*. That often has more than one answer — for
    `tag:projeto AND NOT tag:draft`, dropping `projeto` and adding `draft` both
    work — and the choice is offered rather than guessed.
-   **The view is never asked for twice.** `actions.run(paths, { view })` carries
    it from wherever the notes were chosen: a view's own note list, the sidebar
    (in either mode), the views picker. Only a selection from a plain browser
    asks which view.
-   `test/test_v180_p9.lua` — the tag algebra (AND, OR, De Morgan under
    negation, distribution, self-contradiction, every blocker field), then the
    flow over a real corpus: notes entering a view, leaving it by the chosen
    route, and a title-only view refusing.
-   **Bulk file rename (v1.8.0 Phase 8).** `<C-a>` → *Rename the file* is the
    same substitution panel as titles, over the editable part of the filename.
    The `NNNN_type_` prefix is identity, not description: the expression never
    sees it and the result is rebuilt around it, so numbering and type survive
    any pattern. Journal and scratchpad notes are **not** renameable — their name
    *is* their timestamp — and a selection containing them says so instead of
    quietly dropping them. The preview shows the new filename and how many notes
    cite this one and would therefore be rewritten.
-   **The write is all-or-nothing here, unlike titles.** Renaming rewrites
    `[[links]]` and citation entries in every citing note, so a batch that
    half-applies leaves dangling links. `<CR>` therefore leads to a final gate
    that accepts or refuses the whole list — `picker.confirm`, kept for exactly
    this — stating the total number of citations about to be rewritten. Two notes
    that would end up sharing a name is refused before the gate is even shown:
    the numbering prefix already guarantees uniqueness, so a collision means the
    expression was wrong.
-   **`notes.rename_file(path, new_stem)`** — the mechanical half of
    `rename_note`, extracted rather than reimplemented: the two-step dance a
    case-only rename needs on a case-insensitive filesystem, the awareness of a
    buffer holding the file (its content is preserved and its name follows), and
    the index invalidation of both paths. It does **not** propagate;
    `rename_note` remains the interactive wrapper that does.
-   `test/test_v180_p8.lua` — the stem split and the skip list, collision
    refusal, the rename mechanics including an open buffer and an existing
    target, a real batch whose citing note has body links *and* frontmatter
    entries rewritten in one pass, and note deletion still striking links
    through via the shared pass.
-   **Bulk title change, in one panel (v1.8.0 Phase 7).** `<C-a>` → *Change the
    title* opens a single panel whose prompt **is** the operation: type
    `pattern/replacement` and the rows update on every keystroke, showing
    `before → after` for the notes that match. Type only a pattern and it shows
    what matches, so the expression can be found before committing to it; the
    file previewer shows the note **with the new title in its frontmatter**.
    `<CR>` applies to everything listed, `<Tab>` narrows to a subset. No form,
    no separate result screen, no confirmation step.
-   **The regex is Neovim's own**, not Lua's: the expression that works in `:%s`
    works here, capture groups (`Aula \(\d\+\)/Aula 0\1`), `\v`, `\c` and all.
    `^/Sobre ` prepends, `$/ (wip)` appends, `\[wip\] /` removes — which is why
    there is no menu of operations. `\/` is a literal slash rather than the
    separator. A substitution that would empty a title is refused, an invalid
    pattern is reported on the row it fails on, and a note that simply does not
    match is shown as unchanged rather than as an error.
-   **`lua/pkm/rename.lua`** — `parse_substitution(input)` and
    `plan_names(items, sub)` (the input list is never mutated; the only outside
    call is Neovim's regex engine, so both are testable headlessly),
    `describe`, `format_change`, and `apply_titles(plan)` as the only writer —
    one frontmatter write per changed note plus the mandatory
    `index.invalidate`, then a **single** propagation pass.
-   **`<C-b>` goes back where the notes came from.** The first cut reopened a
    picker over the *same* notes, which could only narrow the set — no use when
    the wrong note was picked upstream. `actions.run(paths, { on_back })` now
    carries a way to reopen whatever chose them, and every surface supplies it:
    the note browser (with what was typed still in the prompt), a view's note
    list, either mode of the views panel. Backing out of the action menu goes
    there too.
-   **The panel comes back after a write.** Applying no longer ends the session:
    the substitution panel reopens over the same notes, now reading as they do
    on disk, so a second substitution costs no reopening. `<Esc>` is what ends
    it. `<C-b>` steps back to a picker over the same notes, for when the
    *selection* was wrong rather than the expression.
-   **`lua/pkm/bufsync.lua`** — open buffers are kept in agreement with what a
    bulk write put on disk. An **unmodified** buffer holding a written note is
    reloaded silently. A **modified** one is not: the batch asks first
    (`y`/`n`, and only when at least one note is actually open with unsaved
    changes, so the common case sees no prompt), saving them before the write on
    `y`, and on `n` proceeding but saying plainly that saving that buffer later
    will overwrite the change. Wired into the title panel and into the batch tag
    flow, which had the same exposure.
-   **`picker.select_live(opts, on_confirm)`** — the front-end behind it, and
    reusable: `compute(prompt)` turns what is typed into rows, `display` draws
    them, `preview` renders the result of the row under the cursor. Bulk file
    rename will use the same panel. Without Telescope it degrades to one
    `vim.ui.input` plus the ordinary confirmation picker.
-   `test/test_v180_p7.lua` — the expression parser (escaped separators, the
    replacement-less state, refusals), the planner against Neovim's regex engine
    (captures, `\v`, anchors, global replacement), and the writing layer over a
    disposable corpus including a note citing **two** of the retitled ones.

-   **Marking notes in the view surfaces (v1.8.0 Phase 6).** `<Tab>` now marks
    notes in the sidebar (`:PKMViewSidebar`, inside a view) and in the browse
    mode of `:PKMViews`; `<S-Tab>` marks and steps up. `<C-a>` acts on the marked
    notes — or on everything listed when none are marked, the rule `<CR>` already
    follows in every picker. The sidebar's overview mode keeps `<C-a>` acting on
    the notes of the view under the cursor: it lists views, not notes, so there
    is nothing there to mark and the gesture never means two things.
    Marks are keyed by path, so a refresh preserves them even when the view's
    contents shifted underneath; entering another view clears them.
-   `views.toggle_mark(marked, key)` and `views.marked_in_order(marked, ordered)`
    — pure, so "the marked ones, or everything listed, in the order on screen"
    is asserted without opening a window. A mark for a note that is no longer
    listed is dropped rather than acted on.
-   **`<C-a>` inside an open view.** Pressing `<CR>` on a view opens
    `M.open(name)` — a *third* picker listing that view's notes, distinct from
    both the views list and the note browser — and neither its Telescope form nor
    its float fallback had the bulk-action key. Both now do, with `<Tab>`
    marking; subview rows are skipped, since they are views rather than notes.
    A sweep of every surface that lists notes confirms the rest were already
    covered; the two pickers that remain without it (citation insertion, promote)
    act on exactly one note by nature.
-   **`<C-a>` in `:PKMViews` when Telescope is installed.** Ph4 and Ph6 wired the
    bulk-action key into `_views_panel` — the `panel.lua` fallback — but
    `:PKMViews` dispatches to `telescope_views_tree_picker` whenever Telescope is
    present, which is the path most users actually get. `<Tab>` appeared to work
    there because it is Telescope's own multi-select; `<C-a>` was simply unmapped.
    Both modes of that picker now have it: over notes, the marked ones or
    everything the prompt leaves listed; over a view, every note it matches.
    `<Tab>`/`<S-Tab>` are also mapped explicitly to toggle-and-step, matching
    `picker.select`, rather than relying on Telescope's sorter-relative defaults.
    Not caught by the phase test because Telescope is absent in headless — every
    Telescope-backed surface stays smoke-only.
-   `test/test_v180_p6.lua` — the pure rule, then the sidebar driven for real:
    opened on a disposable view, marked through its own keymaps, and inspected
    through its buffer (the marker reaches the screen, survives a refresh, keeps
    the column alignment, and clears on view switch).
-   **Naming a tag goes through the picker (v1.8.0 Phase 5).** All three batch
    modes now name their tag the same way, and always show what the tag already
    means in the vault. `add` no longer asks for free text blind: it offers every
    tag **ordered by relevance to the selection** — first the ones already on
    *some* of the selected notes (completing a set is the usual reason to reach
    for a tag), then tags that keep company with the selection's tags elsewhere
    in the vault, then the rest by usage, and last the ones already on *all* of
    them, labelled as changing nothing. Typing a tag that does not exist offers
    to create it, so one screen answers both "which of my tags?" and "a new one".
    `rename` gained the same picker for its **destination**: choosing an existing
    tag merges into it, typing a new one renames to it.
-   `tags.rank_tags(rows, ctx)` — the ranking, pure: every input explicit, rows
    copied rather than reordered, and each copy carrying the note that explains
    its position (`on 2 of 4 selected`, `co-occurs on 7 notes`). `suggest_tags`
    is the read-only wrapper that gathers the context from the index.
-   `picker.select_tag` gained `opts.allow_new` (type to create, with the fallback
    offering `+ new tag…` then a prompt) and now renders each row's `note`. Its
    sorter became pass-through, so the caller's ranking survives to the screen.
-   `test/test_v180_p5.lua` — the four ranking tiers and their wording, the input
    left untouched, `suggest_tags` over a corpus (partial coverage, co-occurrence,
    unrelated, already-on-all), and the create-a-tag path through the fallback.
-   **Bulk actions start from the selection (v1.8.0 Phase 4).** `<C-a>` in any
    note picker runs a bulk operation over **the notes marked there** — or, with
    nothing marked, over everything the prompt leaves listed — the same rule
    `<CR>` already obeys. Since one `live_picker` backs them all, that covers
    `:PKMBrowse`, `:PKMBrowseRecent`, the sidebar's `/` and the views tree's
    `<C-f>` at once; `<Tab>` marks. The views panel (`:PKMViews`) gets `<C-a>`
    too: over a view it acts on every note the view matches, over a note on that
    note. Choosing notes is what the navigation panels are for — rebuilding the
    selection through a command was manual work the plugin exists to remove.
-   **`lua/pkm/actions.lua`** — the bulk-action registry: a plain list of
    `{ id, label, run }`, with `list()`/`get(id)` pure and enumerable, `run(paths)`
    for the menu and `run_id(id, paths)` for a caller that already knows what it
    wants. Growing the menu means appending a row here, not touching a panel
    again — view membership and bulk rename will land exactly that way. It is
    also the first piece shaped for the future `pkm.api`: the operations are
    data, so they can be listed and invoked without a screen.
-   **`:PKMTags` takes arguments.** `:PKMTags rename draf draft`,
    `:PKMTags add draft`, `:PKMTags remove draft`, `:PKMTags browse` — with
    completion for the mode and, for `remove`/`rename`, for the existing tags.
    The argument form is deterministic (whole vault) and **still ends at the
    change list**; nothing is written before it is confirmed. No new command:
    per ROADMAP *Command clearup*, an argument on an existing command is how an
    advanced user or a script gets direct access.
-   `test/test_v180_p4.lua` — the registry (ids, labels, dispatch, unknown id,
    empty selection), `scope_choices` (why the one-option menu disappeared),
    the whole `parse_command_args` contract including its refusals, and
    `batch_on` writing a decided operation with no prompts.
-   **Rich tag picker (v1.8.0 Phase 3).** Every tag choice now runs through
    `picker.select_tag()`: each tag is listed with **how many notes carry it**,
    and the Telescope preview shows those notes (type, title, filename) before
    anything is chosen. It serves both `:PKMTags` → browse and the tag prompt of
    the batch modes; without Telescope it degrades to `vim.ui.select` with the
    count in the label. The two former tag pickers (`telescope.browse_tags`,
    `ui.browse_tags`) are gone — one implementation, one behaviour.

    The rule this phase establishes, now recorded in the ROADMAP Operating
    Principles: **a feature's Telescope display ships in the feature's own
    phase**, never as deferred UI work.
-   **The batch confirmation is a picker, not a static float.** `picker.select()`
    gained `opts.display`, so the `before → after` list is the same note picker
    as everywhere else: the file previewer works, typing filters, `<Tab>` marks a
    subset, and an unmarked `<CR>` applies to everything listed. Dropping a note
    from the batch at the last moment is therefore possible, and marking never
    changes meaning between screens. `tags.format_preview` (whole-float renderer)
    became `tags.format_change` (one row); `picker.confirm` stays for
    all-or-nothing gates where a per-note choice would be a lie.
-   `test/test_v180_p3.lua` — `tag_counts` (counts, two spellings collapsing into
    one row, a repeated tag counted once, restriction to a selection), the
    `format_change` wording, the float front-end rendering a batch through
    `opts.display`, and the `select_tag` fallback.

-   **Batch tag operations (v1.8.0 Phase 2).** `:PKMTags` now opens with a mode
    choice — browse (as before), or add / remove / rename a tag across a
    selection. Each batch mode runs the same four steps: pick a **scope** (a
    filter expression, the current note, or the active view), pick the **notes**
    in the shared picker, name the **tag**, then look at a **preview** listing
    every note's `before → after` before anything is written. Cancelling at any
    step writes nothing. `remove` and `rename` offer the tags that actually
    exist in the vault rather than free text.
-   **`lua/pkm/picker.lua`** — the note-selection front-end, extracted from
    `export.lua` so every operation that acts on a set of notes shares one
    gesture: filter, `<Tab>` to mark, `<CR>` to confirm. `select()` confirms
    **everything currently listed** when nothing is marked (matching the count
    in its title); `confirm()` is the read-only preview gate used before writes.
    Telescope or the float fallback is decided in this one place.
-   `test/test_v180_p2.lua` — the preview wording (pure) and the float
    front-end driven headlessly: `<CR>` confirms the whole list, `q`/`<Esc>`
    cancels, an empty candidate list opens nothing.
-   **Tag engine (v1.8.0 Phase 1).** New `lua/pkm/tags.lua`, split in three
    layers so the rules can be tested without touching a file:
    `plan(tags, ops)` is **pure** and holds every rule; `preview(paths, ops)`
    reports what would change and **writes nothing**; `apply(paths, ops)` is the
    only writing function, one frontmatter write per changed note plus the
    mandatory `index.invalidate` (the opposite of the buffer-only tag commands,
    which must not invalidate).

    Operations are `{ add, remove, rename }`, applied in that order: rename,
    then remove, then add. Matching is case-insensitive and duplicates are
    impossible — renaming onto a tag the note already has merges into it. A
    surviving tag **keeps the spelling it had in the file**; only tags an
    operation introduces are stored normalised, which is what stops a batch from
    rewriting every note that happens to capitalise a tag. `remove` beats `add`
    for the same tag.
-   **`:PKMNewRelative`** — create a note that inherits the current note's tags,
    so it lands in the same views without retyping its classification. Tags are
    read from the *buffer*, so unsaved edits count. Optional type argument
    (`:PKMNewRelative bib`), opt-in keymap `keymaps.new_relative` (default
    `false`). `notes.create_new_note(note_type, opts)` gained `opts.tags` for
    it, backwards-compatibly.
-   `test/test_v180_p1.lua` — 14 cases over the pure core (order of operations,
    case handling, precedence, input not mutated), then the batch layer over a
    disposable corpus (preview writes nothing, apply touches only what changes,
    re-applying is a no-op, the index sees it without a rebuild), plus
    `merge_tags` after delegation and both relative-note paths.
-   **Deep export (v1.7.0 Phase 1).** `:PKMExport` now opens with a mode
    choice, staying a single command rather than sprouting a second one
    (ROADMAP *Command clearup*: common options belong to one multimodal
    command). *Simple* is the previous flow; *Deep* changes only what happens
    after you confirm the picker — **the notes you selected become seeds** for
    a walk across the `cites` / `cited_by` graph already maintained in
    frontmatter, and what the walk finds is exported with them.

    Selecting the seeds *in the picker*, rather than seeding from every note
    the filter matched, is what makes "export this note and what it links to"
    expressible: filter loosely, mark the one note you meant. Both modes share
    the same first two steps, so the gesture is unchanged.

    Traversal is a **per-path budget**: both depths count from the selection,
    and a single path may mix directions — up to `cites_depth` hops along
    `cites` and `cited_by_depth` hops along `cited_by`, in any order. Defaults
    are **2 and 1**. All four citable groups (`notes`, `bib`, `journal`,
    `scratch`) are followed. Cycles terminate: each hop spends budget, and a
    note is only re-expanded when it arrives with a budget the visited one does
    not dominate. After the walk a message reports how many notes the selection
    grew into, then the destination prompt appears.

    New in `export.lua`, both pure and read-only:
    `read_citation_edges(path)` → `{cites, cited_by}` identifier lists (grouped
    and legacy flat frontmatter both accepted), and
    `collect_deep(seeds, opts?)` → deduplicated paths sorted by basename, seeds
    included. Identifier resolution reuses `citations.get_citable_items_map()`,
    called once per run; `opts.items_map` injects one instead.
-   `utils.read_lines(path)` — reads a file into lines without leaving LuaJIT,
    reproducing `vim.fn.readfile()`'s normalisation exactly (UTF-8 BOM dropped,
    CR before LF removed, CR at end-of-file kept, empty file → `{}`). Measured
    at ~0.54× the cost of `readfile` across 600 notes.
-   `bench.index_profile(opts?)` — developer-only profile of the index build,
    read-only. Splits the build into listing, file read, frontmatter parse,
    entry-field assembly, body concat, `body:lower()` and mtime, and prices each
    candidate replacement next to the call in use, ending with both pipeline
    totals. `index_profile({ synthetic = N })` for a disposable corpus.
-   `test/test_v162_p1.lua` — equivalence tests for the faster build: 13 raw
    line-ending/BOM/EOF cases where `utils.read_lines` must match
    `vim.fn.readfile` byte for byte, plus a fixture whose every index entry is
    compared field by field against the pre-v1.6.2 reader rebuilt inside the
    test.
-   `bench.views_open(opts?)` — developer-only benchmark for the `:PKMViews`
    open path. Read-only: it times the live index and the live view definitions
    (cold build, warm `get_all()`, both sort comparators, overview via
    `match_all` vs `count_many`, and a single-view detail open) and writes
    nothing. `views_open({ synthetic = N })` prices the same shapes against a
    disposable temp corpus when there is no real corpus to point at.
-   `test/test_v161_p3.lua` — asserts `count_all`/`count_many` agree with
    `#match_all` (simple view, subproject, empty view, unknown name), that
    counts follow index invalidation, and that `match_all`'s order is identical
    to the pre-Phase-3 comparator's on a fixture built to expose the difference.

### Changed
-   **`citations.update_references_on_renames(pairs)` walks the vault once
    (v1.8.0 Ph8).** Like the title propagation before it, the per-note function
    globbed and read three folders on every call. The batched form takes every
    rename at once and rewrites a citing note a single time even when it cites
    several of them; `update_references_on_rename` delegates with a one-item
    list, so single renames and note deletion are unchanged. Body links are now
    resolved through a lookup in one pass per line rather than one `gsub` per
    rename, which also makes a chained batch (A→B, B→C) safe.
-   **`citations.propagate_titles(titles)` walks the vault once (v1.8.0 Ph7).**
    `propagate_title` globs and reads every note in three folders *per call*, so
    a bulk retitle calling it note-by-note would be quadratic — 50 notes over a
    650-note vault is ~32k file reads. The batched form takes
    `identifier → new title` and does the same work in one pass, rewriting a
    citing note once even when it cites several of the renamed ones.
    `propagate_title(path)` now delegates to it with a one-item map, so
    single-note renames behave exactly as before.
-   **`:PKMTags` no longer opens with a mode menu (v1.8.0 Phase 4).** Bare, it
    goes straight to the tag browser — the four-option menu decided nothing for
    the common case and cost a screen every time. It survives as the
    no-Telescope fallback. The batch modes moved to where the notes are chosen:
    `<C-a>` in a picker or in `:PKMViews`.
-   **The scope menu no longer appears when it has one option.** Asking "which
    notes?" with only *Filter…* available is a step that decides nothing, so the
    filter prompt opens directly. `tags.scope_choices(path, view)` is pure, and
    the batch flow that needs a scope is now only reached by callers that have
    no selection of their own.
-   **Tag lists come from the index, not from a disk scan (v1.8.0 Phase 3).**
    `tags.tag_counts()` reads the in-memory index (cheap since v1.6.2) instead of
    `citations.get_all_tags()`, which globbed and read every note in three
    folders on each call. Two visible consequences, both intended: tags are shown
    in their normalised (lower-case) form, and `Draft`/`draft` — previously two
    separate entries in the picker — are now one row with the combined count.
    `citations.get_all_tags()` itself is unchanged and still serves
    `:PKMMergeTags`.
-   **`remove` / `rename` offer only the tags of the selected notes.** The tag
    prompt is scoped to the selection made one step earlier, and shows how many
    *selected* notes each tag appears on, instead of listing every tag in the
    vault — choosing a tag absent from the selection could only ever produce
    "no note in the selection would change".
-   **`citations.merge_tags` now delegates to `pkm.tags`** — the scan, the rules
    and the writing are one rename operation applied to every indexed note, so
    the loop that duplicated `readfile → parse → save → invalidate` is gone. Two
    intended consequences: tag matching became case-insensitive (`Draft` merges
    like `draft`), and tags untouched by the merge keep their original spelling.
-   **Index build cost (v1.6.2 Phase 1).** `index.lua` listed note folders with
    `vim.fn.glob` and read every file with `vim.fn.readfile`. Profiling the
    build over 600 notes attributed **46% of it to the glob alone** and 34% to
    the reads; the listing is now a single `uv.fs_scandir` per folder (0.7 ms vs
    107 ms — ~167×) and files go through `utils.read_lines` (~0.54× of
    `readfile`). End-to-end `index.rebuild()`, best of three:

    | corpus | before | after |
    |---|---|---|
    | **648 notes (real)** | 230.9 ms | **93.6 ms** (2.5×) |
    | 600 notes (synthetic)  | 230 ms | 95 ms (2.4×) |
    | 2000 notes (synthetic) | 790 ms | 314 ms (2.5×) |

    Per note: 0.356 ms → 0.144 ms on the real corpus (0.383 → 0.158 synthetic).
    This is the cold-build cost the v1.6.1 Ph3 measurement had isolated as what
    a first `:PKMViews` of a session actually waits on.

    The attribution shifts with note size but the conclusion does not: on the
    real corpus the reads are the largest share (41.7%) and the glob second
    (36.8%), against 34%/46% on the synthetic one, because real notes have more
    body to read per file.

    Two candidate swaps were **rejected by the same profile**, on both corpora:
    `vim.uv.fs_stat` is 1.07× the cost of `vim.fn.getftime`, and a Lua stem
    pattern 2.1–4× the cost of `vim.fn.fnamemodify(path, ':t:r')`. Both VimL
    calls stayed — `getftime` is still 12% of the build, with no cheaper source
    for `mtime` found.

    Entry shape, field values and API are unchanged — `test_v162_p1.lua`
    compares every field against the previous reader. Two deliberate
    consequences of dropping `glob`: the listing order is now whatever the
    filesystem returns (nothing depended on it — entries live in a hash keyed by
    path and `get_all()` already iterated unordered), and `'wildignore'` /
    `'suffixes'` no longer hide note files from the index.
-   **`:PKMViews` open latency (v1.6.1 Phase 3).** The views overview screens
    (Telescope views-tree, `:PKMViews` panel fallback, `:PKMViewDelete` panel,
    sidebar overview, and the parent/child counts in every view picker) used to
    call `#views.match_all(name)` once per view. Each of those calls rebuilt the
    whole entry array (`index.get_all()`), materialised a path array and sorted
    it — all to produce one number. They now use the new counting path,
    `views.count_all(name)` / `views.count_many(names)`, which reads the index
    once per batch and evaluates the filters without building or sorting
    anything. Additionally `views.match_all()` precomputes its sort keys instead
    of calling `vim.fn.fnamemodify()` inside the comparator (~N·logN VimL calls
    per open). Ordering, counts and every displayed string are unchanged.

    Measured with the new `bench.views_open()`, before and after, same corpus
    per pair (Neovim 0.11.3, Windows). The first row is the real corpus; the
    synthetic rows show how it scales:

    | corpus | overview before | overview after | detail (one view) before → after |
    |---|---|---|---|
    | **614 notes × 18 views (real)** | 9.3 ms | **6.7 ms** (1.4×) | 2.59 ms → 0.48 ms (5.4×) |
    | 600 notes × 20 views (synthetic)  |   9.3 ms | 2.1 ms (4.5×) | 0.60 ms → 0.16 ms |
    | 2000 notes × 50 views (synthetic) | 121.4 ms | 13.1 ms (9.3×) | 2.69 ms → 0.57 ms |

    Sorting all N paths in isolation: 43.7 ms (comparator-inline) → 4.2 ms
    (precomputed keys) at N = 2000, i.e. ~10× on the comparator alone.

    **Where the gain actually comes from, per corpus.** On the real corpus the
    whole 9.3 → 6.7 ms is the precomputed sort keys: the post-change overview
    costs the same through `match_all` (6.69 ms) as through `count_many`
    (6.71 ms), because at 18 views the eliminated work — 18 entry-array copies
    at 0.01 ms and sorts over small matched sets — is below run-to-run noise,
    while ~0.37 ms/view of `filter.eval` dominates. The counting path is
    therefore *structural* here: it removes the O(V) array copies and O(V)
    sorts, which is what the synthetic rows measure once V·N is large enough
    for them to matter (2000 × 50: 25.3 ms via `match_all` vs 13.1 ms via
    `count_many`). Neither corpus shows a regression.

    **Not addressed by this phase:** the cold index build, which is what a
    first `:PKMViews` of a session really waits on — 250–450 ms for 614 notes
    (0.4–0.7 ms/note; the spread is filesystem cache). `index.prebuild = true`
    already pays it at PKMMode activation, so it is only felt when views are
    opened without PKMMode. A deferred startup pre-warm would need its own
    phase (`init.lua`/`config.lua`).
-   PKM Mode's default layout now starts with `sidebar = false`.
-   Internal: `type_prefix` / `strip_display_prefix` (and their note-type
    abbreviation table) are now shared from `pkm.utils` instead of being
    duplicated in `ui.lua` and `views.lua`; `telescope.lua` keeps its distinct
    padded-label format. `utils.notify` now emits the `[pkm]` prefix (was
    `[PKM]`), matching the notifications used everywhere else. No behavioural
    change to displayed labels.

### Fixed
-   **The unsaved-buffer dialog answered itself.** `bufsync.guard` asks with
    `vim.fn.confirm`, which reads pending input — and the `<CR>` that had just
    confirmed the Telescope panel was still in the typeahead, so the dialog took
    it as "yes" and vanished before it could be seen. Saving happened silently
    and the prompt looked absent. The call is now wrapped in
    `vim.fn.inputsave()` / `inputrestore()`, which parks pending input for the
    duration. The no-Telescope path never showed this: its confirmation is a
    float whose `<CR>` is consumed by a keymap, leaving nothing in the queue.
-   **The export picker exported one note when nothing was marked.** With
    Telescope installed, `<CR>` on the results picker exported only the
    highlighted entry unless every wanted note had first been marked with
    `<Tab>`; the no-Telescope float, meanwhile, has always exported the whole
    list on `<CR>` and says so in its header. The same command therefore
    behaved differently depending on whether Telescope was installed, and
    `:PKMExportView` — "export this whole view" — copied a single note.
    `<CR>` with no marks now exports every note the prompt currently lists,
    matching the float, the picker's own match count, and what the deep export
    computes; `<Tab>` remains how a subset is chosen. Found while smoke-testing
    deep export, which made the mismatch obvious: the traversal collected the
    cited note and the picker copied only the seed.

---


## [1.6.1] - 17/7/2026

### Fixed

- **Intermittent `E482: Can't open file for writing` on save** — an
  OS-level file-open refusal, most likely a transient lock from cloud-sync
  software (`P:\` per this project's own documented Google Drive history)
  racing against this plugin's own `BufWritePost` sequence, which writes
  to the same file multiple times within one `vim.schedule` tick. Fixed
  with a minimal, additive retry wrapper around the single `writefile`
  call in `yaml.lua`'s `save_frontmatter` (Case B, disk writes only) — up
  to 4 attempts with increasing backoff (50/100/200ms). Does not touch
  `parse_yaml`/`generate_yaml` or any parsing logic. Silent in the normal
  case; `WARN`s if a retry was needed (confirms the save did eventually
  succeed); `ERROR`s only if every attempt is exhausted.
- **`zE` destroyed the frontmatter fold with no way to recover except
  saving** — `zE` has no corresponding autocmd event, so nothing observed
  the fold being torn down. Now remapped (buffer-local, torn down in
  `disable()`) to run natively then immediately rebuild the fold.
- **`gf` never followed shortened citations (`note[0042]` in body text)**
  — only recognized `[[wiki-link]]` syntax; the "full citation" that
  appeared to work was actually the YAML `link:` field's `[[...]]` text,
  not the citation token itself. `follow_link()` now falls through to
  `goto_citation()`'s own lookup when no wiki-link is found under the
  cursor, so `gf` follows either link type. `goto_citation()` gained a
  `silent` param so this fallback doesn't double up on error messages.
- **Undo after a save landed the cursor on the timestamp, not the user's
  actual edit** — `last_updated_on`'s frontmatter rewrite is merged into
  the same undo step as the user's edit (via `undojoin`) but runs after
  it, so undo restored the cursor to wherever that rewrite last touched
  the buffer. `BufWritePre` now captures the cursor before the rewrite
  and restores it after, so the merged undo step seals the right position.
- **Buffer panel sorted purely by file mtime** — reordered to match the
  requested behavior: buffers currently in a window first (left-to-right
  by column), then buffers not in any window, most-recently-opened first.
  New session-scoped `_open_order` tracked via a single `BufEnter` hook
  registered once in `M.setup` — covers `<CR>` in the panel itself and
  any other way a buffer gets focused, no per-call-site bookkeeping needed.
- **`toggle_file_explorer` (`<leader>ts`) and `view_sidebar` (`<leader>vs`)
  bound to functionally-identical actions** in the common (non-netrw)
  case — `toggle_file_explorer` disabled by default (`false`); its
  netrw-swap behavior is superseded by the sidebar's own `T` filename/title
  toggle for the "peek at raw filenames" use case, per user's own
  reasoning. `view_sidebar` remains the sole default sidebar-toggle keymap.
- **Sidebar's `<Esc>` doubled as a close key**, inconsistent with the
  Lazy.nvim/Vim-help convention this project otherwise follows (`q` only).
  Removed; `q` is now the sidebar's sole close key.

### Config
- `focus_sidebar` confirmed at its default (`<leader>s`) after evaluating
  and rejecting several `<C-*>` alternatives — `<C-,>` collides with
  Windows Terminal's Settings shortcut, `<C-[>` is byte-identical to
  `<Esc>` in a terminal (was firing on every incidental Escape press),
  and punctuation-based candidates (`<C-\>`) were ergonomically awkward
  on ABNT2. `<leader>s` has no such conflicts.

---

## [1.6.0] - 12/7/2026 to 13/7/2026

### Resolved (Design Questions / Near Goals)
- Decisions 1–3 (note relationships, meta-note type, exportation) written
  up as resolved in `doc/ROADMAP.md`; decision 2's `_meta`-subview
  convention documented in `doc/CONVENTIONS.md`.
- Two Phase X items closed: "views panel cumbersome" (superseded by Phase
  3's Telescope integration) and "view creation confirmation" (fixed
  above).
- **Views/Browse console flash** — confirmed gone by direct reproduction
  attempt (both the new `<C-f>` in-panel toggle and the old direct
  `:PKMViews` → `:PKMBrowse` command sequence were tried; neither flashes).
  No code change was needed; superseded by Phase 3's panel/picker rework.
  Phase 4 in `ROADMAP.md` can be marked shipped once the config default
  for `focus_sidebar` (still pending your key choice) lands

### Removed
- `M.list_views()`, `telescope_views_tree_picker()`,
  `float_views_tree_picker()` — fully superseded by the views panel, no
  longer reachable from anywhere, removed rather than left as dead code.

### Deferred
- Cross-panel-type switching (sidebar as a swappable "view bar" vs.
  "buffer bar" vs. a future bookmark bar, reassignable via config) — real
  scope, explicitly not built here. `_views_panel`'s `mode` field is
  intended to compose with that later rather than need replacing.

### Fixed

- **Browse-mode Telescope picker showed no notes, before or after
  typing** — `telescope_views_tree_picker`'s browse-mode `items` table
  never set an `ordinal` field, and its `entry_maker` passed items through
  unchanged (`function(item) return item end`), so every resulting
  Telescope entry had `ordinal = nil`. Telescope's entry manager needs a
  non-nil `ordinal` for internal bookkeeping even with a no-op sorter
  (`sorters.empty()`, correct here since `finders.new_dynamic`'s own `fn`
  already does the filtering) — without it entries silently fail to
  register. Fixed by setting `ordinal = e.title or e.filename or e.path`
  at construction, matching the working pattern already used by the
  sibling "views" tree mode in the same function. Pre-existing since the
  original views/browse redesign; not something this round introduced,
  and not something any existing test could have caught (nothing in
  `test_v160_p3.lua`/`test_v160_p4.lua` populates a live Telescope picker
  and checks rendered entries — a real blind spot in this project's test
  coverage worth remembering generally, not just for this bug).
- **`<C-f>` search from the views tree picker had no way back** — it
  closed the tree picker before opening results, and the shared
  `browse_paths` utility (also used by unrelated callers like `:PKMOrphans`)
  has no "return to caller" concept to hook into. Added two dedicated,
  self-contained pickers (`telescope_scoped_search_picker`,
  `float_scoped_search`) mirroring the existing detail-view picker's own
  `<C-b>` pattern. Also removed a dead `has_tele` branch inside the float
  tree picker's old `<C-f>` handler — unreachable, since you can only be in
  the float tree picker at all when Telescope was already confirmed absent.

### Added

- **Relative-split picker actions (`<C-v>`/`<C-x>`)** — from any note-listing
  picker or panel, highlighting a note and pressing `<C-v>` opens it in a
  vertical split to the right of the invocation window (the window that
  was current when the picker was opened); `<C-x>` opens it to the left.
  Direction-only, single keypress. New pure decision function
  `resolve_split_target()`, unit-tested in `test/test_v160_p4.lua`
  (8 cases): `left` unavailable when the invocation window was the sidebar
  or has since closed; `right` falls back to the rightmost real editing
  window if the invocation window is gone. New wrapper
  `open_relative_split()` performs the actual split via explicit
  `leftabove`/`rightbelow vsplit` (deterministic regardless of
  `'splitright'`). Guarded to note entries only everywhere — selecting a
  subview and pressing `<C-v>`/`<C-x>` is a no-op.
- **Curated `?` keymap help** — new shared `show_keymap_help(title, lines)`
  float, bound to `?` (normal mode only, so a literal `?` typed into a
  search prompt is unaffected) across every views.lua picker/panel:
  `telescope_view_picker`, `float_view_picker`, both modes of
  `telescope_views_tree_picker`, both modes of `_views_panel`. For the
  Telescope-backed pickers this *replaces* Telescope's own built-in `?`
  which-key float — which listed every custom `map()` binding as
  "anonymous", since none had a description — with one scoped to this
  plugin's actual keys. Every previously-crowded prompt-title/header
  collapsed to a single `? help` pointer, full list moved into the float.
  `sidebar_show_help` refactored onto the same shared helper.
- **Config**: new default `keymaps.focus_sidebar = "<C-,>"` — jumps focus
  directly to the sidebar window from anywhere, regardless of split
  layout, without stepping through intermediate windows.
- **Relative-split picker actions (`<C-v>`/`<C-x>`)** — from any note-listing
  picker or panel (`telescope_view_picker`, `float_view_picker`,
  `telescope_views_tree_picker`'s browse mode, and `_views_panel`'s browse
  mode), highlighting a note and pressing `<C-v>` opens it in a vertical
  split to the right of the *invocation window* (the window that was
  current when the picker was opened); `<C-x>` opens it to the left.
  Direction-only, single keypress — not a window-choice prompt.
  - New pure decision function `resolve_split_target(direction,
    invocation_was_sidebar, invocation_still_valid)` in `views.lua`,
    unit-tested in `test/test_v160_p4.lua`: `left` is unavailable when the
    invocation window was the sidebar (nothing to its left) or has since
    closed (no sensible fallback); `right` falls back to the rightmost
    real editing window if the invocation window is gone.
  - New wrapper `open_relative_split(direction, target_path,
    invocation_win, invocation_was_sidebar)` performs the actual
    `nvim_set_current_win` + explicit `leftabove`/`rightbelow vsplit`
    (never a bare `vsplit`, so behavior is deterministic regardless of
    `'splitright'`).
  - Guarded to note entries only in every picker/panel — selecting a
    subview and pressing `<C-v>`/`<C-x>` is a no-op, since a subview opens
    another picker, not a file.
  - `M.open()` and `M.open_views_panel()` both now capture the invocation
    window (and whether it was the sidebar) before dispatching to either
    backend, threading it through to whichever picker/panel opens.
  - `M._resolve_split_target` exposed for `test/test_v160_p4.lua` only.
- **Views panel** (`:PKMViews`) — `panel.create()`-based replacement for
  the old tree picker. `<CR>` opens a view, `n` creates one
  (`:PKMViewNew`), `u` opens the edit/rename/reparent action picker on the
  highlighted view (`:PKMViewUpdate`'s flow), `/` filters in place. No
  deletion key — that's the whole reason it's a separate panel.
- **`<Tab>` switches the views panel in place to "Browse All"** — every
  note, unscoped, substring-filtered — and back, without closing the
  panel and opening a different one. Same window, same buffer, `state.mode`
  toggled and re-rendered. Deliberately lighter than `:PKMBrowse`: no
  tag:/title:/text: field-prefix grammar, just substring match on title,
  filename, and tags. `:PKMBrowse` is unchanged and keeps its own fuller
  implementation; this is a same-surface convenience, not a replacement.
- **View-deletion panel** (`:PKMViewDelete` with no argument) — separate
  from the views panel by design. Browse → `<CR>` → `vim.fn.confirm()`
  (single keypress, matching the buffer panel's own existing
  close-with-unsaved-changes convention) → delete. Warns in the prompt if
  the view has subviews that reference it as parent, since `M.delete()`
  doesn't touch them (pre-existing limitation, not new — surfacing it
  here at least makes the consequence visible before it happens).
- **Optional sidebar key → views panel** (`config.keymaps.view_panel`,
  default `false`). Wired via a new `views.set_panel_keymap(lhs)`, called
  from `keymaps.lua` at registration time. Listed in the sidebar's `?`
  help when set.
- Two pure helpers, `sort_wins_by_col` and `resolve_window_slot`, backing
  both `N<CR>` and `<C-v>`'s window-targeting — extracted for testability
  per the Standing pure-logic-first design rule.
- `test/test_v160_p3.lua` — the two pure helpers in isolation; both
  panels' lifecycle, content, and no-destructive-key invariant; browse-mode
  rendering; a real (non-interactive) delete round-trip.

- **`panel.lua`** — generic panel infrastructure: per-tab state, scoped
  augroup (refresh-on-event, WinClosed→`ensure_main_window()` safety net,
  BufWipeout cleanup, TabClosed pruning), buffer-local keymaps, `winfixbuf`
  always on. `create(spec)` → `{ open, close, toggle, refresh, is_open,
  get_win }`. Deliberately does not unify header/statusline text or
  search/filter behavior across panels — those stay per-panel.
- **Tag panel** — searchable, scrollable replacement for the
  `vim.ui.select`/`vim.fn.input` flow behind `:PKMAddTag`/`:PKMRemoveTag`
  (bare, no-argument invocation only — the direct-argument fast path is
  unchanged). One-shot prompt-then-filter search via `/`, matching the
  existing convention used elsewhere in `ui.lua` rather than introducing
  live-per-keystroke filtering. Buffer-only mutation via the existing
  `citations.add_tag`/`remove_tag` — no `index.invalidate`, no changes to
  either function.

### Changed

- **`N<CR>` reconsidered: no auto-create on overflow.** The original Phase
  3 design ("`N` beyond the window count creates the next slot") was
  dropped in favor of the existing warn-and-stop behavior, kept
  deliberately rather than replaced. `N<CR>` is a high-frequency action;
  silently altering the window layout on a miscounted `N` is worse than a
  no-op with a message. Confirmed already correct as shipped — refactored
  onto the two new pure helpers for testability, no behavior change.
- **`<C-v>` fixed** — previously targeted the first non-panel window in
  creation order with a bare `vsplit` (side depended on `'splitright'`).
  Now deterministically targets the leftmost editing window and inserts
  `leftabove` of it, landing immediately right of the sidebar and
  shifting everything else right regardless of `'splitright'` — the
  insert-before complement to `N<CR>` the phase actually called for.
- `:PKMViews` and `:PKMViewDelete` (no-argument) now route through the
  new panels. `:PKMViewDelete <name>` (direct-argument fast path) now
  also confirms via `vim.fn.confirm()` — "deletion always confirmed"
  applies there too, not just to the panel. `focus_main_win()` dropped
  from `:PKMViews` (panels create their own split regardless of the
  current window's `winfixbuf` state, so it was never needed).
- Both `go_back()` callers in the detail-view pickers (Telescope and
  float) now return to the views panel instead of the removed tree
  picker — "browse all views" is one consistent UI regardless of entry
  point.
- **Buffer panel** ported onto `panel.lua` — behavior-preserving; stays
  unfocused on open (glanceable, not modal), matching its pre-port design.
  `ui.lua`'s module-level `_tabs`/`get_tab()` and the `PKMUITabs` augroup
  removed entirely — both panels now get per-tab isolation and TabClosed
  cleanup automatically from `panel.lua`.
- Renamed "search view" → "search panel" in the views tree picker's hint
  text, to avoid reading as a type of saved view.
- **Views tree picker no longer has a separate "search mode."** Search now
  happens inside an opened view instead of being a distinct entry point
  chosen upfront. For Telescope users this changes nothing observable —
  `M.open(name)`'s picker already filtered live as you type; the tree's
  `<C-f>` was fully redundant with it. For the float fallback, `/` inside
  an opened view now prompts and re-filters in place (matching the
  tag-panel/trash-panel convention), replacing what had briefly been a
  purely static, unfilterable "search" float — a regression introduced and
  caught within the same round of work, never shipped.
- **View listings sort case-insensitively, underscore-prefixed first** —
  `build_tree_entries()`, `get_view_children()`, and `M.list()` all switched
  from raw `table.sort()` to a `:lower()`-normalized comparator. Previously
  a mixed-case name (e.g. "Zebra") could sort before an underscore-prefixed
  one ("_meta") since '_' (0x5F) sits between uppercase and lowercase ASCII
  ranges — surprising given the `_meta`-subview convention (Design
  Questions decision 2) specifically wants underscore-prefixed views
  grouped first. Propagates automatically to every view listing (Telescope
  tree, panel.lua fallback, sidebar, all pickers), since all of them build
  on these three functions.
- **`reparent_view_prompt` orders candidate parents by subview count**
  (descending), tiebroken by the same case-insensitive order — a view with
  more existing children sorts first, since it's the more likely home for
  a new one.
- **`:PKMViewNew` subproject creation no longer requires typing "yes"** —
  confirmation removed entirely (not just lightened to a keypress):
  creating a view/subview is safe and trivially reversible, and
  confirmation stays reserved for genuinely dangerous actions (deletion),
  consistent with every other view-mutating flow in this file.

### Fixed (caught in review, before reaching a real session)
- A `filter = nil` table-constructor bug in `open_tag_panel` that would
  have let a stale filter silently survive a mode switch (Lua omits
  `nil`-valued keys from table literals entirely).
- A `restore_focus()` timing bug: closing the tag panel's `bufhidden=wipe`
  buffer fires `BufWipeout` synchronously, clearing its `_tabs` entry
  before `close()` returns — a bare `restore_focus()` re-deriving state at
  that point would silently no-op. Fixed by passing the keymap's own
  already-captured `state` reference explicitly.

### Test
- `test/test_v160_p1.lua` — panel.lua generic lifecycle, per-tab isolation,
  buffer-panel content correctness, tag-panel candidate-list correctness
  for both modes. Interactive select-and-mutate flow verified by manual
  smoke test, not automated (feedkeys-based simulation deemed not worth
  the fragility for this phase).

---

## [1.5.9] — 2026-7-10

### Added
- **`test/min_init.lua`** — the isolated headless-test harness referenced by
  the Standing Verification Protocol since before this version but never
  actually created. Self-locating (resolves repo root from its own path,
  independent of CWD); disables ShaDa entirely (`shadafile = 'NONE'`) to
  prevent `E138` from repeated rapid headless test runs; uses a disposable
  `vim.fn.tempname()` scratch root.

### Fixed

- **`((...))` meta-comments couldn't span multiple lines** — `PKMMetaComment`
  was implemented via `vim.fn.matchadd()`, which cannot match across line
  breaks under any pattern (a Vim/Neovim platform limitation, not a regex
  issue). Migrated to buffer-scoped `nvim_buf_set_extmark` (natively
  multi-line via `end_row`/`end_col`), with a pure-logic scanner
  (`find_meta_comments`) finding spans via Lua string patterns — whose `.`
  matches newline, unlike Vim regex — across the whole buffer. Rescanned on
  `enable()`, on save, and (debounced 150ms) on text change. A
  `MAX_META_COMMENT_LINES` cap (50) bounds how far a stray unmatched `((`
  can highlight before giving up, so a typo can't paint the rest of the
  document. `PKMCitation` (`note[0042]`-style) is unaffected — inherently
  single-line, `matchadd()` remains the right tool there.
  PKMMode-exclusive by decision, matching `PKMCitation`'s existing scope;
  `after/syntax/markdown.vim` (the non-PKMMode fallback) is untouched.
- **`:Ex`/`:Explore` from the sidebar or buffer panel silently hijacked the
  panel window** — `winfixbuf` blocks ordinary buffer switches but not
  netrw's initial takeover of an unmodified window; a `FileType netrw` guard
  in `keymaps.lua` (`PKMNetrwFixes`) now detects this via window-local
  option signature and reverts + reopens the panel, deferred via
  `vim.schedule` to avoid mutating the window while netrw's own command is
  still executing (an earlier synchronous version corrupted netrw's setup
  and intermittently reintroduced the buffer-panel sole-window bug as a
  side effect).

### Investigated, no change needed

- ATX/setext headers already correctly highlight across their full span
  under PKMMode — tree-sitter node spans were never subject to `matchadd()`'s
  single-line limitation, since headers were never implemented via matchadd
  in the first place. The original Phase 3 plan's hedge on this ("if
  multi-line headers cannot be highlighted reliably...") turned out to not
  apply; nothing was broken here to begin with.
- `queries/markdown/highlights.scm` unchanged — meta-comment highlighting
  was never tree-sitter-query-based.

---

## [1.5.8] — 2026-7-10

### Fixed

- **Panel buffer hijack (sidebar)** — `open_sidebar()` set `winfixwidth` but
  not `winfixbuf`; a stray `:Ex`, `:edit`, or similar invoked while the
  sidebar held focus could silently repoint its window at an unrelated
  buffer, corrupting the panel. `winfixbuf = true` now set alongside
  `winfixwidth`, converting that whole bug class into a loud, harmless
  error instead. Same fix already covers the buffer panel (`ui.lua`,
  v1.5.7-adjacent) and now the sidebar.
- **View creation never refreshed an already-open sidebar** — `M.save()`
  and `M.save_subproject()` wrote to `views.json` but never called
  `refresh_sidebar_if_open()`, so a newly created view didn't appear in an
  open sidebar until an unrelated refresh or manual `r`. Both now call it
  on success. (No focus-restore needed alongside this: nothing in the
  view-creation path — `:PKMViewNew`'s prompts, `save`, `save_subproject`,
  or `refresh_sidebar_if_open` itself — ever moves window focus, confirmed
  by tracing every call site in `commands.lua` and `views.lua`.)
- **Renaming a view could silently strand a `config.lua` subproject** — a
  subproject's `parent` field is only ever safely rewritable when it lives
  in `views.json`; `config.lua` is Lua source, not a data file, and the
  plugin cannot safely rewrite it. `rename_view_prompt` already propagated
  renames correctly across every `views.json` entry (unaffected — this was
  never actually a completeness gap in the sidecar, only against
  hand-written config); it now additionally warns (never blocks) if any
  `config.lua` subproject still references the old name. Enforced at a
  stronger level too: `M.setup()` now scans `config.projects` at startup
  and warns if it ever contains a `parent`-bearing entry at all, since
  under normal use it never should — subprojects belong exclusively in
  `views.json`, created via `:PKMViewNewSub`.
  Confirmed `reparent_view_prompt` needs no equivalent warning: reparenting
  changes a subproject's parent, never its own name, so nothing that could
  reference it by name is ever invalidated.
- **Buffer panel and sidebar help text under-documented live keymaps** —
  buffer panel's header line and statusline advertised only `<CR>`/`d`/`w`/
  `q`, omitting the live `D` (force-close, discards unsaved changes without
  the `d` confirm prompt), `r` (refresh), and `T` (filename/title toggle)
  bindings; now lists all six. Sidebar's statusline separately advertised
  `za fold`, a generic Vim fold command with no effect in the sidebar buffer
  (it sets no `foldmethod`) — removed as stale copy-paste from a note-buffer
  hint string.
- **Note/view-opening commands could open their target inside a PKM panel**
  — `:PKMTags`, `:PKMBrowseRecent`, `:PKMOrphans`, `:PKMView`, `:PKMViews`,
  `:PKMViewLast`, and `:PKMViewEdit` could, if invoked while focus was in
  the sidebar, buffer panel, or netrw, open their result inside that panel
  window instead of a normal editing window. All seven now call the
  existing `focus_main_win()` helper first, matching the coverage already
  present on `:PKMNewNote`/`:PKMNewJournal`/`:PKMNewScratchpad`/`:PKMImport`/
  `:PKMBrowse`. Audited but confirmed not applicable: commands that operate
  on "current buffer" (`:PKMRenameNote`, `:PKMConvertNote`, `:PKMPromote`,
  `:PKMTranspose`, `:PKMChangeType`) already self-guard via their own
  PKM-folder membership check; `:PKMViewSidebar` and `:PKMBuffers` open the
  panels themselves and already carry equivalent window-targeting logic in
  their own keymaps; `:PKMExportView` and `:PKMExport` never open a note
  buffer at all — traced the full `export.lua` call chain and confirmed
  every step (filter form, results picker, destination prompt, copy) uses
  only floating windows or pure file I/O, never `vim.cmd('edit ...')`.

### Known limitations (carried, not introduced this phase)

- `PKMLinkNote`, invoked from netrw specifically (not sidebar/bufpanel,
  which are nameless and already guarded), passes its empty-buffer-name
  check because netrw buffers are named after their directory. Whether
  this can actually corrupt the netrw listing depends on netrw's buffer
  modifiability, which wasn't verified empirically. Low-probability edge
  case; flagged, not fixed this phase.

---

## [1.5.7]  - 10/7/2026

### Fixed

- **Case-only rename blocked as a false collision** — `rename_note()`
  treated `filereadable(new)==1` as always meaning "target exists",
  rejecting renames that only change case (e.g. `prazos` → `Prazos`) on a
  case-insensitive filesystem even though the target was the same file.
  Added `is_same_file()` (device+inode identity via `vim.loop.fs_stat`) to
  distinguish a genuine collision from a case-only rename of the same
  object. A single `rename()` call is not reliable for case-only changes on
  every case-insensitive filesystem implementation, so the same-file path
  now stages the change through a temporary name (two-step rename) to force
  the new casing to actually land on disk, then rewrites the file with
  current buffer content so no unsaved edit is lost in the process.
- **E13-prone buffer redirect in `rename_note()`/`change_note_type()`** —
  both functions redirected the buffer to its new name via
  `vim.cmd('keepalt file ...')` after a disk-level rename/write. Replaced
  with `nvim_buf_set_name` + direct `writefile`, with the write always
  confirmed successful before the buffer is repointed — removing any Vim
  write command from the redirect path entirely, so an otherwise-unmodified
  rename or type change cannot trigger a forced-write prompt.
- **Citation metadata did not track title changes** — editing a note's
  `title` never propagated to the `title` field stored in other notes'
  `cites`/`cited_by` entries. Added `citations.propagate_title(note_path)`,
  called from the `BufWritePost` sync autocmd after `update_references`,
  idempotently rewriting only the entries whose stored title has drifted.

---

## [1.5.6] - 2026-6-21

### Fixed

- **Buffer panel `d` evicted a modified buffer's window before knowing the
  close would succeed** — `detach_buf_from_wins(bufnr)` ran unconditionally
  before attempting `bdelete`, so on a modified buffer the window switched
  away first and only then did `bdelete` (no `!`) fail, leaving the buffer
  open but no longer visible anywhere. Fix: `d` now checks `modified` first
  and prompts (`vim.fn.confirm`, Yes/No/Cancel) — Yes writes then closes
  normally, No force-closes and discards, Cancel/Esc leaves the buffer and
  its window untouched. Detach only happens once the outcome is settled.

- **Buffer panel `<CR>` split the panel's own window when no editing window
  existed** — the fallback path (`rightbelow vsplit`) operated on whatever
  window was current, which at that point is the panel's own buffer-local
  keymap context — producing a vertical sliver of the panel itself instead
  of a proper editing pane. Pre-existing latent bug, not a recent
  regression; only reachable when the last editing window is closed while
  the panel stays open. Fix: creates a real window above the panel first
  (same technique as `ensure_main_window`), then loads the buffer into it.

- **Buffer panel could still end up as the sole window** — `ensure_main_window()`
  was only invoked from the panel's own `d`/`D`/`w` keymaps, so closing the
  last editing window through any other means (`:q`, `:bd`, `<C-w>c` typed
  directly in it) left the panel alone on screen with no rebalancing. Fix:
  added a `WinClosed` autocmd in `toggle_bufpanel` that calls
  `ensure_main_window()` after any window closes in the tabpage, covering
  every path rather than just the panel's three keymaps.

- **BufWritePost reload left every PKM buffer permanently "modified," and
  the next `:w` after that warned the file had changed on disk** —
  regression introduced by the `nvim_buf_set_lines`-based reload fix above:
  unlike `:e`, `nvim_buf_set_lines` updates buffer content but neither
  clears `modified` nor refreshes Neovim's internal "file mtime as of last
  read" bookkeeping. Surfaced as: `:wqall` prompting on unmodified buffers,
  buffer panel `d` refusing to close without `!`, and a "file changed since
  reading it" warning on save → undo → save. Fix: added a quiet
  `noautocmd write!` immediately after the `nvim_buf_set_lines` reload —
  refreshes both `modified` and the mtime record as a side effect of a real
  (if content-redundant) write, without reintroducing `:e`'s fold-
  destruction or tree-sitter-detach side effects. Verified via headless
  Neovim test that `noautocmd write!` touches neither.

- **Automatic save edits created spurious undo steps** — `BufWritePre`'s
  `last_updated_on` injection and `BufWritePost`'s `noautocmd e` reload (after
  `update_references`) both mutated the buffer as ordinary, separately
  undoable changes, landing on top of the undo stack after the user's real
  edit. Fix: both call sites now `pcall(vim.cmd, 'undojoin')` immediately
  before their mutation, merging into the same undo block as the user's last
  edit. Tradeoff: `last_updated_on` is no longer independent of undo — it
  reverts together with the edit it stamps. True independence isn't
  achievable without either discarding buffer undo history entirely (the
  `'undolevels' = -1` trick does this — rejected) or moving metadata out of
  the buffer (against the in-file metadata commitment).

- **`cites`/`cited_by` sub-groups (`notes`/`bib`/`journal`/`scratch`)
  reordered on every save** — `generate_yaml`'s `key_order` only covered
  top-level keys; nested groups fell through to an unordered `pairs()` pass,
  whose iteration order is unspecified by Lua and varies across the freshly
  parsed tables rebuilt on every save. Fix: `generate_yaml` takes an optional
  `key_order` parameter; recursion into `cites`/`cited_by` now passes a fixed
  sub-order (`notes, bib, journal, scratch`).

- **`manage_backlink()` polluted undo in unrelated open buffers** — both
  branches (modified-target in-buffer apply, and unmodified-target silent
  disk-sync reload) mutated `target_bufnr` via raw `nvim_buf_set_lines`
  without `undojoin`, creating a separate undo step in a buffer the user
  wasn't even saving — triggered purely by citing/un-citing it from another
  note. Fix: both mutations now run inside
  `nvim_buf_call(target_bufnr, function() pcall(vim.cmd, 'undojoin'); ... end)`,
  merging into that buffer's own undo history. Same `undojoin`-over-`undolevels=-1`
  reasoning as the `init.lua` BufWritePre/BufWritePost fix above.

- **Citation entries (`identifier`/`title`/`link`) reordering on every save**
  — same root cause as the `cites`/`cited_by` group-ordering fix above, one
  level deeper: `generate_yaml`'s array-of-objects branch (Case 2) never
  passed a key order into its recursive call, so each citation entry table
  fell back to the top-level order (where `title` matched and always
  rendered first) with `identifier`/`link` falling through to unordered
  `pairs()`. Fix: new `citation_entry_order = {"identifier","title","link"}`
  passed into the Case 2 recursive `generate_yaml` call. Applies identically
  to `cited_by` entries — same code path, not a separate bug.

- **BufWritePost reload still produced a separate undo step despite
  `undojoin`** — confirmed via headless-Neovim testing that `:e` (file
  reload) does not honor a preceding `:undojoin` under any invocation; it
  unconditionally opens a fresh undo block. This was the actual cause of the
  "swap reverts, then timestamp reverts" two-press undo behavior. Fix:
  replaced `noautocmd e` with `pcall(vim.cmd,'undojoin')` +
  `nvim_buf_set_lines(written_buf, 0, -1, false, readfile(filepath))`, which
  *does* honor undojoin — confirmed via the same testing. Side effects
  verified safe: `nvim_buf_set_lines` (unlike `:e`) does not destroy manual
  folds and does not detach an active tree-sitter highlighter, so the
  existing fold-restore and TS-restart logic become harmless no-ops rather
  than newly-broken paths. Left in place as redundant defensive code rather
  than removed — out of scope for this fix.

---

## [1.5.5] - 2026-6-19

### Fixed

- **Custom markdown highlight/injection queries never merged with Neovim's
  bundled defaults** — both `queries/markdown/highlights.scm` and
  `queries/markdown/injections.scm` carried an `extends` modeline, but it
  was preceded by a descriptive file-path comment and a blank line. Per
  `:h treesitter-query-modeline-extends`, the modeline must sit at the
  literal top of the query file; ours didn't, so Neovim treated each file
  as a full *replacement* of the bundled query rather than an extension.
  Confirmed directly via `vim.treesitter.highlighter.active[bufnr]`: the
  resolved `markdown` highlights query contained only our own two captures
  (`pkm.indented`, `markup.list`) — none of the bundled heading, blockquote,
  link, or list-checkbox captures were present. This had been the case
  since both files were first written (Phase 4); it wasn't introduced by
  the recent performance work, it surfaced because that work was the first
  time live highlighter state got directly inspected. Fix: moved the
  modeline to the literal first line of both files, with the descriptive
  comment moved below it. Verified post-fix via the same live-state check:
  the resolved query now includes the full bundled capture set.

  Side effect: this also restored the bundled `markdown_inline` injection,
  which the same bug had been silently suppressing in `injections.scm` —
  see the performance entry above; `ensure_injection_override()` now needs
  to be active (not commented out) to keep that injection deliberately
  suppressed, rather than relying on this bug to do it by accident.

  Process note: two earlier attempts at this exact fix targeted the
  modeline's exact spelling (`;; extends` vs `; extends`) rather than its
  position, and made no measurable difference — confirmed both times via
  the same live introspection rather than visual inspection, which is what
  caught that the first two attempts hadn't actually changed anything.

---

## [1.5.4] - 2026-6-19

### Fixed

- **TS highlighter extmark out-of-range errors persisting after 1.5.3** — the
  1.5.3 fix made `parser:parse()` run synchronously in `TextChanged`/
  `TextChangedI`, but `parser:parse()` with no argument only guarantees the
  root `markdown` tree is reparsed; per `:h LanguageTree:parse()`, injected
  trees (`markdown_inline` for header/paragraph content, `yaml` for
  frontmatter) are only reparsed if the given range intersects them. Since no
  range was given, every inline injection kept its pre-edit tree, so any edit
  that shifted rows left stale extmark positions in headers and paragraph
  text — exactly the cases reported (near headers, multi-line text, second
  headers; not reproducible when nothing followed the header but blank
  lines). Fix: `parser:parse()` → `parser:parse(true)`, forcing all regions
  (root + injections) to reparse on every change.

### Decisions
- **Markdown indentation: 4 spaces, unchanged.** Tested against CommonMark's
  content-alignment rule and behavior across GitHub, GitLab, Bitbucket,
  Pandoc, Reddit, VS Code, and Obsidian: 4 spaces is the only width that
  renders nested lists correctly everywhere. 2-space breaks on Bitbucket,
  Pandoc, and Reddit; 3-space breaks on GitLab, Bitbucket, Pandoc, and
  Reddit. Personal usage (not config) should match — see below.

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

- **Frontmatter fold closes on save (regression)** — removing `vim.schedule`
  from the `TextChanged`/`TextChangedI` callback (the extmark out-of-range
  fix) made `parser:parse()` run synchronously during `BufWritePre`. This
  triggered an immediate `foldmethod=expr` re-evaluation with `foldlevel=0`,
  closing the frontmatter fold before `BufWritePost` could save its open
  state. The saved state was then `was_open = false`, preventing restoration.
  Fix: fold states are now captured at the very start of `BufWritePre`,
  before any buffer modification, and stored in `_pre_write_fold_states[buf]`.
  `BufWritePost` reads and clears this entry instead of re-sampling fold state
  mid-sequence. Falls back to mid-sequence sampling when PKM mode was inactive
  at write time.

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
