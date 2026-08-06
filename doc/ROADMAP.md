# PKM.nvim — Project Roadmap for LLM Assistants

**Purpose:** the forward plan — versions, phases, goals — and nothing else.
Detail decreases as work recedes into the future; **completed work is summarised
in a line pointing at `doc/CHANGELOG.md`, and dropped entirely once nothing
pending depends on it.** When a section here narrates shipped work, it is only
because a *decision* it records still constrains work that is still pending.

For the standing rules that govern *how* a phase is executed and verified, see
`doc/PRINCIPLES.md`. For codebase architecture see `doc/ARCHITECTURE.md`; for
code rules, patterns, and environment see `doc/LLM_CONTEXT.md`. For the full,
canonical version history see `doc/CHANGELOG.md`.

---

## What This Project Is

PKM.nvim is an integrated note-taking and knowledge management plugin for Neovim. It is built around the author's own workflow design — not an implementation of Obsidian, Zettelkasten, or any other established PKM theory. The design is still being refined through daily use, but the current state is close to what the author wants.

The core concept is a **structured note flow**:

```
Scratchpad  →  capture ideas quickly, no friction
    ↓
Journal     →  timestamped daily entries, personal log
    ↓
Consolidated →  permanent numbered knowledge base
```

Notes are plain markdown files with YAML frontmatter. Consolidated notes carry structured citations that create bidirectional links automatically. The system is local-first, cross-platform, and Vim-native.

The note namespace is intentionally **flat and global** — all notes share a single counter, a single root, and a single citation graph. Project organisation is achieved through **views** (saved filter definitions), not through physical separation. Multi-wiki support (separate namespaces) is not a goal.

**Suite context:** pkm-nvim lives inside the **pkm-suite** working-tree grouping
as a sibling of **pkm-syntax** (the extracted markdown highlighter it depends
on). They are separate GitHub repos under `Vitruvia/pkm-*`, not a monorepo. Edit
highlighting in pkm-syntax, not here. See `CLAUDE.md` and the suite-level
`P:\Active\pkm-suite\CLAUDE.md`.

---

## Current State

**Current version:** see the top released entry in `doc/CHANGELOG.md` (canonical;
**v1.63.0** as of this writing). All work happens directly on `dev`; `main` holds
periodic stable backups of `dev`, not an independently maintained release line.

**Working features:**

== General ==
- ✅ Three folder types: Scratchpad, Journal, Consolidated
- ✅ Note creation with automatic numbering (`0042_note_Title.md`); numbering skips
     trashed note numbers to prevent conflicts on restore
- ✅ Note types within Consolidated: `note`, `bib` (bibliography), `agg` (aggregate/collection)
- ✅ YAML frontmatter management with templates per note type
- ✅ Bidirectional citation system — inserting a citation in A automatically adds a backlink in B
- ✅ Flexible timestamp system (`full`, `date_time`, `date_only`)
- ✅ Free-form `title` field — decoupled from filename; file renamed only via `:PKMNote rename`
- ✅ Note promotion: scratchpad → consolidated or journal
- ✅ Note conversion between types and folders (transpose)
- ✅ Import existing files into PKM structure
- ✅ Citation cleanup (removes stale references when notes are deleted)
- ✅ Tag merging across all notes
- ✅ Telescope integration: note browser, tag picker, citation picker, tag merge
- ✅ Export utility: filter notes by tag/title/body/filename, copy to folder (`:PKMExport`)
- ✅ Statistics window (`:PKMStats`)
- ✅ Cross-platform: Windows, WSL, Linux, macOS
- ✅ Context-aware citation picker — scores by active view (+2) and shared tags (+1)
- ✅ Multi-vault: registry (`vaults.json`), identity by path, lifecycle + switching

== Editing and Viewing ==
- ✅ Markdown utilities: header counter, level shift, symbol abbreviations
- ✅ Sequence renumbering: nested lists, blockquote-prefixed lists, emphasis-wrapped
     ordinals (`*N*`, `**N**`), `**N. body**` bold-line items, header families
- ✅ `:PKMList convert` — ordered ↔ unordered list conversion with depth prompting
- ✅ Legal-text list hierarchy (LC 95/1998): `:PKMList renumber` renumbers artigo /
     parágrafo / inciso / alínea / subalínea (one-pass nested `renumber_legal`);
     `pkm-syntax` highlights every legal marker
- ✅ Structure-aware autowrap `:PKMList wrap` (also `gq`/`gqq`/motions via formatexpr):
     Option-A list indent, blockquote reflow, whitespace-preserving fenced code
- ✅ `:PKMPanel mode [on|off]` — session context toggle; activates explorer UI,
     pre-builds index, enables tree-sitter syntax highlighting on PKM notes
- ✅ `:PKMPanel [explorer]` — toggle sidebar + buffer panel as a unit
- ✅ Markdown highlighting — now the standalone **pkm-syntax** plugin (a dependency):
     legal + native list markers, citations (`PKMCitation`), `((meta-comments))`
     (`PKMMetaComment`), YAML frontmatter injection, frontmatter folding/foldtext
- ✅ Metadata commands (buffer-only, no disk write): `:PKMNote settitle`,
     `:PKMTag add`, `:PKMTag remove`

== Search ==
- ✅ Boolean filter DSL over `tag`/`title`/`text`/`filename`/`type`/`any` fields
     (AND, OR, NOT, parentheses, quoted values)
- ✅ In-memory note index with incremental invalidation (~290× faster than raw scan),
     plus background chunked warm-up so the first panel/pop-up open is warm
- ✅ `:PKMBrowse [expr]` — live filter-as-you-type; bare text triggers `any` predicate;
     `<C-t>` cycles a note-type filter (all/note/agg/bib/journal/scratch) over the results
- ✅ `:PKMBrowse recent [n]` — n most recently modified notes (default 20)
- ✅ `:PKMTags` — tag picker; on selection opens browse(`tag:<x>`)
- ✅ `:PKMBrowse orphans` — notes with no tags, no citations, and no matching view
- ✅ Filter autocomplete for `:PKMBrowse`: field prefixes, operators, `tag:<value>`,
     `type:<value>` completions

