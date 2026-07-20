# CLAUDE.md — Claude Code operating guide for PKM.nvim

This file is the entry point Claude Code reads on every session in this repo.
It is deliberately thin: it does **not** restate architecture, rules, or history
that other documents already own (single-ownership discipline — see
`doc/LLM_PROJECT_INSTRUCTIONS.md`). It adds only the layer specific to operating
through Claude Code: how to read, edit, verify, and hand work back.

---

## Read before acting

These are authoritative. Read the relevant ones before proposing or making any
change; do not rely on memory, on training data, or on this file for anything
they own.

- `doc/LLM_PROJECT_INSTRUCTIONS.md` — coding standards, module structure, review
  protocol, source-of-truth ordering, changelog/doc cadence, explanation style.
- `doc/LLM_CONTEXT.md` — fast-read session brief: current version, module map,
  non-negotiable code rules, established patterns, git workflow, environment.
- `doc/PHILOSOPHY.md` — scope constraints. A change that violates a principle is
  out of scope regardless of how useful it seems in isolation.
- `doc/ARCHITECTURE.md` — codebase layout, module responsibilities, config shape.
- `doc/ROADMAP.md` — forward plan (phases, release plan) and the **Standing
  Verification Protocol** (the required check order).
- `doc/CHANGELOG.md` — version history, known bugs, dead code, suspended
  functions, pending decisions. Check Known Bugs before proposing any fix.

Source-of-truth order for how code *currently behaves*: a file read live from
disk in this session > the knowledge-base copy > documentation. If sources
conflict, say so explicitly rather than silently choosing one.

---

## Fixed facts (never reconstruct from memory)

- Repo root — WSL: `/mnt/p/Active/pkm-nvim`  ·  Windows: `P:\Active\pkm-nvim`
- Git remote name: `pkm-nvim` (**not** `origin`). Dev branch: `dev`. Release
  branch: `main`.
- Reference materials (read-only): `/mnt/p/Recursos/<subpasta>` /
  `P:\Recursos\<subpasta>` — e.g. *Programming in Lua, 4th ed.* Consult for
  language semantics; the Lua 5.4 manual remains the higher authority.
- The notes vault `P:\Notes` and the "Agregador de Questões" project belong to
  **other** workflows. Never read, write, or reason about them while developing
  this plugin.

---

## Absolute rules

1. **Never run `git gc`, `git repack`, `git prune`, or `git maintenance`.** The
   repo lives on Google Drive sync; object-database rewrites corrupt it.
   (`.claude/settings.json` also denies these, and `gc.auto=0` is set globally.
   This rule is the human-readable backstop, not the only guard.)
2. **Never commit to `main`, and never push, tag, or merge without an explicit
   instruction in the current turn.** Default working branch is `dev`. Pushing
   prematurely breaks the Standing Verification Protocol, which requires
   commit → push → `:Lazy sync` → verify → *then* tag.
3. **Every `Edit` anchor comes from a read done in this session**, ideally the
   read immediately preceding the edit — never an `old_string` reconstructed
   from memory of an earlier read. An `Edit` that fails on a bad anchor is the
   symptom of this error; re-read, do not retry from memory.
4. **Never cite a line number from memory.** `grep -n` (or read) to obtain the
   real number, then act on that specific span.
5. **Never report a result you did not produce.** Do not claim a test passed, a
   file compiles, or a command succeeded without running it and reading its
   output. No fabricated diffs, counts, or outcomes.
6. **One pass per file per phase.** All edits to a file within a phase must be
   mutually compatible and verifiable together (ROADMAP operating principles).
   Do not touch a file a second time in the same phase.
7. **Do not edit a source file the user currently has open with unsaved changes
   in Neovim.** If you cannot tell, ask. (Lazy loads the plugin from GitHub, so
   working-tree edits never reach the running plugin — but they can still
   collide with an unsaved buffer on the next `:w`.)
8. **Respect the non-negotiable code invariants** in `doc/LLM_CONTEXT.md` (e.g.
   never `index.invalidate` from buffer-only metadata paths; never strip
   backlinks in `trash_note()`; never register `UndoPost`; `TextChanged*` parses
   synchronously; always `utils.join`/`utils.normalize` for paths; Telescope
   checked at call time; never optimize without a `bench.lua` baseline). Restate
   the invariants a phase touches before editing it.

---

## Per-task loop

1. **Read** the target module(s) live from disk, plus the relevant docs
   (LLM_CONTEXT patterns, CHANGELOG known bugs).
2. **State the plan**: which files, which functions, and the expected change
   scope (how many files / hunks). This is the baseline for step 4.
3. **Edit** — anchors per Rule 3; standards per LLM_PROJECT_INSTRUCTIONS (header
   block, section separators, LuaDoc on exported functions, `local`-by-default,
   explicit nil handling, current Neovim API, 2-space indent).
4. **Verify**, in this order:
   - `git diff --stat` then `git diff` — read what actually changed.
   - **Reconcile** the real diff against the scope stated in step 2. More files
     or hunks than intended is *your* error — investigate before continuing;
     never rationalize the count to fit.
   - `luacheck lua/pkm/<changed>.lua` on each changed file (configured for
     LuaJIT — see Verification commands). Do **not** use PUC `luac -p`: the
     installed Lua is 5.1.5, which rejects `goto`, a construct both this
     codebase and Neovim's LuaJIT runtime accept.
   - The phase's headless test (see Verification commands).
5. **Report** deliverables first, reasoning after. Show the real command output.
   Flag any bug found-but-not-asked-about clearly and add it to CHANGELOG Known
   Bugs, but do not fix it unless asked; if it risks data corruption or silent
   failure, say so explicitly.
6. **Stop before commit/push/tag/merge** — those are user-gated (Rule 2). Update
   `doc/CHANGELOG.md` / `LLM_CONTEXT.md` / `ROADMAP.md` on the version cadence
   (batched after a completed version), not mid-phase, unless asked.

---

## Verification commands

Run from repo root. Tests never touch the live Notes tree — `test/min_init.lua`
uses a disposable temp root and points runtimepath at *this working tree*, so it
exercises your just-made edits (unlike Lazy, which loads the plugin from GitHub).

```sh
# Phase test — disposable temp root; exercises THIS working tree
nvim --headless -u test/min_init.lua -c "luafile test/test_<phase>.lua" -c "qa!"

# Static analysis + parse, LuaJIT dialect (needs a .luacheckrc with
# std = "luajit" and globals = { "vim" }). Also catches syntax errors.
luacheck lua/pkm/<file>.lua

# Zero-install parse check via Neovim's own LuaJIT (accepts `goto`); prints the
# error on failure, always quits. Use when luacheck is unavailable.
nvim --headless --clean -c "lua local f,e=loadfile('lua/pkm/<file>.lua'); if not f then print(e) end" -c "qa!"

# NOTE: do not use PUC `luac -p` as the parse check — Lua 5.1.5 rejects `goto`,
# which LuaJIT (Neovim's runtime) accepts, so it produces false failures.

# Read-only inspection (runs without a prompt in any mode)
git status ; git diff ; git diff --stat ; git log --oneline -n 20
```

---

## Stop and ask when

- A requirement is ambiguous, or the target module/function is unclear.
- Sources of truth conflict (live file vs. knowledge base vs. docs) — surface
  the conflict, do not silently pick one.
- An operation could overwrite or delete existing content without it being
  clearly intentional.
- A change would violate a `doc/PHILOSOPHY.md` principle — propose a compliant
  version, or record it under ROADMAP *Postponed / Out of Consideration* with
  the principle it touches.
- The reconciliation in step 4 does not match the plan in step 2.
