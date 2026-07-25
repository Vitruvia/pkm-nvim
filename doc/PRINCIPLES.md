# PKM.nvim — Standing principles

**What this file owns:** the rules that hold across every version and phase —
how work is split and executed, how features are designed, and how a phase is
verified before it is committed.

**What it does not own:** the forward plan (`doc/ROADMAP.md`), the codebase
layout (`doc/ARCHITECTURE.md`), scope constraints (`doc/PHILOSOPHY.md`), coding
standards (`doc/LLM_PROJECT_INSTRUCTIONS.md`), or what already shipped
(`doc/CHANGELOG.md`).

These principles were extracted from the ROADMAP once it became clear that a
plan document holding permanent rules made both harder to read: the plan should
shrink as work completes, and these do not.

---

## Execution — how work is split

1. **One pass per file per phase.** A phase may touch many files, but never the
   same file twice within that phase. All edits to a given file in a phase must
   be mutually compatible, low-risk, and verifiable together, so it is safe to
   apply them all before verifying. When a file would need two incompatible
   passes, the work is split along a seam where each part still functions
   independently, and the parts land in different phases (possibly different
   versions). Different phases **may** re-touch the same file.

2. **A phase groups by safe co-modification, not by category.** Items share a
   phase when their file edits combine cleanly, even if one is a bugfix and
   another a feature. The rule is a ceiling, not a mandate to cram unrelated
   work together.

3. **Each phase fits one response.** A phase is delivered as a single message
   containing every modification it needs, file-by-file, never split across
   messages.

---

## Design — how features are shaped

4. **One panel, not a wizard. Count the screens before writing the flow.**
   A command's cost is measured in *screens between the user and the result*,
   and a screen that does not decide anything is a defect. Concretely:

   - **Prefer a single panel where typing *is* the operation** — the input and
     the preview in the same place (`picker.select_live`). A form that collects
     parameters, then a screen that shows the notes *without* the change in
     them, is two screens doing the work of none.
   - **A menu of operations is usually a syntax problem.** Five choices —
     prefix, suffix, remove, replace, rebuild — collapse into one substitution
     field, where `^/X ` prepends and `$/ X` appends. Ask whether the options
     are really one expression the user already knows how to write.
   - **Reuse the syntax the user has in their fingers.** Neovim regex over Lua
     patterns; `pattern/replacement` over two prompts. Familiar beats novel even
     when novel is tidier to implement.
   - **Never make the user restate what the editor already knows.** No scope
     prompt when a panel has a selection; no note picker when the notes were
     just marked.

   Written after v1.8.0 Ph7 shipped a five-option menu followed by two more
   screens, and had to be rebuilt as one panel. The failure mode is systematic,
   not a slip: each step looks reasonable in isolation, and the cost only shows
   when the flow is used.

5. **A feature ships its own UI, in its own phase.** When a phase creates or
   changes a choice the user makes, the Telescope version of that screen —
   counts, previewer, the shared marking gesture — is part of *that* phase, not
   deferred to a later "UI pass". The `vim.ui.select` / float path remains as the
   no-Telescope fallback, and small fixed choice sets (3–4 options, e.g. the
   Simple/Deep menu of `:PKMExport`) may stay `vim.ui.select` outright. Shipping
   the poor version first creates rework and an inconsistent surface across
   commands; v1.8.0 Ph3 had to go back and redo the tag panel for exactly this
   reason.

6. **Command surface.** A typed command is for what the user invokes directly;
   nothing gets a new `:PKM*` name when it fits as an argument to an existing
   command or as an action in a panel. Every capability lands in three layers — a
   pure or read-only core with no UI, a row in the `actions.lua` registry when it
   acts on a set of notes, and at most one more argument on an existing command.
   The interactive and programmatic forms are the *same* command: bare it is the
   friendly path, with arguments it is deterministic and script-callable, and
   destructive operations keep their confirmation in both. (Full discussion:
   ROADMAP § Design Questions 4.)

---

## Standing bug-prevention design rules