== Views ==
- ✅ Project view system — named saved filters, sidecar `views.json`, full CRUD
- ✅ Subproject hierarchy — `{parent, filter}` entries composing AND chains
- ✅ `:PKMView` — view **management** only (v1.63.0): `new` · `update` (action
     picker-panel: edit filter / rename / reparent) · `edit` · `delete` · `rename`
     · `export [name]` · `add`/`remove` (note membership)
- ✅ `:PKMBrowse views [name]` — the view **pop-ups** (v1.63.0): bare = the
     tree-structured view picker (parent-child hierarchy); `<name>` = that view's
     notes; `last` = reopen the last activated view
- ✅ `:PKMPanel sidebar [view]` — the **persistent** two-mode sidebar (overview +
     detail), the sole door to it (v1.63.0): 50-entry navigation history, `<C-t>`
     type filter, `<C-v>` vertical split, `/` scoped search, `?` help float; hosts
     pluggable providers (views + nav) with autoswitch
- ✅ `:PKMPanel buffers` — persistent bottom buffer-list panel with auto-refresh
- ✅ Cyclable pop-up (`pkm.popup`) hosting browse / views / nav, cycled with `<C-l>`
- ✅ Per-tabpage state for both sidebar and buffer panel

== Trash ==
- ✅ `:PKMNote delete` — soft-delete to `.pkm-trash/` (when `trash.enabled = true`);
     backlinks preserved for clean restoration
- ✅ `:PKMTrash restore` — picker over trash manifest; moves note back, re-indexes
- ✅ `:PKMTrash empty` — permanently deletes all trash and strips backlinks
- ✅ Auto-purge via `trash.max_age_days` (default 60; 0 = disable)
- ✅ Trash manifest records `filename`, `original_path`, `title`, `deleted_at`,
     `deleted_timestamp`

== pkm.api (headless agent surface) ==
- ✅ `require('pkm.api')` — data-only, never opens UI; wraps existing cores
- ✅ Writes: `create`, `rename`, `changetype`, `transpose`, `annotate`, `cite`,
     `cite_source` (find-or-create bib note), `set_membership`, `save_subproject`,
     `rename_tag`, `merge` (note-merge with graph redirect)
- ✅ Reads: `find`, `find_all` (cross-vault), relevance ranking, `read`,
     `neighborhood`, `context`, `related_unlinked`, `unlinked_pairs`, `stale`,
     `duplicates`, `ui_state` (UI snapshot for agent-assisted smoke testing)
- ✅ Agent protocol: `doc/AGENT_PROTOCOL.md` + `doc/PKM_API.md` + `doc/CONVENTIONS.md`;
     `pkm-notes` skill installed by `:PKMAgentProtocol`

**Known limitations:**
- ⚠️ No preview system
- ⚠️ No image embedding or visualization support

**Metadata notes:**
- The `status` field has been **removed** from frontmatter. Do not reintroduce it.
- Citation structure: `cites: {notes: [], bib: []}` and `cited_by: {notes: [], bib: []}`.
- The `title` field is free-form and never overwritten by the system after creation.
- Trash is isolated to `.pkm-trash/` inside the PKM root (not OS trash).
- Note numbers skip trashed entries; gaps are intentional (numbers are identifiers, not labels).

---

## Architecture Reference

Codebase layout, per-module responsibilities, and configuration shape live in
`doc/ARCHITECTURE.md` (single owner). `config.lua` is the canonical source of
configuration defaults.

---

## Versioning Policy

