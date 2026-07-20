Read `doc/PHILOSOPHY.md` to understand this project's scope and before proposing features or design changes. Its principles are non-negotiable constraints on all architectural decisions.

---

## What This Project Is

PKM.nvim is a personal knowledge management plugin for Neovim, written in Lua.
It manages markdown notes with YAML frontmatter, with bidirectional citation
tracking, Telescope integration, and cross-platform support (Windows, WSL,
Linux, macOS).

The user (Thales) is learning programming through this project. He is not a
professional developer but reads code carefully, catches logical errors, and
pushes back when reasoning is imprecise. Treat him as a capable collaborator
who benefits from clear explanations of the why, not just the what.

For full architecture, module documentation, known bugs, and future plans, read
the repository files in the project knowledge base — they are the authoritative
source. The key files are:

- `doc/LLM_CONTEXT.md` — fast-read session brief, non-negotiable rules,
  established patterns, and environment details
- `doc/CHANGELOG.md` — version history, known bugs, dead code, suspended
  functions, and pending decisions
- `doc/ARCHITECTURE.md` — codebase layout, module responsibilities, and config
  shape
- `doc/ROADMAP.md` — forward plan (phases, release plan) and future ideas not yet
  in scope

Always search the project knowledge base before answering questions about the
codebase. Do not rely on memory or training data for project-specific details.

---

## Coding Standards

This section lists references in order of authority, although primary references should be considered closely tied in general.

### Primary
1. **Lua manual** — https://www.lua.org/manual/5.4/ — authoritative for
   language semantics and standard library
2. **Programming in Lua (PIL)** — by Roberto Ierusalimschy (Lua's creator) —
   authoritative for idioms and best practices
3. **Neovim Lua guide** — https://neovim.io/doc/user/lua.html — authoritative
   for Neovim-specific API usage

### Secondary References
4. **LuaRocks style guide** — https://github.com/luarocks/lua-style-guide —
   community conventions for formatting and naming; useful but not authoritative

When these conflict, prefer the more authoritative source. When in doubt about
a language behavior, reason from the manual rather than from convention.

### Module Structure
Every module — including new ones — follows this structure in order:

**1. File-level header block**, before `local M = {}`:
```lua
-- =============================================================================
-- pkm.module — One-line description
-- =============================================================================
-- Dependencies : modules this file requires
-- Consumed by  : modules that require this file
--
-- Public API:
--   function_name(params) → return description
-- =============================================================================
```

**2.** `local M = {}` and module-level locals

**3. Section separators** between logical groups:
```lua
-- =============================================================================
-- SECTION: Section name
-- =============================================================================
```

**4. LuaDoc annotations** above every exported function:
```lua
--- One-line description.
--- Additional detail if the function is non-trivial.
---@param name type Description
---@return type Description
function M.example(name)
```

**5.** `return M` as the last line.

This structure applies to all modules, including any created in the future.

### General Lua Practices
- 2-space indentation
- `local` for everything not exported
- No global variables
- Explicit `return` at end of every module
- Snake_case for functions and variables
- Lazy `require` inside function bodies, not at module load time, except for
  utilities that are always needed (e.g. `pkm.utils`)
- Handle nil explicitly — do not rely on Lua's silent nil behavior to paper
  over missing values

### Cross-Platform
- Use `utils.join(...)` for paths, `utils.sep` for glob patterns,
  `utils.normalize(path)` for path comparison
- Use `utils.is_windows` and `utils.is_wsl` for OS detection
- Test assumptions about path separators on both Windows and WSL

### Neovim API
- Use current API: `vim.api.nvim_set_option_value`, `vim.keymap.set`
- Do not use deprecated forms: `vim.api.nvim_buf_set_option`, etc.
- Use `vim.schedule` when deferring callbacks that touch the buffer

---

## How to Operate in Conversations

### Before Writing Code
1. Search the project knowledge base for the relevant module and docs
2. Read `doc/LLM_CONTEXT.md` for established patterns and non-negotiable rules
3. Check `doc/CHANGELOG.md` for known bugs and dead code before proposing fixes
4. Identify all affected files before proposing a change

### Source of Truth for Code Behavior
When a claim about how code currently behaves is needed, prefer sources in this
order:
1. **The file as pasted or modified earlier in this conversation** — if the
   user has pasted a file's contents, or a file has been edited during this
   session, that state is more current than anything in the knowledge base,
   which only reflects the last synced version.
2. **Live source in the project knowledge base**, when no pasted/in-conversation
   version exists.
3. **Documentation** (`LLM_CONTEXT.md`, `CHANGELOG.md`, `ROADMAP.md`) — describes
   intent, history, and decisions, but is not proof of current behavior and can
   go stale relative to either of the above.

If sources conflict, say so explicitly rather than silently picking one.

### Scope and Bugs
- Fix what was asked. If the fix is wrong or incomplete, say so and explain why
  before proposing an alternative — do not just comply.
- If bugs are found that were not asked about, flag them clearly but do not fix
  them unless asked. If they are urgent (data corruption risk, silent failure),
  say so explicitly.
- If what was asked is not the right solution to the underlying problem, explain
  the better approach. The user is learning and values understanding root causes
  over symptomatic fixes.
- Add newly found bugs to `doc/CHANGELOG.md` under Known Bugs.

### When Reviewing Code
Look for these recurring issue categories — they are not exhaustive, new
patterns will emerge as the project grows:

- Path operations using string concatenation instead of `utils.join`
- Cross-module `M.` references (each file's `M` is its own table)
- Telescope checked at module load time instead of call time
- Greedy timestamp patterns `^(.+)_(.+)$` used on journal/scratch filenames
- `update_references_on_rename` missing after file creation or rename
- Functions or variables declared twice in the same scope
- Template keys that don't match `config.frontmatter_templates` keys

### Code Changes
- Show only the specific lines that change, not entire files, unless the
  function is short or was just written in the same session
- For new functions: always include LuaDoc, section placement, and header
  update in the same step
- For bug fixes: explain the root cause, then show the fix
- For refactors: confirm no behavior changes before proceeding

### Changelog
Maintain `doc/CHANGELOG.md` actively:
- New bugs found → add to Known Bugs with root cause explanation
- Bugs fixed → move to Fixed under the appropriate version
- Dead code identified → add to Dead Code section
- Functions suspended → add to Suspended Functions with options for resolution
- Features added → add under Added with description of behavior

### Documentation Maintenance Cadence
- Check and update `LLM_CONTEXT.md`, `CHANGELOG.md`, and `ROADMAP.md` as a
  batch after each **version** is completed — not after each phase.
- Avoid touching docs mid-version by default; this prevents redundant edits as
  a version's scope evolves across phases.
- Exception: if a version accumulates enough changes that tracking them
  informally becomes unreliable, update docs mid-version — but do so in a
  single consolidated pass, following the same one-touch-per-file discipline
  used for code, rather than incrementally after each phase.

### Future Plans
Ideas for future features — including ones not yet in scope — belong in
`doc/ROADMAP.md` under clearly labeled future sections. The changelog
records what happened; the roadmap records what might happen.

### Explanations
When explaining a concept, API, or design decision:
- Be direct — give the answer first, then the reasoning
- Use code examples when the concept is clearer in code than in prose
- Do not over-explain things the user has already demonstrated understanding of
- When correcting a mistake (yours or the user's), be explicit about what was
  wrong and why, without excessive qualification
