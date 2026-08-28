# PKM.nvim — LLM Session Context

Read this first. It is the fast-read brief. Read `doc/ARCHITECTURE.md` for the
architecture reference (layout, module responsibilities, config shape).
Read `doc/PHILOSOPHY.md` before proposing features or design changes. Its principles
are non-negotiable constraints on all architectural decisions.

---

## Current version: **v1.83.1** — (**v1.83.1**, headless-verified 27/8/2026; panel feel rides author smoke) **views-panel count cache (perf; Phase 1 of 3)**: the views panel (`<leader>va` → view tree) recomputed **every** view's match count on **every** open — an O(views × notes) `filter.eval` scan run synchronously each time (felt as reopen lag, from `temp/improvements.md`). NEW **`index.generation()`** — a monotonic content-generation counter bumped on every `_index` mutation that can change a result (full build, background-build finish, each `invalidate`); pure reads (`get_all`/`get`) never bump it. **`views.count_many` is now memoized keyed by that generation**: first call at a corpus state pays the scan once, every later call at the same generation returns cached numbers with no index touch; missing names are computed and merged so mixed callers stay correct. Cache clears two ways — a note change advances the generation (stale key → recompute), a view-definition change clears it via `views.invalidate` (`_count_cache = nil`, beside `_sidecar_cache`/`_tree_cache`). **No new `index.invalidate` call — the bump lives INSIDE `invalidate`, so the buffer-only-metadata invariant holds.** `test_v1831_p1` (14 checks: generation monotonicity + read-stability, count correctness vs `count_all`, invalidation by note-change and by new view). Suite green; `test_v161_p3`'s "no stale caching" case stays green (the generation bump on `invalidate` is what keeps it correct). Implements the **reopen** half of the CHANGELOG Views_suite caching decision; the cold first compute is unchanged. **Phases 2–3 deferred (ROADMAP § Views-panel open latency):** async/chunked count fill for an instant *first* open (Ph2), inverted tag index for O(matched) cold recompute (Ph3, gate on a bench baseline). Also captured: **views tree expand/collapse** feature (ROADMAP). **Doc-drift fixed 27/8:** ROADMAP had frozen at v1.63.1 while code reached v1.83.0 — Current State, Shipped so far, pending-features status reconciled through v1.83.1; the 2026-08-19 gestor audit triaged (D1/D4/D7 open; D2/D6 shipped in v1.80.0). (**v1.83.0**, author-smoke confirmed + tagged 20/8/2026) insert-mode **`<C-j>` list continuation extended to unordered families + cursor fix for every ordered family**: `plan_list_continuation` (pkm-markdown `a8dd776`) now continues plain bullets (`-`/`*`/`+`, marker repeated) and GFM task items (`- [ ]`/`* [x]` → fresh **unchecked** `- [ ] `) as well as the ordered families, tagging each plan `ordered=true|false` so `list_newline` skips the cascade renumber for the unordered ones; and `list_newline`'s final cursor placement, which used an arabic-only regex (`^%s*%d+[.)] `) and dropped the cursor to column 0 for roman/alpha/inciso, now measures the rewritten line minus the unchanged tail (correct for every marker width — a lone `i.` continues as `ii.` with the cursor after it). Lockstep pkm-markdown. **Known limitation (deferred, CHANGELOG Known Bugs):** a roman/alpha subitem NESTED under a different-family parent in the same paragraph isn't renumbered (single-family `renumber_sequence`); standalone/same-family lists (the smoked case) are correct. (**v1.82.0**, headless-verified 19/8/2026, **interactive `:PKMView add` picker awaits author smoke before tag**) **membership WRITES use a view's OWN filter, not the containment roll-up**: fixes the 2026-08-19 gestor `_meta` fallout — `:PKMView add <container>` (+ `new_note_in_view`, `api.set_membership`) offered the CHILDREN's tags (or refused "several ways") because it resolved "add to `_meta`" from `get_tree` (own OR union(descendants)); the three write paths (`views.set_membership`, `tags.view_flow`, `tags.new_note_in_view`) now resolve against new **`views.get_own_tree(name)`** (own filter, no child composition; shared `resolve_own_expr`), while reads/counts keep composing downward — a parent still CONTAINS its children for viewing, but add/remove/new-note writes that view's DIRECT membership. `test_v1820_p1` (15 checks), suite **105/105**. **Prevention:** `skills/pkm-notes/SKILL.md` View/tag model rewritten from the stale `parent AND child` "subset" text (which drove the gestor to hand-OR child tags into the parent) to CONTAINMENT + "never hand-edit the parent's own filter; use reparent/save_subproject; give a pure container its own identity tag" (installed copy synced). **Vault 01 data fix (via pkm.api, backup first):** `_meta` own filter `concursos-_meta OR guia-estudos OR editais` → `tag:"concursos-_meta"`; `Disciplinas` ~20-tag OR-union → `tag:"concursos-disciplina"` (clean container marker); containment rolls children up (`_meta` 24, `Disciplinas` 136), hierarchy intact. (**v1.81.0**, headless-verified 19/8/2026, **interactive reparent picker awaits author smoke before tag**) **nested views become CONTAINMENT, not intersection**: on the author's call, a subview no longer *narrows* its parent (old `parent AND child`, which emptied a child whose notes didn't also satisfy the parent — the v1.80.0 warning's root cause), it *belongs to* it. New model: a view = **own filter OR union of its descendants**; a subview matches its own filter (independent of parent), and a **parent CONTAINS its children**. So nesting/reparenting never narrows or empties a view — the manual OR-union supersets the gestor built by hand (`_meta`/`Disciplinas`) are now automatic. `views.get_tree` composes **downward** (own OR children; per-branch ancestor/depth guard; malformed child skipped). The v1.80.0 empty-composition **warning is REMOVED** (obsolete by construction — `save_subproject`/`reparent`/`api.*` return `{ok}`, `composition_warning` deleted). Also: the **reparent candidate picker → Telescope `pick_list` UI** (with counts; `vim.ui.select` fallback), addressing the ">3-4 options → real UI" directive (the 2-3 option action menu stays `vim.ui.select`). BREAKING for nested-view *results*, but backward-compatible with vault 01 (manual supersets still resolve, just redundant). Suite **104/104** (test_v1800_p1/p2 rewritten to containment; test_v161_p3's 2 composition assertions updated). Kept from v1.80.0: `api.rename_view`/`reparent_view`/`delete_view` (D2), save_subproject mixed-filter guard (D5), tree-shaped `structure()`/`views.tree()` (D6). (**v1.80.0**, headless-verified 19/8/2026, **interactive reparent picker awaits author smoke before tag**) **view-lifecycle API + silent-empty-composition guard**: closes the dev findings from the 2026-08-19 vault-`01` gestor reorg (`temp/pkm-gestor-audit-2026-08-19.md`). NEW headless API — **`api.rename_view`** (re-points children, so a subtree renames without orphaning — replaces the child-orphaning delete-old+save-new), **`api.reparent_view`** (explicit "change parent" with the cycle guard; over a new pure `views.reparent`), **`api.delete_view`** (D2). **D1 [P1] fix**: a subview AND-composes its parent, so reparenting a child under a parent that excludes it silently emptied the view (`Guias` 21→0); `views.save_subproject`/`reparent` now compute a non-blocking **`warning`** (own-filter matches >0 but composed matches 0), surfaced as `{ ok=true, warning }` (pure `composition_warning`). **D6**: `api.structure()` now returns the view **tree** — each row carries `depth`/`parent`/`has_children` (new public `views.tree()`). **D5 fix**: `save_subproject` now runs the `mixes_field_and_any` filter guard `save` already had. **D4 (container view type) deferred** → ROADMAP; **D7 (audit flags frontmatter-less journals) is NOT a plugin bug** — journals ARE created with frontmatter (`journal.lua`→`create_frontmatter`), so the flags are real. The interactive `reparent_view_prompt` picker now delegates to the tested `views.reparent` (behavior-preserving + the new warning notify). Suite **103/103** (`test_v1800_p1`). (**v1.79.0**, smoke-confirmed + tagged 17/8/2026) **relative-level header navigation**: two-axis key model — DIRECTION bracket (`[` back / `]` fwd) × LEVEL letter (`u` shallower / `l` deeper), digit N = exact level DELTA. All 4 explicit `<dir><level>N`: `[uN`=shallower-back (ancestor), `]lN`=deeper-fwd (descendant), `[lN`=deeper-back (descendant behind), `]uN`=shallower-fwd (ancestor-level ahead). Bare shortcuts `[N`=`[uN` (`[1`=parent,`[2`=grandparent), `]N`=`]lN` (`]1`=child,`]3`=level-6 ahead). Exact `enclosing±N`; out of 1..6 → no move; above all → any. Digit-in-key (not Vim count) deliberate. `[`/`]` not `#N` (no latency). Pure core `find_heading_target(…, {dir, level_delta=signed})` in **pkm-markdown** (`e254ddf`; dir & level_delta INDEPENDENT — all combos free), keymap = built from the axes into 6 prefixes × N=1..6 (36 maps) in pkm-nvim `keymaps.lua` (config `header_prev_key`/`header_next_key`/`header_shallower_key`/`header_deeper_key`/`header_level_jump_bare`). All key work here is pkm-nvim-ONLY (pkm-markdown unchanged since e254ddf). (Iterated this session: `level_rel` `d1cb987` → 4-motion ordinal `073dda2` → literal `[N`/`]N` `9595840` → +crossed `a698687` → +symmetric explicit `[u`/`]l`.) From `temp/adicionar-roadmap.md` batch item 3; item 2 was already v1.78.0's `<C-j>` split, and item 1 (the inciso highlight) is **intended, not a bug** — a standalone roman `C -` at line start highlights by design (G9 stays closed). On a line like `1. 2. a`, tree-sitter parses `2. a` as a nested ordered list so **both** `1.` and `2.` markers paint — the author re-raised this 17/8 and, after the mechanism was shown, **reaffirmed G8 as won't-fix** (correct CommonMark; overriding it would fight the parser). No change. — the **2026-08-12 vault-gestor batch (G1–G12), complete + smoke-confirmed (13/8/2026).** (**v1.78.0**) ordered-list continuation moved to **`<C-j>`** (Ctrl-J), plain **`<CR>` = newline** — the earlier `<S-CR>` never reached Neovim (the author's terminal collapses Shift+Enter to `<CR>` in the byte stream), and `<C-j>` is a real LF every terminal delivers; lockstep pkm-markdown `attach` + pkm-nvim `mode.enable_note_buffer`, `list_newline`/`plan_list_continuation` unchanged. (**v1.77.0**) **`<C-t>` note-type cycle in the view pop-up pickers** (`telescope_view_picker` + `float_view_picker`, `<leader>va` → view): all→note→agg→bib→journal→scratch on top of the prompt, a specific type hides subview rows; the sidebar detail mode / browse `live_picker` / note picker already had it, so `TYPE_CYCLE` was promoted to a module-level const in `views.lua` (+ pure `type_passes`/`next_type_idx`) and the sidebar's local deduped. (**v1.76.0**, pkm-syntax sibling) **block-aware inciso highlight**: moved off the per-line `matchadd` to a buffer-scoped extmark scan (`find_inciso_markers`/`refresh_inciso_markers`, ns `pkm_inciso`) that paints a same-indent ` - ` marker run only when EVERY marker is a canonical roman numeral — so an uppercase-alpha `A -/B -/C -/D -` list no longer mis-paints its C/D/I items; `inciso_list_pattern` kept as the test-pinned single-line spec (`test/test_v1760_p1.lua`). (**v1.75.0**) the pkm-nvim half of the batch: quote-aware `args.lua` (`regroup_quoted` — `:PKMView rename` on spaced names, and every spaced-arg command), present-tag-aware `views.set_membership` (unique-cheapest residual vs the note's current tags; no destructive guess on ties), `api.save_view`/`structure`/`tag_catalog`/`emit`, a non-blocking mixed field+`any` filter warning in `views.save`, CONVENTIONS § Tags, settings-hygiene. **G8 closed won't-fix** — `2. 2. text` is correct CommonMark (the second `2.` is a genuine nested `list_marker_dot`; pkm-syntax `highlights.scm:14` paints markers at every depth by design), and the doubled prefix that produced it was the continuation bug, already fixed. **Git policy (author's CLAUDE.md, 13/8):** commit + push are the agent's by default for the three suite repos (`git -C "<repo>"`); **tag + merge need an explicit instruction**; never `--force`, never commit to `main`. Suite **102/102**. (**v1.74.0**) `pkm_mode.syntax.highlight_all_markdown` now defaults to `true`: pkm-nvim ships pkm-syntax + pkm-markdown as dependencies, so **every** markdown buffer (not just vault notes) gets their treatment out of the box — highlight + the editing utilities (`gq`/`gw` wrap via `formatexpr`, ordered-list `<CR>` continuation). PKM notes are unchanged (full note behaviour via the `open_note` trigger; the FileType path skips them); a plain markdown buffer still gets only highlight + edit, not the note behaviour (fold/window opts). Set `highlight_all_markdown = false` to leave non-vault markdown untouched. Only the default flipped — the FileType-autocmd mechanism (`mode.lua`, guarded by `pkm_markdown_attached`) is unchanged. The flip made `min_init`'s own `setup()` register the global autocmd, so `test_v1420_p1`/`test_v1471_p1` now `syntax.disable` to establish a clean baseline before the enable each verifies; `test_v1420_p1` asserts the new default. Suite **101/101**. (**v1.73.0**) insert-mode `<CR>` list continuation now covers **all** ordered families, not just arabic: `pkm-markdown.plan_list_continuation` detects the same families `renumber_sequence` does, in the same order (arabic → legal-inciso `I -` → subalínea `i.` [validated roman] → alpha `a)`/`a.`); the new item carries a same-family marker and the cascade renumber assigns the ordinal. Lockstep pkm-markdown change (`gq`/`gw` already handled every family). test_list_continue +7. (**v1.72.1**) `highlight_all_markdown` now also drives pkm-**markdown** editing, not only pkm-syntax highlight — `mode.enable_plain_markdown` calls `require('pkm.markdown').attach(bufnr)` beside `pkm.syntax.enable`, fixing the v1.72.0 Percurso B smoke where non-vault markdown highlighted but had no `gq`/`<CR>`. (**v1.72.0**) **markdown editing extracted to the standalone `pkm-markdown` sibling** (Backlog Item 2 / Phase 7, the last backlog item): `lua/pkm/markdown.lua` is now a thin **lazy facade** (1267→61 lines) re-exporting `require('pkm-markdown')`, mirroring `pkm.syntax`; the 1267-line body moved **byte-for-byte** to `pkm-markdown/lua/pkm-markdown/init.lua`. pkm-nvim now depends on **TWO** siblings — pkm-syntax (highlighting) + pkm-markdown (editing) — both prepended to the runtimepath by `test/min_init.lua` (relative sibling resolution). `pkm-markdown` gained a standalone `setup(opts)`/`attach(bufnr,opts)` (a `FileType markdown` autocmd wiring `formatexpr` + the ordered-list `<CR>`, idempotent via buffer-local `pkm_markdown_attached`, which `mode.enable_note_buffer` now also sets so the two never double-wire a note buffer). **Fixed a `formatexpr` regression the split exposed:** Neovim's `v:lua.require('mod').field` does a **raw** field lookup that ignores `__index`, so the facade's pure-proxy was invisible to the `v:lua`-wired `formatexpr` and `gq`/`gw` silently fell back to internal wrap — `formatexpr` is now a **real key** on the facade (the only `v:lua`-invoked export). Suite **101/101**. (**v1.65.0**) `tag:` now narrows incrementally in the live SEARCH pickers: `filter.eval(tree, note, opts)` gained `opts.tag_substring`, which relaxes ONLY `tag:` to a contiguous substring (plain `find`, never fuzzy — `tag:rpg` never matches `glorious-parmeggiano`), so `tag:rp` matches `rpg`/`my-rpg` as you type instead of the list vanishing until the tag is complete. Passed by the live pickers only (`:PKMBrowse`, view note-lists, `<C-f>` Browse-All, `vim.ui.select` fallback); saved-view eval (`match_all`/`count_*`/`match_set`) and `tag_sets` keep `tag:` EXACT, so a view `tag:rpg` still means exactly `rpg` and `:PKMView remove` still knows the one tag to strip. test_filter.lua 171/171. (**v1.64.1**) filter grammar now tolerates a space after a field colon: `tag: rpg` / `text: forge` parse as the field predicate, not only the glued `tag:rpg`. The tokenizer skips whitespace after a known field's colon and takes the next quoted string or bare word as the value; fix is in `pkm.filter` so it lands on every surface (browse, view note-lists, sidebar `/`, views.json exprs). Found in the v1.64.0 smoke — the reflexive space made `filter.parse` fail and the live pickers fell back to a literal any-search that matched nothing. `tag:` with nothing after is still an error. test_filter.lua 161/161. (**v1.64.0**) descriptor search everywhere a note list is shown: the view note-lists (`telescope_view_picker` + float `float_view_picker`) and the `<C-f>` "Browse All Notes" (`telescope_views_tree_picker` browse-mode) now run the prompt through `filter.lua` (`tag:`/`text:`/`title:`/`filename:`/`type:` + AND/OR/NOT, bare word = any-field), the same language `:PKMBrowse` uses — they previously matched the display string (title/filename) only. New pure `filter.parse_prompt` unifies the lenient live-parse rule (empty→nil, parseable→AST, partial→any-pred); `telescope.live_picker` de-dup'd to call it. Subview rows still narrow by name; the pop-up's `views`/`nav` providers (view names / headings) are unchanged by design. test_filter.lua 147/147 (+12 parse_prompt). (**v1.63.1**) doc/path fix: the reference tree is **`P:\Resources`** (WSL `/mnt/p/Resources`), NOT `Recursos` — corrected across the skill, AGENT_PROTOCOL §6.2/§10, CONVENTIONS, both CLAUDE.md files, and this file; the installed `~/.claude/skills/pkm-notes` copy + memory were fixed too (re-run `:PKMAgentProtocol install` to keep the distributed bundle in sync). (**v1.63.0**) command surface sorted onto the **persistent-vs-transient axis** (BREAKING): the transient view pop-ups moved to `:PKMBrowse views [name|last]`, the persistent sidebar has ONE door `:PKMPanel sidebar`, and `:PKMView` is view-**data** ops only (new/update/edit/delete/rename/export/add/remove); default keymaps re-pointed (same keys: `<leader>ps`→`:PKMPanel sidebar`, `<leader>va`→`:PKMBrowse views`, `<leader>vl`→`:PKMBrowse views last`). test_v1630_p1. (**v1.62.0**) `<C-t>` note-type filter built into the browse picker (`telescope.live_picker`): cycles all/note/agg/bib/journal/scratch on top of the prompt, works in `:PKMBrowse`/view-lists/the pop-up, overrides Telescope's `<C-t>`=select_tab; also neutralised the stray `<C-l>`=complete_tag error. (**v1.61.3**) sidebar CONTAINER extracted onto `lua/pkm/sidebar.lua` (views+nav are providers, `views.lua` re-exports the API; behavior-preserving). (**v1.61.2**) forced-save fix — a citation into an open *unmodified* buffer now writes the backlink THROUGH the buffer, killing the phantom W12 `:w` prompt. (**v1.61.1**) docs — roadmap reorg to its charter + `body_lower` index-shape doc fix. (**v1.61.0**) perf: background (chunked) index warm-up so the first sidebar/pop-up/browse open isn't the cold synchronous build. `index.start_background_build()` gathers the file list up front and reads in idle `vim.defer_fn` slices (400/slice); kicked ~200ms after setup, gated by `pkm_mode.index.prebuild`; a panel opened mid-build finishes the remainder synchronously (`ensure_built`), never partial. Benchmark-driven (build ~0.15ms/note dominates; reads 49% + mtime 39%; primitives already optimal). test_v161_p1/p2. (v1.60.1 was docs-only) — ARCHITECTURE.md refreshed (added api/check/args/nav/popup/skill modules + PKM_API/AGENT_PROTOCOL/PRINCIPLES to the doc tree; v1.60 keymap-axes + panel.cycle_focus notes), PRINCIPLES.md records the smoke-note placement, ROADMAP reconciled the "Fix now" wrapped-`N.` highlight item (a pkm-syntax concern now), config.lua tag-comment nit fixed. Also pruned 5 codified/resolved memories. (v1.60.0) — the queued UX evals: default keymaps redesigned on a **persistent-vs-transient** line — CONTENT verbs `<leader>n/c/f/v/M`; `<leader>p` = the PERSISTENT panels only (sidebar `ps`, buffers `pb`); transient pickers live under their verb, so the cyclable pop-up is `<leader>fp` (find), not a pane; `<C-Tab>`/`<C-S-Tab>` cycle the persistent panes. BREAKING for default keymaps, config keys unchanged. `:PKMView update` no-arg now opens a picker-panel (reuses the deletion-panel tree). No new command (native `:help pkm-keymaps` + `:nmap`). (v1.59.0 was Workstream E: the doc revision.) `doc/pkm.txt` WORKFLOW+COMMANDS rewritten by-context to the ~15-command verb surface (stale since v1.14.0), new Vaults/Utilities/pkm.api sections + real help tags; ROADMAP Working-features list + LLM_PROJECT_INSTRUCTIONS suite/pkm.api note updated; documentation debt cleared. Docs only. **This closes the post-Area-3 consolidation batch (A–E).** (v1.58.0 = Workstream A, suite move; v1.57.0 = Workstream B, Resources + note conventions.)