The project sits in the 1.x range but is **pre-release**: there are no external
API consumers and the only user is the author. Versioning follows a constrained
form of [Semantic Versioning](https://semver.org/):

- **MAJOR is frozen at `1`** for the whole pre-release period. `2.0.0` is
  reserved for the first public-stability release and is not created during
  ordinary development.
- **MINOR (`1.Y.0`)** — introduces at least one backward-compatible,
  user-facing feature. May also carry bug fixes and refactors.
- **PATCH (`1.y.Z`)** — bug fixes, performance work, internal refactors, and
  documentation-only work. No new user-facing features.
- **"Backward-compatible"** is judged against the author's own configuration and
  workflow, since there are no other consumers. A change that requires the
  author to edit their config is still a MINOR during this phase (never a
  MAJOR), but must be recorded under a **Config changes** note in the CHANGELOG.
- **Phases are the unit of implementation and review** within a version. A phase
  edits each file in **exactly one pass** (see `doc/PRINCIPLES.md`). A version
  may contain one phase or several.
- **Tags** (`git tag -a vX.Y.Z`) are applied only after every phase of a version
  has landed and passed the verification protocol — never mid-version.

---

## Shipped so far (v1.5.7 → v1.63.0)

*Compact thematic summary. `doc/CHANGELOG.md` is canonical for what each version
changed; consult it rather than reconstructing detail here. Decisions from
shipped work that still constrain **pending** work are kept in
§ Design constraints carried forward, below.*

- **v1.5.7 – v1.11.1 — foundations.** Correctness/index batches; the bulk-metadata
  stack (v1.8.0, nine phases); the v1.8.1 defect pass (the reproduce-before-fix
  discipline); views-reached-from-where-you-are (v1.9.0); header navigation
  (v1.10.0); the **vault registry** and multi-vault enumeration/lifecycle/switching
  (v1.11.0/.1 — nothing outside the registry names a vault).
- **v1.12.0 – v1.14.0 — typed forms + command clearup.** The shared argument
  parser `args.lua` (v1.12.0 Ph1) gave every state-writing operation a typed,
  script-callable form (interactive and programmatic are the *same command*). The
  command surface collapsed from ~57 top-level names to **~15 verb-contexts**
  (`:PKMNote`, `:PKMTag`/`:PKMTags`, `:PKMView`, `:PKMVault`, `:PKMCite`,
  `:PKMBrowse`, `:PKMPanel`, `:PKMHeader`, `:PKMList`, `:PKMTrash`, `:PKMCheck`,
  `:PKMStats`) — verbs, not flags; completion is a tree. From here, **new features
  add verbs to contexts, not new top-level names.**
- **v1.16.0 – v1.21.0 — the pkm.api / agent-protocol stack.** The three-layer
  stack (data-only `pkm.api`; `AGENT_PROTOCOL.md` + `PKM_API.md`; the `pkm-notes`
  skill via `:PKMAgentProtocol`), validated by a real eval that reversed the
  first-run failure. Placement-aware writes (`insert_section`), note-lifecycle and
  user-note writes through the API (`annotate`), `ui_state`, and the
  memory-organization doctrine (AGENT_PROTOCOL § 11).
- **v1.22.0 – v1.32.0 — retrieval + revision threads.** Bib/sources
  (`cite_source`), cross-vault `find_all`, relevance ranking, `read`,
  `neighborhood`, `context`; then `related_unlinked`, co-citation, vault-wide
  `unlinked_pairs`, `stale`, `merge`, `duplicates`. Both threads are
  **substantially complete**; the eval loop resumes as the driver.
- **v1.34.0 – v1.47.0 — legal lists, wrapping, syntax extraction.** The Brazilian
  legal-text list hierarchy end-to-end (renumber + highlight); structure-aware
  autowrap (Area 2, complete); and the physical extraction of highlighting into
  the standalone **pkm-syntax** plugin (v1.44) with an on/off toggle (v1.47).
- **v1.48.0 – v1.56.0 — navigation + panels/sidebar.** The `panel.create` factory;
  the nav provider; the sidebar lifted onto `panel.create` hosting **pluggable
  providers** (views + nav) with **autoswitch**; buffer-panel `[count]<CR>` + `/`;
  the nav/headings pop-up; and the **cyclable pop-up** container (closing Phase 3.5).
- **v1.57.0 – v1.63.0 — conventions, suite move, surface + doc cleanup, perf.**
  Recursos read/write conventions + light note conventions (v1.57); relocation
  into pkm-suite (v1.58); the `doc/pkm.txt` verb-surface rewrite (v1.59); the
  **keymap redesign** on a persistent-vs-transient axis + `:PKMView update`
  picker-panel (v1.60, BREAKING for default keymaps); doc cleanup + memory prune
  (v1.60.1); and the **background chunked index warm-up** so the first panel/pop-up
  open is warm (v1.61 — benchmark-driven; the build is I/O-bound and its primitives
  are already optimal, so warming is the right lever); and the **documentation
  review + this roadmap's reorganization** (v1.61.1, docs-only — a conservative
  whole-tree code review found nothing to change; the `body_lower` index-shape
  drift was fixed; this document was compacted to its charter); the
  **forced-save fix** (v1.61.2 — Near 5.1: a citation into an open unmodified
  buffer writes the backlink *through* the buffer, killing the phantom W12 `:w`
  prompt at its source); and the **`pkm.sidebar` extraction** (v1.61.3 — the
  sidebar container host moved onto `lua/pkm/sidebar.lua`, `views.lua` is now a
  provider + re-export shim, behavior-preserving); the **browse-picker
  note-type cycle** (v1.62.0 — `<C-t>` in `:PKMBrowse`/the view note lists/the
  pop-up cycles all/note/agg/bib/journal/scratch, the non-sidebar way to reach
  journal & scratchpad notes; also silenced the stray `<C-l>` complete_tag error);
  and the **command-surface consolidation** (v1.63.0, BREAKING — the transient
  view pop-ups moved to `:PKMBrowse views`, the persistent sidebar has one door
  `:PKMPanel sidebar`, and `:PKMView` is view *data* ops only, per the
  persistent-vs-transient axis).

**The eval loop is the ongoing driver:** each run against the real vault reports
friction (a missing op, a discovery gap), which becomes the next increment.
Baseline: [[pkm-eval-first-run]].

**Documentation debt: cleared** (README, ARCHITECTURE, pkm.txt, LLM_PROJECT_INSTRUCTIONS,
the per-version docs). Suite/sibling structure and the pkm.api/agent layer are all
documented.

---

## Forward plan by area

*The pending plan, organized by area, priority-ordered. **Priority rule:**
anything that interacts with `pkm.api` or external agents — above all anything
that **creates or modifies commands** — comes first, because it is what the API
wraps. Per `doc/PRINCIPLES.md` 7, each area is tagged: **🔺** build the agent side
now, alongside the human side; **▹** low API impact, agent side may defer with a
noted caveat (but do both when it is easy). The detailed specs live under
§ Near goals / § Distant goals / § Potential goals below; this is the priority
view over them.*

**Pending-features status (as of v1.63.0).** There are **no non-deferred,
near-term pending features left** — the two that were open both shipped: the
**forced-save prompt** (Near 5.1) in **v1.61.2** (a citation into an open,
unmodified buffer now writes the backlink *through* the buffer, so a later `:w`
no longer hits the phantom W12 prompt), and the **`pkm.sidebar` extraction**
(Area 3) in **v1.61.3** (the container host now lives in `lua/pkm/sidebar.lua`;
`views.lua` is a provider that re-exports the container API). Everything still
pending is either **deferred** — vault lifecycle create/merge/split
and the in-place `convert` normaliser (Area 1); the persistent / mtime-cached index
(Distant 3); Phase 3.4 journal/scratch nav + block-element indexing (Area 3);
*parágrafo único* (Area 5); `:PKMView stats` (Potential); commands-outside-vault
(Functionality 3.1) — or **long-horizon** (the rest of Distant / Potential, which
carry "do not design toward"). A handful of open threads are **eval-driven and
open-ended** rather than scheduled features: growing agent-assisted smoke testing
and the retrieval/revision follow-ups (Area 1).

### 1 · pkm.api & agents — 🔺 highest priority

Core shipped (v1.16–v1.32; see above). **Pending:**

- **Vault lifecycle — create / merge / split**, plus the in-place `convert`
  normaliser. Deferred until a real `Unregistered/` folder needs them (they are
  the only vault ops that renumber notes). Full spec in
  § Merging and splitting vaults.
