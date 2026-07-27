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

- **Every removal confirms.** Removing, deleting or discarding always presents a
  screen that says what is about to be lost, and it says so in the *title* of
  that screen, not only in the body. This holds for the whole plugin: a note, a
  view, a tag across a batch, a note's membership of a view, the trash, an
  unsaved buffer.

  It is the deliberate counterweight to principle 4, and the two are constantly
  confused. **A menu asks *what*; a confirmation guards the *irreversible*.**
  Cutting a menu that offers a single option removes a step that decides
  nothing. Cutting a confirmation removes the only chance to stop. So:
  one-option menus go, confirmations stay — and "the user already told us what
  they want" is an argument about the first, never about the second.

  Two things are *not* exempted by being fast paths: a command called with
  explicit arguments (`:PKMViewDelete <name>` confirms exactly as its panel
  does) and a "force" variant of an existing key. A force key may skip the
  question when nothing is at stake — closing a saved buffer costs nothing —
  but never when it is the difference between the key and its gentler sibling.
  That gap is what `D` in the buffer panel was: `bdelete!` straight through,
  unsaved edits gone without a word.

  Genuinely exempt, and only these: changes confined to a buffer that `u`
  reverses (`:PKMRemoveTag` writes nothing to disk), and automatic maintenance
  the user configured in advance (`trash.max_age_days` purging on startup),
  which reports rather than asks. A flow whose confirmation *is* its panel — a
  preview list plus `<CR>`, as every `tags` batch has — already satisfies this;
  it does not need a second dialog on top, only a title that names the removal.
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
   first. Tag only after step 5 passes, never before. The exception is a smoke
   session started with `nvim -u test/min_init.lua`: that points runtimepath at
   this working tree, so it needs neither push nor sync — which is precisely
   why it cannot stand in for the smoke of step 5, run in the real config.
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

### What a check has to prove

Learned building the first smoke route, at the cost of a defect that shipped
past a test written to catch it.

-   **A check must start where the candidate readings diverge.** The assertion
    for `:PKMHeaderNext`'s level argument started at a line where "the second
    header ahead" and "the first level-2 header ahead" were the same line. It
    passed for months of nothing while the command read the level as a count.
    Before writing an assertion, name the wrong behaviour it is meant to exclude
    and pick an input where the two answers differ — otherwise the test asserts
    that the code runs, not that it is right.
-   **`normal!` ignores mappings.** Verifying a keymap with `vim.cmd('normal!
    ]h')` exercises the built-in `]` and `h`, never the mapping, and reports a
    cursor that did not move as if the feature were broken (or, worse, one that
    did as if it worked). Keymap checks use `normal` without the bang; the
    function behind the mapping is checked separately.
-   **A route is an assertion, and a cheaper one than it looks.** Simulating the
    smoke note found what the test suite did not, because a route only completes
    when every step lands where it claims — there is no line to compare, so
    there is nothing to get wrong in the comparison.
-   **When something else writes the same state, assert the source, not the
    value.** The v1.10.1 control claimed a modeline had fired by reading
    `shiftwidth`, but markdown's own ftplugin writes `shiftwidth` too — so the
    expected value could arrive from the wrong author, and the unexpected one
    could mean either "it never fired" or "it fired and was overwritten".
    `:verbose set` names who set it, which is what the check was actually
    claiming. The smoke pass caught this, not the suite: the author ran the
    control in a session with an ftplugin the headless run did not have.
-   **A probe must not answer itself.** `vim.fn.execute('messages')` includes
    the script's own `print` output, so searching it for `E518` after printing
    a label containing `E518` matches the label — every later check then reads
    `true` for free. Search for the error's *text*, or capture before printing.

### The smoke note — the checklist is the terrain

A phase that needs specific material to be smoke-tested (headers at several
levels, nested lists, a citation graph) gets that material **written for it in
advance**, as a note in the test vault `P:\Note-Vault\00 - NotesTeste` — never
in the primary vault, `P:\Note-Vault\01 - Vitruvia`.
Without it the author either hunts for a note that happens to have the right
shape or drafts one by hand before being able to test at all.

The note is not a list of instructions with a fixture underneath. It is a
**route**: performing a step lands the cursor on the text of the next one.

-   **Each landing carries the next step.** Step 3 is written at the place step 2
    delivers you to, because that is where the eyes already are. A step that
    lands somewhere with no instruction is a dead end and the route is wrong.
-   **A route that only completes when the feature works is itself the
    assertion.** A checklist read top to bottom proves nothing about where the
    cursor went; a route stalls the moment a jump misses, and the reader knows
    exactly which step broke without comparing anything against a table.
-   **Each landing first says what just happened**, naming what should have been
    skipped and where it was, and only then commands the next move.
-   **Traps denounce themselves.** A line that must be skipped says so in place:
    *"se você chegou aqui, o passo 4 não manteve o nível"*. When the trap cannot
    carry text — the point of the line is that it is *not* a heading — the next
    landing names it and says how far above it sits.
-   **Never revisit a landing**, or the reader arrives at an instruction already
    spent — unless the round trip *is* the step, written as one instruction
    ("go there, confirm, come back with `<C-o>`"), so the old landing is passed
    through rather than consulted. Steps that leave the note (a `:enew`, a
    fresh buffer) go last.
-   **Say what the smoke cannot see**, in the note, pointing at the headless test
    that covers it — a case that is deliberately absent must not read as an
    omission.
-   **Simulate the route before handing it over.** Execute the real keys and
    commands over the real file and check that every landing is the intended
    one. The note is a claim about behaviour; claims get verified, not asserted.
-   **The note is disposable and says so.** It carries the smoke tag/view, so a
    later phase reaches its predecessors in one place.

For a feature whose operation does not move the cursor, the landing is whatever
the operation leaves visible — the panel row, the renamed file, the reloaded
buffer. The rule is unchanged: the next step must be readable from the state the
previous step produced.

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