*v1.56.0 (3.5b slice 2): **`pkm.popup`** — ONE pop-up hosting the three providers (browse=all notes,
views=view names, nav=headings), cycled with `<C-l>` (Telescope only; `vim.ui.select` fallback omits
it). `popup.open(provider)`; `<C-l>` re-opens on the next in browse→views→nav. STANDALONE semantics
complete the origin rule: selecting does the provider-native action and NEVER drives the sidebar —
browse opens the note, views ACTIVATES (M.open, via new `views.popup_search`), nav jumps. The
sidebar's own `/` (which DOES drive the sidebar) stays separate. `keymaps.nav_search` opens this
cyclable pop-up on nav. `pick_list`/`browse`/`browse_paths`/`live_picker` gained optional `on_cycle`
(additive; `:PKMBrowse` + sidebar `/` unchanged). `test_v1560`. CLOSES Phase 3.5.*

*v1.55.0 (3.5b slice 1): `nav.search()` = fuzzy headings pop-up (pick_list; jump on select). It is
the nav provider's `/` (replaced the in-panel filter + `c` clear) and reachable standalone via
`keymaps.nav_search`. test_v1550; test_v1510 updated (nav keys now all shared with views).*

*v1.54.0: buffer panel gains `[count]<CR>` (open in the Nth editing window; reuses
`_sort_wins_by_col`/`_resolve_window_slot`) and `/` (fuzzy pop-up over open buffers via pick_list).
New ui.lua helpers collect_listed_bufs/open_buffer/open_buffer_in_slot/bufpanel_search. test_v1540.*