- **Agent-assisted smoke testing — grow the surface.** `api.ui_state` + `feedkeys`
  through the real mappings is proven (test_v1200_p1). Still to grow: broaden
  `ui_state` (telescope active, bufpanel contents, marks/highlights); a stub for
  `vim.ui.select`/prompts so picker-gated paths are drivable; a reusable harness +
  a skill note so the agent reaches for it by default. Background in
  `[[pkm-agent-smoke-testing]]`.
- **`cite` token placement (quality nit).** `cite` appends `[note[NNNN]]` at
  end-of-body, which can land after a `## References`/appendix as a dangling token.
  Consider an optional placement (a heading, like `insert_section`) or a
  conventional "Related" section. Not blocking. (`cite_source` already places under
  a `## References` heading.)
- **Retrieval thread — possible later work:** relevance-ranked neighbourhoods;
  body-text search; tooling that helps "structure a note for retrieval" (now
  protocol, AGENT_PROTOCOL § 11.6) — orienting-summary / section scaffolds.
- **Revision thread — the eval loop drives what comes next** (related-unlinked,
  stale, duplicates, merge are all shipped; act with the existing lifecycle writes).
- **Persistent / mtime-cached index — considered for interop, DEFERRED** (decision
  1/8/2026). See § Distant goals 3 for the decision, the two gates, and the
  low-risk cache shape. Interim win shipped: the skill batches a task into one warm
  headless session; and v1.61 warms the in-memory index in the background.
- RAG/OKF navigation aids (gestor mode); richer intra-vault graphs.

### 2 · Wrapping — ▹ COMPLETE

Structure-aware autowrap is done and has **no open questions** (v1.41 Option-A
indent + marker families; v1.43 fenced-code content + `formatexpr`; v1.45
blockquote reflow; v1.46 whitespace-preserving code). The reflow is idempotent and
marker-preserving. Nothing pending.

### 3 · Navigation + panels/sidebar — 🔺 (command-creating parts first)

Core shipped (v1.48–v1.56; see above). **Pending:**

- **Phase 3.4 (deferred)** — journal/scratch navigation (wires the idle
  `journal.lua` helpers); **block-element indexing** in the nav provider
  (headers inside code/quote blocks must **not** be extracted into the index).
- ✅ **`pkm.sidebar` extraction — done in v1.61.3.** The sidebar container host
  moved out of `views.lua` onto `lua/pkm/sidebar.lua` (the host for the views +
  nav providers, on `panel.create`). `views.lua` is now a provider that registers
  `views` with the container (like `nav`) and re-exports the container's public
  API, so every historical `views.<fn>` call site (commands/keymaps/mode/api/trash/
  nav) is unchanged. Behavior-preserving — the whole sidebar battery + full suite
  stayed green (`test_v1613_p1` locks the boundary); interactive smoke confirms.
  Multiple simultaneous sidebars stay a future per-user-config option.
- Active-window motions (list items, blocks — Near goals 2.1); explorer UI
  customisation (Distant goals 6); relevance ordering in panels (Distant goals 9).
  *These create commands/panels an agent reaches for → 🔺.*

### 4 · Syntax highlighting — ▹ core complete; now the standalone `pkm-syntax` plugin

All legal + native markers highlight; extraction to **pkm-syntax** is done (v1.44),
consumed through the thin `pkm.syntax` facade (no-op stub if absent). Cross-repo
rule: pkm-syntax stays `Dependencies: none`; its API is the contract — change both
repos in lockstep. **Further syntax/fold features now land in pkm-syntax, not here.**

- **Residual known issue (belongs to pkm-syntax):** a *manually* hard-wrapped line
  whose continuation begins `N. ` is mis-highlighted as a new list item. Inherently
  ambiguous (a line beginning `N. ` *is* a list item by every markdown rule). The
  autowrap-produced case is already fixed at the source (v1.41 guarantees a
  continuation line never begins `N. `). Any real fix is a context-aware scan in
  pkm-syntax. See Near goals 5.2 for the full report.

### 5 · Markdown editing features — ▹ legal lists complete

Legal lists are complete end-to-end (renumber v1.34/1.37/1.38/1.39 + highlight
v1.35/1.36/1.40 + structure-aware wrap + CONVENTIONS § Lists). **Pending:**

- **Parágrafo único** is the one unclassified legal marker (deferred — needs a
  per-article § count).
- **Displays / tables** (Distant goals 1); **insertable folds** (Potential goals).
- **`markdown.lua` extract-vs-keep (decided 3/8/2026): keep in-tree now.** The
  module is already **extraction-clean** (zero `require('pkm.*')`) and can become a
  `pkm-markdown` plugin the way highlighting became `pkm-syntax` — but the split is
  a **scheduled follow-up**, taken only when a real need appears (a second consumer,
  or the module outgrowing the plugin). New markdown features (header/content
  **folds**, displays/tables) land **in `markdown.lua`** and ride the eventual
  extraction; building them does not wait on the split.

### 6 · Other — ▹

- ✅ **Forced-save prompt** (Near goals 5.1) — **done in v1.61.2.** A citation
  into a note open in an **unmodified** buffer now writes the backlink *through*
  the buffer (`manage_backlink`, `citations.lua`), which re-stamps Neovim's stored
  on-disk timestamp; a later user `:w` no longer sees the plugin's write as an
  external change (the phantom W12 prompt), and no genuine external-change prompt
  is auto-accepted. The modified-buffer branch is unchanged (in-buffer only, no
  disk write). `test_v1612_p1`; the no-prompt outcome is a smoke confirmation.
- **`:PKMView stats`** — per-view counts (`views.count_many`, **not** `match_all`
  per view). A verb on `:PKMView`, not a new command. **DEFERRED (author, 3/8/2026);
  Potential, not scheduled.**
- **Commands outside the vault** (Functionality 3.1) — settle and guarantee the
  *default set* of `:PKM*` commands that work on any markdown file, not only vault
  notes. **DEFERRED (author, 3/8/2026).** (The highlighting half is done via
  `highlight_all_markdown` + `:PKMSyntax`.)