- **`winfixbuf` safety net.** Every PKM panel window (sidebar, buffer panel, and
  every panel built on `panel.lua`) sets `winfixbuf = true` immediately after
  its buffer is assigned. This converts the whole class of "a file opened inside
  the panel" bugs (`:Ex`, `:edit`, `:PKMViewEdit` invoked while a panel holds
  focus) from a silent hijack that destroys the panel into a loud, harmless
  error. PKM's own open/create commands additionally redirect through
  `focus_main_win()` for smooth UX; `winfixbuf` catches everything not explicitly
  guarded, including built-ins PKM cannot intercept.
- **Pure-logic-first.** Non-trivial logic (deep-export traversal, case-rename
  identity test, title-propagation diff, citation-edge extraction, header
  targeting, window-slot arithmetic, tag-set relatedness, name substitution) is
  written as a pure function with explicit inputs/outputs and no editor or
  filesystem side effects in the core. The per-phase test file exercises the pure
  function; the command/UI layer is a thin wrapper.
- **Reuse, don't reimplement.** Resolve citation identifiers through
  `citations.get_citable_items_map()`; redirect panel focus through
  `focus_main_win()`; refresh sidebars through `views.refresh_sidebar_if_open()`;
  propagate identity changes through the existing rename-propagation machinery;
  keep open buffers in step through `bufsync`.
- **Batch the vault scans.** `citations.propagate_title` and
  `update_references_on_rename` glob and read every note in three folders *per
  call*. Any operation that touches N notes uses the batched form
  (`propagate_titles`) instead, or it is quadratic.
- **Invariants restated per phase.** Each phase names the invariants it must not
  break (e.g. never `index.invalidate` from buffer-only metadata commands; never
  strip backlinks in `trash_note()`; never register `UndoPost`; never run
  `git gc`; always `utils.join` / `utils.normalize` for paths; Telescope checked
  at call time; never optimize without a `bench.lua` baseline). A phase that
  cannot satisfy an invariant is re-scoped, not forced.

---

## Standing Verification Protocol

Every phase is verified in this order before its commit:

0. **Push, then sync.** `git commit -a -m "..."` → `git push pkm-nvim dev` →
   `:Lazy sync` (or `:Lazy update`) in Neovim, then restart. Lazy.nvim
   installs this plugin from GitHub, not the local working tree — none of
   the steps below can observe a change that hasn't been pushed and pulled
   first. Tag only after step 5 passes, never before.
1. **Headless sandbox run** against a disposable scratch corpus, never the live
   `Notes` tree:
   `nvim --headless -u test/min_init.lua -c "luafile test/test_<phase>.lua" -c "qa!"`.
   Empirical execution precedes any claim that a fix works.
2. **Per-phase test file** `test/test_<version>_<phase>.lua` asserting pure-logic
   outputs including success, failure, boundary, cycle, empty, and nil inputs.
3. **Static pass** — `luacheck` on changed files, plus the recurring-issue
   checklist (string-concatenated paths; cross-module `M.` references; load-time
   Telescope checks; greedy timestamp patterns; missing
   `update_references_on_rename`; double declarations; template-key/config-key
   mismatches).
4. **Cross-platform spot-check** — path-touching changes exercised against a
   Windows drive path (`P:/Notes/...`) and a WSL mount path (`/mnt/p/Notes/...`)
   in the fixture.
5. **Manual smoke checklist** — the exact `:PKM*` commands to run and their
   expected outcomes.

**What the headless suite cannot see.** Telescope is not on the runtimepath in
headless, so every Telescope-backed screen is smoke-only; the tests exercise the
`vim.ui.*` / float fallback. Three bugs in v1.8.0 Ph6 lived exactly there. When a
phase adds a Telescope surface, the smoke checklist must name it explicitly, and
anything reachable in the fallback is tested rather than assumed.

**Review protocol for returned modifications.** When applied changes are pasted
back, each is checked for: (a) landing only in the named function/region;
(b) header/section/LuaDoc discipline; (c) no second pass on a file already
touched this phase; (d) no forbidden pattern reintroduced; (e) presence and pass
of the phase's test artefacts; (f) behaviour matching the spec. Discrepancies
are reported with root cause before any follow-up edit.