*v1.53.1 (smoke fixes): AUTOSWITCH IS NOW LIVE (removed the transition-seeding — `_autoswitch_last`/
`seed_autoswitch_context`/`tab_has_markdown` gone). It shows the provider the focused editing window
asks for (nav for markdown, views otherwise); a manual `<C-n>` cycle is a TRANSIENT PEEK that holds
while you stay in the sidebar and reverts on refocusing an editing window; pin via `:PKMPanel
autoswitch off`. Opening the sidebar (no-name) is context-driven. Nav header shows the vault only if
it FITS the sidebar width. test_v1520 updated; test_v190_p2 pins autoswitch off.*

*v1.53.0 (Area 3 Phase 3.5a): content-consistent `/` — views overview `/` searches VIEWS (a
`pick_list` of view names); launched from the sidebar so choosing one switches THIS sidebar to it.
New `pkm.telescope.pick_list` / `pkm.ui.pick_list` primitive. `sidebar_search()` backs the `/`. KEY
MODEL: pop-up & sidebar are SEPARATE; the pop-up drives the sidebar only when opened from it.*


*v1.52.0 (Area 3 Phase 3.3b): the sidebar AUTOSWITCHES between its providers by focus. On by
default (`config.sidebar_autoswitch`, `:PKMPanel autoswitch [on|off|toggle]`, `views.set_autoswitch`).
Shows `nav` when the focused window holds a MARKDOWN file, `views` when no window holds a
markdown file. Acts only on a CONTEXT TRANSITION (nav-worthy ↔ no-file) tracked per-tab in
`_autoswitch_last`, so a manual `<C-n>` cycle or explicit `:PKMPanel nav|sidebar` STICKS until
the context changes (explicit opens/cycles call `seed_autoswitch_context` to mark the context
handled). Driven by `views.autoswitch_tick()`, scheduled from nav's WinEnter/BufWinEnter
tracker. `<leader>s` (focus_sidebar) opens context-appropriately (nav from a markdown window,
else views). Helpers `win_is_markdown`/`tab_has_markdown`/`autoswitch_desired` are forward-
declared in views' State section (the provider/open fns above the autoswitch section reference
them). FIX: nav header glyph `▚`(U+259A, obscure)→`≡`(U+2261, the winbar's outline glyph).
`test_v1520`. Suite 82/0. Area 3 container/content arc (3.1→3.3b) COMPLETE; 3.4 deferred
(journal/scratch nav, block-element indexing, nav-in-popup). A `pkm.sidebar` extraction of the
container host out of views.lua remains a later mechanical tidy.*


*v1.51.0 (Area 3 Phase 3.3a): the sidebar is now a container hosting content PROVIDERS,
switched in place. Corrects Phase 3.1's mistake (`:PKMPanel nav` opened nav in its OWN 2nd
split). nav is now a provider on the ONE sidebar. A provider = `{ name, label, statusline,
build_lines, apply|keymaps, init?, on_enter? }`. The panel's build_lines DISPATCHES to
`_sidebar_providers[state.provider].build_lines`; `state.provider` rides the per-tab table.
SWITCHING swaps the buffer's keymaps in place (teardown by lhs → apply new) + re-dispatches
build_lines — no close/reopen (so 3.3b autoswitch won't flicker). Common keys q/`<Esc>`
(close) + `<C-n>` (cycle) survive every swap; views' full keymap set moved verbatim into
`apply_views_keymaps`. nav.lua no longer owns a panel — exposes `sidebar_provider`, registers
via `views.register_sidebar_provider` in nav.setup, source-tracking refreshes the sidebar only
while showing nav. New views API: show_sidebar_provider/cycle_sidebar_provider/
set_sidebar_provider/sidebar_provider/sidebar_provider_is/register_sidebar_provider.
`:PKMPanel nav`→show_sidebar_provider('nav'); `:PKMPanel sidebar`→views. Container ownership
stays in views.lua for now (a pkm.sidebar extraction is a later tidy). `test_v1510` proves the
keymap swap via the buffer's keymap table; `test_v1480` integration rewritten to the provider
model. Suite 81/0. NEXT = Phase 3.3b: autoswitch (sidebar→nav when the focused window holds a
MARKDOWN file, →views when no file window; ON by default, `:PKMPanel autoswitch` toggles).*


*v1.50.0 (near-patch, 4 author notes): (1) `<leader>s` → `views.focus_sidebar()` is now a TOGGLE — records the come-from window (panel `prev_win`) + jumps in; from inside jumps back; opens if closed. (2) Panel winbars show the suppressed note NUMBER: shared `utils.winbar_label(entry,path)` = `title · filename(with number)`; sidebar winbar uses it (number even in title mode); buffer panel GAINS a winbar (set on WinEnter/CursorMoved, cleared on WinLeave so the glanceable unfocused panel keeps full height); winbar is per-window so it never touches the active editing window. (3) `<C-g>` in sidebar+bufpanel echoes the full path. (4) nav panel header shows the vault (like sidebar/bufpanel). FIX: opening the sidebar no longer builds the overview TWICE (v1.49.0 ran panel.open's build + a switch re-entry just for the cursor → doubled count_many; now cursor placed inline; test asserts count_many runs once). The remaining cold-first-open cost is the synchronous index build (get_all builds on first access; prebuild is on PKMMode activate) — durable fix is the deferred persistent/mtime-cache index. `test_v1500_p1`. Suite 80/0.*


*v1.49.0 (Area 3 Phase 3.2): the views sidebar was extracted onto the generic `pkm.panel`
container, behavior-preserving. `panel.create` grew four seams: `spec.width` (number/thunk —
fixes width at open, `wincmd =` to re-equalise siblings, re-asserts on `WinResized`),
`spec.on_open(state, helpers)` (per-panel decoration seam: statusline/winbar/extra
autocmds), `panel.refresh_all()` (repopulate the panel in every tabpage from each tab's own
state), `panel.get_state()` (live per-tab state while open, nil while closed) — all additive,
buffer/tag/nav panels untouched. The sidebar is now `panel.create({name='sidebar', width=…,
focus_on_open=true})`; content is one `sidebar_build(state)` dispatcher; its whole keymap +
statusline + winbar surface moved VERBATIM into `on_open`. `views` no longer has its own
`_tabs`/`get_tab` (now `get_tab` → `_panel.get_state()`) nor the `TabClosed`/`WinResized`
autocmds (panel owns them). Public API unchanged (`open_sidebar`/`is_sidebar_open`/
`get_sidebar_win`/`get_last_view`/`refresh_sidebar_if_open`/`set_panel_keymap`). Two
intentional consistency micro-changes: `<Esc>` now closes (like `q`); panel `WinClosed` net
keeps a main window alive. `test_v1490`; existing sidebar tests (`test_v180_p6` marks,
`test_v1200_p1` ui_state, `test_v190_p2` filetype) are the regression gate, all green.
Suite 79/0. NEXT: 3.3 provider cycling + sidebar-default-nav (one container switches between
views and nav providers). Interactive-only bits ride the manual smoke.*


*v1.48.0 opens Area 3 (containers + nav). `lua/pkm/nav.lua` + `:PKMPanel nav`: a side
panel of the focused note's ATX headings (via `markdown.scan_headings`, fence/frontmatter
aware), level-indented + title header; `<CR>` jumps the source window, `/` filters (`c`
clear, `r` refresh). Follows the active note (WinEnter/BufWinEnter tracker from
`nav.setup`, wired in init.lua). Built ENTIRELY on `panel.create` — the first new content
provider on the generic container factory, no views.lua touched (Phase 3.1). Optional
`keymaps.nav_panel` (default false). NEXT: 3.2 extract the sidebar container from views.lua
(behavior-preserving, smoke-gated), then 3.3 provider cycling + sidebar-default-nav.
`test_v1480`; audit test_v1130_p8 gained the `nav` verb. Suite 77/0.*


*v1.47.1 (author smoke follow-up): `highlight_all_markdown` now also enables markdown
buffers ALREADY OPEN when setup ran (FileType doesn't re-fire for them — a reload, or a
file whose FileType fired before pkm-nvim loaded); `mode.setup` loops loaded markdown
bufs and enables them (highlight-only, skipping PKM notes), mirroring pkm-syntax.setup().
This was the real cause of "highlighting off by default" for the author. test_v1471. 76/0.*


*v1.47.0 (Area 4 syntax control): `:PKMSyntax [on|off|toggle]` (bare=toggle) — manual
highlighting control on the current buffer, independent of PKM mode /
`highlight_all_markdown` (vault note → full look; other markdown → highlight_only).
`pkm-syntax.is_active(bufnr)` added (lockstep). The `pkm.syntax` **facade now resolves
lazily** — it cached a no-op stub once at load if pkm-syntax wasn't yet on the rtp
(the likely cause of highlighting not appearing when pkm-syntax hangs off a lazy
plugin); now retries per access, caches only success. Author config: pkm-syntax moved
to be a dependency of pkm-nvim (lazy=false) not telescope. The highlight_all_markdown
mechanism itself is correct (verified headless). `keymaps.toggle_syntax` (default off).
test_v1470; audit test_v1130_p8 updated. Suite 75/0.*

*v1.46.0 closes the last Area-2 wrap open question: fenced-code content now wraps
**whitespace-preserving** — `markdown.wrap_range` keeps each code line's leading
indent AND internal whitespace, breaks only at a fitting space, over-long tokens
overflow (never split), continuations repeat the indent, lines never joined
(idempotent), a fitting line unchanged. New helper `wrap_code_line`; the fenced
branch no longer uses the space-collapsing `reflow`. Prose/list/blockquote wrap
unchanged. Area 2 (wrapping) now has NO open questions. `test_v1460_p1`. Suite 74/0.*

*v1.45.0 (Area-2 wrap polish): blockquotes now reflow in `markdown.wrap_range`
(`:PKMList wrap` / `gq`). A quoted paragraph reflows to `textwidth` at a normalised
prefix of `>` + 3 spaces per nesting level (a 4-column indent — `>   ` at depth 1,
`>   >   ` at depth 2), marker repeated on every wrapped line. A bare `>` is a
paragraph break; a quoted list/marker line (`> - x`, `> i. y`) is re-prefixed but
NOT folded into prose (nested structure inside quotes is out of scope). Non-quote
line ends the quote. Idempotent. `wrap_structural` no longer swallows `^%s*>`.
Deferred: the code-block whitespace question (fenced content still word-wraps).
Standalone pkm-syntax also gained a `setup({ number = false })` opt (line-number
suppression decoupled from the fold; default keeps numbers) — pkm-nvim's
enable()-driven note look is unchanged. Suite 73/0.*

*v1.44.0 completes the extraction: the markdown highlighting is now the standalone
**`pkm-syntax`** plugin (sibling repo `P:/Active/pkm-suite/pkm-syntax`, remote Vitruvia/pkm-syntax,
renamed from pkm-highlight). `lua/pkm/syntax.lua` is a thin facade re-exporting
`require('pkm-syntax')` (graceful no-op stub + warning if the plugin is absent), so all
callers are unchanged. The highlighting code and `queries/markdown/*.scm` MOVED to
pkm-syntax (removed here — two copies would double-apply the `; extends` query).
`test/min_init.lua` prepends `../pkm-syntax` to the runtimepath. **pkm-nvim now DEPENDS
on pkm-syntax** — the author must add it to the real Lazy config. Suite 74/0 through the
facade; behaviour unchanged (code moved verbatim). Architecture rule: pkm-syntax stays
`Dependencies: none`; its API (enable/disable/refresh_fold/foldtext/setup + patterns/
`_find_*`) is the contract — change in lockstep across both repos.*


*v1.43.0 (from the autowrap smoke): fenced-code **content** now wraps per line (fences
left untouched like headings); and `markdown.formatexpr()` is set as `formatexpr` on
PKM notes (`mode.lua` `enable_note_buffer`), so `gq`/`gw` and any motion (`gqq`,
`gq3j`, visual `gq`) route through the structure-aware wrap with no new keymap. Legal
format confirmed by the author. `test_v1410_p1` updated. Next: the physical highlighter
extraction into the `pkm-highlight`→`pkm-syntax` repo (sibling `P:/Active/pkm-highlight`,
remote Vitruvia/pkm-highlight).*


*v1.42.0 prepares the highlighter for extraction: `syntax.enable(bufnr, highlight_only)`
splits pure highlighting (tree-sitter, matchadd/extmark markers, YAML injection) from
PKM-note behaviour (frontmatter fold, window opts, zE), and `pkm_mode.syntax.
highlight_all_markdown` (default off) pure-enables non-PKM markdown via a FileType
autocmd in mode.lua (which owns the vault-path check, keeping syntax.lua
`Dependencies: none`). The physical repo split is an author-owned follow-up.
`test_v1420_p1`. No required smoke (default behaviour unchanged; all-markdown is
opt-in). **This closes the H→C arc**: all legal renumber + highlight + autowrap +
conventions shipped, and the highlighter is extraction-ready.*


*v1.41.0 adds `markdown.wrap_range(l1,l2)` / `wrap_at_cursor()` / `:PKMList wrap` — a
reflow to textwidth (or 80), **Option A**: a list item's continuation lines go to
marker_indent + 4 (never the prefix width; short markers padded to the 4-space tab
stop, long markers overflow only the first line), plain paragraphs reflow at their own
indent, and headers/tables/fenced-code/frontmatter/blockquotes are left untouched. All
marker families recognised (digit/bullet + the five legal markers, subalínea validated
so `civil.` is prose); idempotent. Fixes the wrapped-number highlight symptom at the
source (a continuation line never begins with `N. `). `test_v1410_p1`. SIGNALS A SMOKE
(feel of the wrap; note 0282). NEXT: extract highlighting as a standalone plugin
(Area 3 — needs a packaging decision), then the conventions doc. Blockquote reflow and
formatexpr integration deferred.*


*v1.40.0 opens the highlighting phase: the legal markers tree-sitter can't see now
highlight, completing parity with the renumber. **artigo** `Art. Nº` + **parágrafo**
`§ Nº` via matchadd (`syntax.artigo_list_pattern`/`paragrafo_list_pattern`, `\C`, `º`
optional, digit-required so prose is safe); **subalínea** `i.` via a validated buffer
scan + extmark (`find_subalinea_markers`, reusing the meta-comment mechanism) since
matchadd can't roman-check `civil.`. The roman validator is **self-contained in
syntax.lua** (no require of markdown) so the module keeps `Dependencies: none` for the
coming extraction. Author decision: standalone forms + own highlight, not the `- `
dash. `test_v1400_p1`. SIGNALS A SMOKE (note 0280, all levels + negatives). NEXT:
extract syntax as a standalone plugin (Area 3, all markdown), then structure-aware
autowrap (Area 2), then the conventions doc.*


*v1.39.0 lands the headline of the legal hierarchy: **`markdown.renumber_legal(l1,l2)`**
walks all five levels in one pass — artigo `Art. Nº`/`N`, parágrafo `§ Nº`/`N`, inciso
`R -`, alínea `a)`, subalínea `r.` — classifying each line by marker TYPE and resetting
every deeper level when a shallower one appears (nesting independent of indentation,
which is preserved). Ordinal rule (LC 95: `º`≤9, cardinal from 10). **`renumber_range`**
routes: ≥2 legal levels → nested, else the flat `renumber_sequence`; `:PKMList renumber`
uses it. Shared numbering helpers hoisted to module level. `test_v1390_p1`. **Legal
renumbering is complete.** SIGNALS A SMOKE — the artigo/§ format is a choice to confirm
(smoke note 0281). Remaining in the arc: subalínea highlighting (extmark scan), then
structure-aware autowrap (Area 2), extract highlighting as a plugin (Area 3), the
conventions doc (phase 4). `parágrafo único` deferred.*


*v1.38.0 adds the **subalínea** family (lowercase roman + `.`: i., ii., iii …) to
`renumber_sequence`. The marker token is validated as a **canonical roman numeral**
(round-trips through `to_roman`; new `from_roman`/`is_valid_roman` helpers), so words
made of roman letters (`civil.`, `mil.`, `mix.`) are not renumbered even mid-range.
Tried **before** the alpha family so `i.` is roman i, not the 9th letter; alpha keeps
`.` for non-roman letters (`a.`). Renumber only — subalínea **highlighting is
deferred** to the highlighting phase (matchadd can't do the validity check; it'll use
a buffer scan + extmarks like the meta-comments). `test_v1380_p1`; no interactive
smoke needed (renumber is headless-proven). Remaining hierarchy: artigo `Art. Nº.`/
`Art. N.`, parágrafo `§ N`, then the one-pass nested renumber.*


*v1.37.0 begins the Brazilian legal-text list hierarchy (author decision: legal `-`
form). The roman **inciso** family is retargeted from the v1.33.0 generic `.`/`)`
form to the canonical `I - ` (LC 95/1998: uppercase roman + ` - `), in both
`renumber_sequence` and the highlight (`syntax.inciso_list_pattern`, renamed from
`roman_list_pattern`). The `.`/`)` roman form is **dropped** (not kept as an alias).
The ` - ` separator keeps incisos distinct from the lowercase-roman subalínea (`i.`)
coming next. `test_v1330_p1`/`test_v1350_p1` retargeted; smoke 0280 updated via
pkm.api. Remaining hierarchy: subalínea `i.` (needs a roman-validity check for
false positives like `civil.`), artigo `Art. Nº.`/`Art. N.`, parágrafo `§ N`, and a
one-pass nested renumber across all levels. Then the structure-aware autowrap
(Area 2), then extract highlighting as a standalone plugin (Area 4), then the
markdown conventions doc.*


*v1.36.1 fixes a false positive in the v1.35.0/v1.36.0 marker highlighting: matchadd
honours `'ignorecase'` (the real config sets it), so `[IVXLCDM]` folded case and a
lowercase word like `civil.`/`id.` at line start was painted as a roman inciso. Both
patterns now lead with `\C` (case-sensitive): roman uppercase-only, alpha
lowercase-only. Caught by the v1.36.0 smoke-fixture prediction (a lowercase `c)`
matched the roman pattern). `test_v1350_p1`/`test_v1360_p1` set `'ignorecase'` and
assert it. Smoke note 0280 in `00 - NotesTeste`.*


*v1.36.0 is parallel work (Area 4, syntax highlighting): **lettered list markers now
highlight** — `a)`/`b)`/`aa)` (legal *alíneas*), completing the visual parity with
v1.34.0 renumbering and v1.35.0 roman markers. Same mechanism (matchadd via the
`PKMListMarker` group; tree-sitter emits no list node for lowercase markers either).
`syntax.alpha_list_pattern` (exposed). **The `)` form only** — the `.` form of a
lowercase label collides with two-letter abbreviations that can begin a line (`vs.`,
`cf.`, …), which an always-on highlight would paint; roman highlights both forms
because uppercase-roman abbreviations are rare. Renumbering still handles both `a.`
and `a)`. `test_v1360_p1`. Interactive → needs the real-config smoke.*

*v1.35.0 is parallel work (Area 4, syntax highlighting): **roman-numeral list markers
now highlight** — `I.`/`II.`/`VII)` (legal *incisos*). A live tree-sitter probe
confirmed the markdown grammar emits **no** `list_marker_*` node for uppercase roman,
so a `.scm` capture can't reach them; they're highlighted via a per-window `matchadd`
(the `PKMCitation` mechanism), a new `PKMListMarker` group linked to `@markup.list`.
`syntax.roman_list_pattern` (exposed) matches a roman marker at line start behind
optional indent/blockquote prefixes; `test_v1350_p1`. **The "resume a list after a
break" case needed no code** — the probe showed tree-sitter already marks arabic
markers resuming across blank-line/lazy/heading breaks (and every marker in the real
`ringforge-magia` note); the only unmarked shape (a marker ≠ 1 abutting a non-list
paragraph) is CommonMark-correct and is the Area-2 wrapped-number domain. Sits on
v1.34.0 (alíneas, `to_alpha`).*

*v1.34.0 is parallel work (Area 5, markdown editing, not agent-facing): a **lettered
list family** in `markdown.renumber_sequence` — `a)`/`b)`/`c)` (legal *alíneas*) are
now recognised and renumbered (letter labels via a `to_alpha` bijective-base-26
converter: a … z, aa …), nesting via the same per-depth counters, `.`/`)` separators
and blockquote handling as the other families. Additive — detected **last** (after
digit / emphasis / header / roman), bounded to 1–2 letters so prose is not swept;
a list starting at `a` is unambiguous (a lowercase i/v/x-start is not disambiguated
from roman). `test_v1340_p1`. **One family per pass** — a mixed roman-inciso +
alpha-alínea block renumbers only the detected level; full one-pass nested-hierarchy
renumbering is a later step. Sits on v1.33.0 (roman incisos, `to_roman`).*

*v1.32.0 adds **`api.duplicates(opts?)`** — near-duplicate notes (the candidates for
`merge`), completing the detect→act loop. Where `unlinked_pairs` finds *related*
notes, this finds notes that are nearly the *same*: similarity is a weighted Jaccard
blend of **body** words (0.5, the truest signal), **title** terms (0.3), and **tags**
(0.2, `by-claude` ignored), over every pair of substantive `note`/`agg` notes (bodies
from the index; all pairs compared so a body copy under a different title is caught —
quadratic, a deliberate sweep). Each pair `{ a, b, similarity, body_sim, title_sim,
tag_sim }` at/above `opts.threshold` (0.5); `opts.limit` (10). `test_v1320_p1` covers
the detect→`merge`→gone round-trip; **re-run `:PKMAgentProtocol install`**. This
**substantially completes the revision/evolution thread** (related-unlinked ·
stale · duplicates · merge); the eval loop resumes as the driver. It sits on v1.31.0
(the note-merge lifecycle write).*

*v1.31.0 adds **`api.merge(survivor_ref, absorbed_ref, opts?)`** (over
`notes.merge_notes`) — the missing primitive to *act* on duplicate findings. It folds
the absorbed note into the survivor: appends its body (under `opts.heading` if given),
**redirects its citation graph** onto the survivor (inbound citers re-pointed; the
survivor gains the absorbed note's outbound cites via the copied body), unions its
topical tags, then trashes it. Because `trash.trash_note` preserves backlinks for
restore, the graph is redirected **before** the trash so nothing dangles, and a copied
token pointing back at the survivor is stripped (no self-citation). **Both notes must
be assistant-authored** (the survivor is rewritten, the absorbed note deleted). Returns
`{ ok, survivor, redirected, absorbed_title }`; reuses `write_body` +
`citations.cite`/`uncite` + `agent_delete`. `test_v1310_p1`; **re-run
`:PKMAgentProtocol install`**. Next: the near-duplicate detector (`api.duplicates`)
that produces merge candidates. It sits on v1.30.0 (the `stale` review queue).*

*v1.30.0 adds **`api.stale(opts?)`** — the § 10 review queue: substantive `note`/`agg`
notes likely to need re-checking, ranked. The strong signal is a **provenance gap** —
no references (no bib citation, no `## References`/`## Sources` section) [3] or no date
[1]; **age** only ranks among flagged notes (+1/yr, capped) and never flags alone
unless `opts.min_age_days` is set (a plain aged-notes sweep). Each `{ path, title,
note_type, score, reasons = { no_references?, no_date?, age_days? } }`. Advisory and
heuristic ("look again", not "this is wrong"); bib notes and journals/scratch are out
of scope. Reads each candidate's frontmatter for dates/bib-cites, body from the index.
`test_v1300_p1`; **re-run `:PKMAgentProtocol install`**. Remaining in the thread: the
near-duplicate detector plus a note-merge lifecycle write (next). It sits on v1.29.0
(the vault-wide `unlinked_pairs` sweep).*

*v1.29.0 adds **`api.unlinked_pairs(opts?)`** — the vault-wide twin of
`related_unlinked`: every *pair* of notes related (shared tags / title terms /
co-citations) but with no citation edge between them, ranked, so the assistant can
review the whole vault for missing links and `cite`. Same signals/weights/exclusions,
computed over all pairs via inverted buckets; a bucket (tag / term / shared source)
with more than `opts.bucket_cap` (30) members is skipped as non-discriminating. Each
pair `{ a, b, score, shared = { tags, terms, co_citations } }`; `opts.limit` (20),
`min_score` (3), `graph` (true). Cost: one read of every note's edges — a deliberate
sweep. `test_v1290_p1`; **re-run `:PKMAgentProtocol install`**. Remaining in the
thread: the near-duplicate detector (same engine, higher threshold → merge; needs a
note-merge lifecycle write) and the stale detector (age + missing provenance, § 10).
It sits on v1.28.0, which added the co-citation signal to `related_unlinked`.*

*v1.28.0 adds the graph signal to `api.related_unlinked`: beyond shared tags and
title terms, a **co-citation** (weight 2 each) — a source both the focus and a
candidate cite/are-cited-by — so notes that lean on the same references surface as
related even with no shared tag. Each candidate now carries `co_citations`. It reads
each candidate's edges, so it sits behind **`opts.graph`** (default true); `graph =
false` is the prior cheap index-only pass. `test_v1280_p1` (notes related only by a
shared source, ranked by how many they share, absent under `graph=false`). Still to
come in the thread: a vault-wide unlinked-pairs pass, and the near-duplicate and
stale detectors. It sits on v1.27.0, which opened the revision/evolution thread with
`related_unlinked`.*

*v1.27.0 opens the revision/evolution thread (ROADMAP Area 1): the first tool that
surfaces what to *revise*, not just retrieve. **`api.related_unlinked(ref, opts?)`**
returns, for a focus note, the notes related to it (shared tags / title terms) but
**not linked to it** (no citation edge either way) — `{ ok, note, candidates }`, each
`{ path, title, note_type, score, shared_tags, shared_terms }`, ranked (tag = 2, term
= 1) — so the assistant can `cite` the ones that belong together (the eval-flagged
gap: related-yet-ungraphed notes). Non-topical tags are excluded so they can't make
everything look related: `by-claude` (on every assistant note) always, plus any tag
on >80% of the vault. Already-linked notes excluded. Advisory/read-only, single-vault,
cheap (index + one edge read). `test_v1270_p1`; **re-run `:PKMAgentProtocol install`**.
Focus-mode for now — co-citation signal, vault-wide clustering, and near-duplicate /
stale detectors are the planned continuations. It sits on v1.26.2 (help-panel patch).*

*v1.26.2 (patch, author-reported after the v1.26.1 smoke, interactive surface): a help
float left open by switching away is no longer orphaned — it closes on `WinLeave`
(dismiss keys run the Telescope-resume hook, a bare leave just cleans up); and the
two-chord `<C-y><C-v>`/`<C-y><C-x>` help row is realigned as a continuation line at the
shared description column across all five help panels. Code in `lua/pkm/views.lua`
(`show_keymap_help`). Sits on v1.26.1, which fixed the Telescope help-close and float
width.*

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
**bib doctrine** landed in `doc/AGENT_PROTOCOL.md` § 10 (consult `P:\Resources` + web;
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
  body_lower    : string    -- body:lower(), cached so filter.eval() need not re-lower per query
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
| Plugin path | `P:/Active/pkm-suite/pkm-nvim/` (Windows) · `/mnt/p/Active/pkm-suite/pkm-nvim/` (WSL) — sibling `pkm-syntax` alongside under `pkm-suite/`; GitHub repos stay separate under `Vitruvia/pkm-*` |
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