- Longer-horizon: browser preview (Distant 2); persistent index (Distant 3,
  deferred — decision under Area 1); review queue (Distant 5); smart search +
  relevance ranking (Distant 9); note sync (Distant 10); note versions / undo
  (Distant 11); metadata-system review; image / ASCII support.

---

## Merging and splitting vaults — deferred (split is further still)

Both are deferred on purpose. They are the only vault operations that renumber
notes, and renumbering means rewriting citations, which is why they wait until a
real `Unregistered/` folder asks for them. The batched machine they need already
exists: `citations.update_references_on_renames(renames)` (`citations.lua`), which
operates on `config.root_path` and therefore runs at the destination once the
files are there.

**Merge — the cheaper of the two, build first.** Incoming notes are **appended**:
renumbered starting at the receiving vault's next free number (its highest note
plus one); the receiving vault is not renumbered. `prepend` is an option, not the
default. Only one side of the graph moves, so only the incoming notes' citations
(plus any citation *into* them from notes that came along) are rewritten. Notes
that stay behind never change.

**Split — genuinely harder, because it is the selection that makes it so.** The
extracted notes are renumbered **from 01 in both vaults** — the new vault and what
remains. Renumbering the source vault rewrites *every* citation in it, not only
those touching the notes that left: a whole-vault rewrite of a live knowledge
graph. It wants a **dry run and a backup gate** before it wants a keymap. The
*selection* machinery already exists — the filter DSL, `:PKMExport`'s selection,
the marks in the views panels — so split should reuse them rather than invent a
selection UI: mechanically it is export → mass delete → mass renumber on both
sides.

**Order:** merge lands first and teaches the renumber-plus-rewrite path on the easy
side; split follows once that path is proven on real notes.

---

## Near goals (short-term to mid-term)

*Detailed specs for pending items. For how these group into areas and what comes
first, see § Forward plan by area above. Shipped sub-items are compacted to a line.*

1.  **Markdown improvements (near):**
    1.  ✅ **Global next-header** — `:PKMHeader sibling` (v1.15.0). Done.
    2.  **Conventions (near, partly done).** `doc/CONVENTIONS.md` exists (guidance,
        not yet a syntax contract). The **still-open** long-tail is the
        long-prefix spacing/indentation rule:
        -   spacing: GitHub's guidelines (two spaces after number prefixes, three
            after simple symbol prefixes → 4-space indent). For symbols ≥4 chars
            and numbers ≥3 chars, the **first line** may sit wherever it lands after
            `level indent + prefix + space`, but **every other line** starts at the
            current level indentation (Option-A indent — **shipped** in the v1.41
            autowrap):

            ```
            -- Intended result, assume a first-level prefix.
            11111111111. first line starts here...............................
                and all other lines wrap here.
            ```

            If prefixes are so long that indentation would transgress the margins
            (e.g. 80 chars), special notations are ensued (power notations like
            10^6), or the user opts for denser prefixes (hexadecimals, or
            `a`–`z` then `aa`–`zz`). This requires additional conventions and
            autowrap/highlight evaluation, and must not break current features.
        -   ✅ Brazilian legal-text list prefixes — **done** (Area 5).
        -   **Juxtaposition notation** for equivalent names like `AI/LLM` or
            `não-exaustivo/não-taxativo` — still to specify.

2.  **Navigation (near):**
    1.  **Active-window motions** — keymapped commands to navigate between:
        -   same-level list components;
        -   the end / beginning of a list;
        -   different-level headers (same-level is native Neovim; **any-level**
            shipped in v1.10.0);
        -   different-level list components;
        -   blocks of the same type (code blocks, lists, citations).
    2.  **Bookmarks / index** — extract headers into an indexed topic list
        accessible via a command that opens a nav panel for the current note
        (navigate between headers; also usable to copy the index). *(The nav
        provider ships this for headings; block-aware indexing is Phase 3.4.)*
    3.  **Sidebar** — a keymap to open the index *within* the sidebar and one to do
        it *without leaving the active window*. The bookmark bar shows the index
        with collapsable/expandable levels and allows quick navigation to the view
        system, with **no autoswitch** for this bookmark mode (it appears only when
        the user asks, and switches back to view navigation only when the user
        asks). **Headers within container blocks (code, quotes) must not be
        extracted** — the system must understand our textual structures, and
        conventions instruct users and AI to read them the same way (code blocks
        and quotations are display, so nothing inside them is part of the main
        text's structure).

3.  **Functionality (near):**
    1.  **Custom syntax + commands outside PKM.** Highlighting half **DONE**
        (`highlight_all_markdown` + `:PKMSyntax`, per buffer). The
        **commands-outside-vault half is DEFERRED** (author): many commands (e.g.
        `:PKMNote rename`) already work outside the vault; settling and guaranteeing
        the *default set* that always works on any markdown file waits.
        Customization stays distant.
    2.  ✅ **Custom PKM-aware autowrap** (frontmatter / code / headers / tables /
        custom-prefix lists) — **done** as Area 2 (v1.41–v1.46).
    3.  ✅ **Batch add/modify tags** — done (v1.8.0).
    4.  ✅ **Add/remove a note into a view (tag only)** — done (v1.8.0 Ph3 /
        v1.9.0). *(Spec, for reference: grab each OR-separated tag set a view
        accepts; if one, add it (no duplicates); if several, present a panel.
        Removal presents "remove all" vs "minimal sets".)*

4.  ✅ **`pkm.api`** — the programmatic surface for LLM assistants — **shipped**
    (v1.16.0+). Data-only, headless-safe, wraps existing cores, writes are
    auditable, no new typed commands. See § Forward plan by area 1 for pending
    growth and the agent-protocol docs.

5.  **Misc** (the LLM assistant decides timing):
    1.  ✅ **Forced-save prompt — done (v1.61.2).** The residual `y`/`n` prompt is
        gone, removed *without risk* per the caveat: a citation into a note open in
        an **unmodified** buffer now writes the backlink *through* that buffer
        (`manage_backlink`), so Neovim's stored on-disk timestamp stays in step and
        a later `:w` no longer treats the plugin's own write as an external change
        (W12). No genuine external-change prompt is auto-accepted; the
        modified-buffer branch is untouched. `test_v1612_p1`.
    2.  **Wrapped-number highlighting (reconciled 3/8/2026; was "Fix now").**
        Highlighting moved to **pkm-syntax** (v1.44), so any code fix is a
        pkm-syntax change — which is why CHANGELOG § Known Bugs shows no open
        pkm-nvim bug. The autowrap-produced case is mitigated (v1.41 guarantees a
        continuation line never begins `N. `). The **residual** case — a *manually*
        hard-wrapped line whose continuation starts `N. ` — is inherently ambiguous
        and the scanner cannot know it is wrapped citation text. Any real fix is a
        context-aware scan in pkm-syntax, or the user avoids hard-wrapping
        mid-sentence. *(Original case: `… no edital [note[0205] - 1. Da Prova
        Discursiva].` wrapping just at the second `1.`.)*

---

## Distant goals (mid-term to long-term)

1.  **Markdown improvements (distant):**
    1.  Conventions (distant):
        -   evaluate cost-benefit of extending list prefixes to any alphanumeric
            symbol + a separator from a standard list (`-`, `.`, `)`, `:`), and the
            same for symbol sequences — allowing `text:`, `I -`, `I)`, etc. to be
            highlighted and to drive wrapping/indentation (needs the long-prefix
            indentation conventions above).
        -   **displays:** markdown/tsv/csv tables; space- or multispace-separated
            tables; separator conventions; text wrapping inside table cells and
            across two-or-more-column layouts (custom autowrap leaving native
            untouched):

            ```
            -- WRONG --
            - XLIII       Crimes de tortura, tráfico ilícito de entorpecentes e afins,
            terrorismo e crimes hediondos

            -- CORRECT --
            - XLIII       Crimes de tortura, tráfico ilícito de entorpecentes e afins,
                          terrorismo e crimes hediondos
            ```

2.  **`lua/pkm/preview.lua`** — browser-based live preview: Markdown + LaTeX
    (MathJax), WebSocket live updates on save, cross-platform browser opening,
    terminal fallback (glow/mdcat).

3.  **Persistent index — considered for LLM interop, DEFERRED (decision 1/8/2026).**
    Weighed *because of* interop: the agent invokes `pkm.api` headless, **one cold
    process per call**, so it re-pays the full index `build()` every time, and
    `find_all`'s `scan_root` re-reads every non-active vault from disk on each call.
    Measured cold cost (`bench.find_all_bench`, synthetic temp fs): ~0.16 ms/note →
    a 3-vault `find_all` runs **~96 ms at 200 notes/vault, ~470 ms at 1000, ~975 ms
    at 2000**; Drive-backed vaults are likely slower. Verdict: tolerable now, a real
    cost past ~1k notes/vault. **Deferred behind two gates:** (a) let the retrieval
    features define the read pattern first (RAG may want body text/embeddings, so
    persisting a shape now risks the wrong one); (b) build only once a `bench.lua`
    baseline **on the real vaults** shows a bottleneck (the standing no-optimisation-
    without-a-baseline rule). **Interim wins shipped:** the skill batches a task into
    one warm headless session; v1.61 warms the in-memory index in the background.
    **When built, the low-risk shape:** an **mtime-keyed cache** — reuse entries
    whose mtime is unchanged, re-read only the rest (incremental rebuild that
    self-heals staleness on load), written atomically (the `vaults.json` precedent),
    treated as a cache and never an authority (a lost/corrupt one just rebuilds; keep
    it **off** the synced drive to avoid `.conflict` churn). Design for two writers —
    the agent process and the user's editor.

4.  **`_match_cache` in views.lua** — cache matched path arrays alongside filter
    trees (O(1) repeated `match_all` until invalidation). **Not adopted by v1.6.1
    Ph3**, which reached a ~5–9× overview speedup without invalidatable state
    (`count_many` + precomputed sort keys). A cache would now only pay off for
    repeated *path* queries. Revisit at ~5k notes or ~200+ views with observed
    latency, and only after the cheaper `:PKMBrowse orphans` fix (skip the per-view
    sort — CHANGELOG § Known Bugs).

5.  **Note review queue** — select and track notes intended for review. May include
    organizers, separators, or filter interactions for priority/subject
    categorisation.

6.  **Explorer UI customisation:**
    1.  positions and width of each panel; auto-on/off triggers by directory, CWD,
        or buffer type; other layout options.
    2.  improved help panel with main keymaps (the current help is sidebar-only);
        must update as the user customizes their config (so it is tied to this item).
    3.  **Sidebar options:** always on; always off; on when a note is opened (then
        remain); on when entering the notes folder (then remain); **off when any
        note is opened** (a negative toggle, cumulative with and taking precedence
        over the positive toggles).
    4.  **Buffer panel options:** always on; always off; on when a note is opened
        (then remain); on when entering the notes folder (then remain); on when a
        note is opened but off again when all notes are closed.
    5.  `:PKMExplore` uses its own options for the sidebar and buffer panel;
        whatever is toggled later takes precedence; user manual toggles always win.

7.  **Syntax highlighting (distant):** extended list-prefix recognition (now lands
    in **pkm-syntax**).

8.  **System customization:**
    1.  turn PKM's markdown features on/off, to allow external markdown plugins.
    2.  UI customization (Telescope-based or a possible native UI): sidebar and
        buffer-bar positioning.
    3.  PKMMode: when to activate; which functions/commands/highlighting to
        propagate outside the PKM system; root and note-folder renaming; note-type
        renaming; new note-type creation per user need.

9.  **Improved search/browse and citations:**
    1.  improve context detection (only if it does not significantly impair
        performance) so notes order by **relevance** on search and in the panels
        (buffer + sidebar). Signals: same subview > same view > same tags but not
        the same view > no relationship; among equals, exact-same-tags first; also
        creation/modification period, shared citations, recently opened/edited,
        frequently-opened-together, textual matches. Define a rationale for the
        priority; take inspiration from Obsidian/Google/social-network ranking.
        (Design Question 1: tag-set relatedness is a candidate signal.) *Real case:
        `0035_bib_Constituição…1988.md` was untagged `direito-constitucional` yet is
        clearly related and cited by many notes in that view — detect this.* Keep
        maintainability, future-Vim compatibility, feature-compatibility, and
        performance paramount; **discard any part that cannot meet them.**
    2.  smart search **without** losing the exact-textual-match protocol (not fully
        fuzzy): "remedios" should find "remédios", "remedios constitucionais" should
        find "remédios-constitucionais", but an exact match ranks above smart matches.

10. **Note sync** — in-PKM syncing (GitHub, Google Drive, or others) with privacy
    (a private option and a local-only option; easy local deletion after work when
    downloaded elsewhere), robust to desynchronized edits (diff-converge), and fast
    (no Evernote-style lag).

11. **Note versions and undo** — store some versions of a note, allowing "undo"
    even after save/close. Evaluate against performance and storage cost.

12. **Navigation (distant):** improved motion inside tables (quick move to next
    cell/column/line, including unfilled cells).

---

## Potential but not guaranteed goals (do not design toward)

-   **Alternative PKM modes:** Obsidian-style backlink graph, Zettelkasten
    ID-based linking, etc. Selectable configurations, not the default.

-   **Image and visualization support:** embedded images, Mermaid in preview,
    inline rendering (kitty/iTerm2 protocols).

-   **`:PKMView stats`** — **DEFERRED (author, 3/8/2026); Potential, not scheduled.**
    Table of all views with note counts and subproject depth. When taken: iterate
    `views.list()` and format `views.count_many(list)` (the linear counting pair —
    **not** `match_all()` per view) as a float or notification. A `:PKMView stats`
    verb, not a new command.

-   **Metadata system review (in-file vs. sidecar).** Recorded for future
    reconsideration only. Decision gate: revisit ONLY IF, after (1) the
    modified-buffer write-through fix and (2) frontmatter folding/conceal, the
    in-file approach remains unacceptable in daily use.

-   **PKM UI** — a UI not dependent on Telescope, letting users choose which UI to
    use and enabling more flexible development of commands that currently use
    Telescope's UI. Telescope's UI and search are not removed while in use; users
    choose which to enable, and where adequate they may run together.

-   **Alternative diagram and imaging methods** — ASCII/text-based art and other
    portable methods. Examine human readability, AI/machine readability, and
    portability before implementation.

-   **Insertable folds** — a character combination marking fold start/end in any
    file, implemented only if it does not incur heavy performance cost (else a
    partial implementation, else skip and record why + what must change). Full spec:
    -   conceal any line or collection of marked lines;
    -   detect a fold that starts at a header and wraps its content → show the
        header's name when folded, marked/highlighted as a header, title preserved;
    -   detect a fold wrapping a code / citation / list / table block → mark it as
        such when folded, with a counter if several ("code block 1, 2…");
    -   detect a fold around plain text (inline code, bold/italic) but not headers /
        code / native wrappers → identify as just text;
    -   preserve performance even with several folds in a file;
    -   partial implementation: conceal only headers and the content they wrap;
    -   advanced: autoconceal options (default `{headers: [on; level 2; autofold
        off], frontmatter: [on; level 1; autofold on]}` — level-2 headers wrapped in
        concealers but not folded; frontmatter always wrapped and folded by default).

-   **Exportation (compatibility formats):**
    1.  **pkm (standard)** — the plugin's own format (already the default).
    2.  **common markdown** — reformat: every non-standard list prefix standardized
        (a legal `Art. 1º.` / `§ 1º.` → `1.` / `1.1.`, or `1.` if `1.1.` is
        incompatible) with correct indentation (often already present, so only the
        prefix changes); same for every PKM/user convention unsupported by the main
        protocols (CommonMark default, options for other protocols).
    3.  **Obsidian** — frontmatter extracted into Obsidian-compatible metadata;
        markdown/notation reformatted for Obsidian.

---

## Unlikely goals, nongoals, or out of consideration

- **Multi-wiki** — multiple independent namespaces with separate counters.
  Superseded by the view system. The single global counter guarantees uniqueness;
  do not break it.
- **Non-flat citations** — hierarchical structure beyond `notes`/`bib`. Undecided;
  current structure may be permanently sufficient.

---

## Design constraints carried forward from shipped work

*The decisions below were paid for in shipped versions but still bind **pending**
work; that is the only reason they survive here (the per-version storytelling is in
`doc/CHANGELOG.md`). The non-negotiable **code** invariants are owned by
`doc/LLM_CONTEXT.md`; these are the roadmap-level design rules.*

**Command surface & shape**
- **Verbs, not flags**, and **no new top-level `:PKM*` names** — a new capability
  is a verb in an existing context (or a panel action), completing from the same
  table that declares it. Daily-typed shortcuts (`:PKMBrowse`, `:PKMBrowse views`,
  `:PKMNote new`) keep permanent names, documented as shortcuts.
- **Sorted by the persistent-vs-transient axis (v1.63.0).** Transient pop-ups live
  on `:PKMBrowse` (notes, recent, orphans, tags, `views`); persistent panels on
  `:PKMPanel` (sidebar, buffers, nav, explorer, mode); `:PKMView` is view **data**
  only (new/update/edit/delete/rename/export/add/remove). A command opens a view
  three ways by *mode*, not by owner: transient (`:PKMBrowse views`), pop-up
  (`pkm.popup`), persistent (`:PKMPanel sidebar`) — the same pattern notes have.
- **Interactive and programmatic are the same command** — bare = friendly path,
  arguments = deterministic/script-callable; destructive ops confirm in both forms.
- **Every capability lands in three thin layers:** a pure/read-only core (no UI); a
  row in the `actions.lua` registry when it acts on a set; at most one more argument
  on an existing command. The UI is always the thinnest layer.
- **A vault cannot be named after a verb** — `validate_name` reserves the verb list,
  so position-1 stays unambiguous (verb only when it matches a declared one).

**Selection, panels & the undo block**
- **Choosing notes belongs to the navigation panels**, not a command's own scope
  prompt. `ctx.view` **orders, it never decides** — where a selection came from says
  nothing about what to act on.
- **`picker.select_live` is the panel shape** for any bulk operation (the prompt
  *is* the operation; rows recompute per keystroke; no separate result screen).
  **`picker.choose`** is the one-of-N menu for an already-ranked list; reaching
  `vim.ui.select` mid-flow drops a Telescope user onto the command line.
- **Nothing the plugin does may enter the user's undo block.** A buffer mutation
  during the write cycle drags `u` off the edit; a mutation from a scheduled
  callback leaves the block open and absorbs the next keystrokes — force the break
  with `let &undolevels = &undolevels`. The post-write file rewrite must happen on
  **every** save, or a later `:w` stops with W11.
- **`create_new_note` owns the window guard**, not its callers: panels set
  `winfixbuf`, so opening a buffer from one is E1513. `utils.focus_editing_win` is
  the single search for a window that may hold a note.
- **A key that belongs to "the view surfaces" is wired at all of them in one edit**,
  through one helper; a chord's prefix must itself be a complete mapping.

**Vault state, paths & identity**
- **Vault state never holds an absolute path.** Anything the plugin writes *inside*
  a root is relative to that root and re-rooted on read (vaults get copied, moved,
  switched). This is what unblocked multi-vault and applies to every future sidecar.
- **One value, one job.** Do not overload one argument as both a note's identity and
  the place to read its text (a trashed note has moved: the two diverge).

**Verification & the editor**
- **Check what the editor already does before planning to add it** — read the
  runtime, not memory (Neovim's native `]]`/`[[` already jump *any*-level headers;
  the complement PKM owed was count/level/Visual/jumplist/no-parser, not a repeat).
  A key that repeats the editor is spent for nothing.
- **A count and a numeric argument cannot share a command** — Vim reads a leading
  number as the count, so a level argument needs a non-numeric spelling (`h6`).
- **Assert the source, not the value, when someone else writes the same state** —
  probe `numberwidth` (no ftplugin touches it), not `shiftwidth` (the markdown
  ftplugin sets it after modelines run, so it reads the same either way). The
  headless suite is blind to this; the author's smoke pass caught it.
- **`entry.mtime` is the only recency signal** (`last_updated_on` has no consumer),
  and it is not a record of human editing — Drive sync, restores and checkouts all
  push mtime forward.

**Resolved Design Questions (no further planning needed)**
- **Note relationship** → tag-set relatedness (Jaccard/overlap), not rigid
  parent/child; feeds relevance ranking (Distant 9). The v1.7.0 "relative note"
  embodies it at creation time.
- **A note type for describing other notes** → no new frontmatter `type`; use
  `_meta` subviews (`doc/CONVENTIONS.md` § Views) and the underscore-first sort.
- **Exportation** → the AI-context case is just another `_meta` subview (exporting a
  view already exports its subviews). The still-open half (compose current-note /
  current-view / arbitrary export) lives under Distant goals § Exportation.
- **Command clearup** → resolved and shipped (v1.13/v1.14); the policy is the
  "Command surface & shape" constraints above.

---

## LLM Assistant Rules, Patterns & Environment

Non-negotiable rules, established code patterns, environment details, debugging
commands, and git conventions are owned by `doc/LLM_CONTEXT.md` — consult it
alongside this document. They are intentionally not restated here. Module structure
(header block, section separators, LuaDoc) is a coding standard owned by the
project instructions (`doc/LLM_PROJECT_INSTRUCTIONS.md` § Coding Standards).

---

## Neovim Version Compatibility Watch List

Audited 2026-06-21 against Neovim 0.12 (stable, 0.12.3) while still running
0.11.3. Full breaking-changes/deprecations list reviewed; no code changes
required for the 0.11 → 0.12 upgrade itself. Recorded here so future upgrades
don't need to re-derive this from scratch.

**Confirmed safe (re-verified against 0.12 `news.txt`, no action needed):**
- `vim.treesitter.get_parser()` now returns `nil` on failure instead of
  throwing. All call sites in `syntax.lua` already wrap in `pcall` and check
  for `nil`, handling both behaviors. No regression.
- `UndoPost` still does not exist as an autocmd event in 0.12. The existing
  rule ("never register `UndoPost`") remains correct — re-check this line
  specifically at the next major version audit, since it's the one rule most
  likely to silently become obsolete (i.e., wrong, not broken) if Neovim ever
  adds the event.

**Low-priority migration (deprecated, not removed — no urgency):**
- `nvim_create_autocmd()`'s `buffer` key is deprecated in 0.12 in favor of
  `buf` (old key still accepted). Used in `syntax.lua` and `views.lua` at
  minimum. Safe to leave as-is; rename opportunistically when touching those
  autocmds for other reasons, not as a standalone task.

**Watch item (uncertain risk, verify after actual upgrade):**
- 0.12 tightened URI-scheme detection on buffer names (RFC3986). PKM does not
  call `vim.uri_*` or otherwise parse buffer names as URIs, so Windows
  drive-letter paths (`P:/Active/...`) should be unaffected. Not verified
  empirically. After upgrading, sanity-check `:PKMNote`, `follow_link` (`gf`),
  and sidebar note-opening (`edit` + `fnameescape`) against a `P:/` path first.

**Process for future upgrades:**
- Re-run this audit against `:help news` for the target version before
  upgrading, not after. Check specifically: treesitter API changes (PKM's
  heaviest Neovim-API surface), autocmd event additions/removals, and any
  change to `foldmethod=manual` / `matchadd` semantics (used in pkm-syntax's
  frontmatter folding and citation highlighting).

---

*Update this document as a batch after each version is completed, per the
Documentation Maintenance Cadence in the project instructions — not
continuously as project state changes.*
