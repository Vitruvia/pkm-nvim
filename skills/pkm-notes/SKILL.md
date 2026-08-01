---
name: pkm-notes
description: >-
  Operate a PKM (personal knowledge management) vault through pkm-nvim's pkm.api —
  create, cite, tag, query, and audit notes, as your own durable memory or to
  assist the user's tasks. Use whenever you are working with pkm-nvim notes,
  journals, or vaults, or when you need memory that persists across sessions.
  The core rule: drive the vault through pkm.api, never by editing note files
  directly.
---

# Operating a PKM vault (pkm-nvim)

You have a knowledge vault reachable through **`pkm.api`**, a programmatic surface
over the pkm-nvim plugin. It is your durable memory and the safe way to read and
change notes. Full policy is in `AGENT_PROTOCOL.md`; the function reference is in
`PKM_API.md` (both bundled in this skill directory).

## The one rule

**Every state change goes through `pkm.api`. Never create or edit a note by
writing the file directly.** A note is not just text: it has an allocated number,
a schema-correct frontmatter, a bidirectional citation graph, and an authorship
marker. Editing files by hand bypasses all of that — it hand-picks numbers (that
collide), hand-copies frontmatter (that drifts), leaves the graph empty, and
strips your authorship. That failure is exactly why this surface exists. When the
API cannot express something, say so and ask — do not fall back to raw file edits.

**Prose is not off-limits — it goes through the API too.** Populate a note with
`create(…, body = …)`, and edit prose with `set_body` / `append_body`; the
frontmatter and the citation graph stay managed for you. You never need to touch
the file directly to write content. Citations are the one thing that is *not*
free prose: add them with `cite`, not by hand-typing tokens.

## How to call it

You are in a terminal; drive Neovim headless. `require('pkm.api')` returns data
(JSON-encodable) and never opens UI.

```sh
nvim --headless -u <init> \
  -c "lua print(vim.json.encode(require('pkm.api').<fn>(<args>)))" -c "qa!"
```

- **`<init>`** loads pkm-nvim and selects the vault: the user's own Neovim config,
  or a minimal init — `require('pkm').setup({ root_path = '<vault path>' })`.
  **Quote the whole `-c`**; vault paths contain spaces.
- A **write** returns `{ ok, … }`. If `ok` is false, read `error`, stop, and
  report — never retry blindly or edit the file instead.
- A **read** returns its data directly.

## Core operations

```lua
-- create a note WITH ITS BODY (ALWAYS pass by='claude' — it stamps authorship)
api.create('note', { title = 'AFO audit', by = 'claude', tags = { 'afo' },
                     body = 'What I learned…\n\n## Detail\n…' })
--   → { ok=true, path=…, number=…, filename='…_ByClaude_…', tags={…,'by-claude'} }

api.set_body(path, text)       -- replace a note's prose (frontmatter preserved) — YOUR OWN notes
api.append_body(path, text)    -- add to a note's prose — YOUR OWN notes
api.annotate(ref, text, { heading = 'Notes' })  -- add a By-Claude-marked comment to a USER's note (with permission)
api.rename(ref, new_name)      -- rename, keeping a consolidated note's number/type prefix
api.changetype(ref, 'agg')     -- change a consolidated note's type (note|agg|bib)
api.transpose(ref, 'journal')  -- move a note between folders (promote/transpose)
api.cite(source, target_ref)   -- link two notes (keeps both sides of the graph)
api.tag(paths, { add = { 'x' }, remove = { 'y' } })   -- bulk retag
api.find('afo')                -- search views + tags + titles at once — START HERE for "where is X"
api.views()                    -- list projects/views — a subject is often a VIEW, not a tag
api.view_members(name)         -- the notes in a view
api.query('tag:afo AND type:note')   -- filter the index → { ok, matches }
api.get(path)                  -- one note's index entry
api.notes()                    -- every note (sample to find the real tag spelling)
api.audit()                    -- vault-integrity findings (read-only)
api.delete(path)               -- guarded: removes only notes YOU authored, trashes them
api.actions()                  -- discover the enumerable bulk operations
```

See `PKM_API.md` for the complete list and every return shape.

## Finding notes

- **Start with `api.find('term')`** — it searches view names, tags, and titles at
  once, case- and accent-insensitively. A subject is often a **view** (a saved
  filter), not a tag (searching `afo` finds the *AFO view*, not the tag
  `administração-financeira-orçamentária`), and `find` surfaces all three so you
  do not miss it. Then read `api.view_members(name)` or re-`query` with the real
  tag it reported.
- **A bare `query('tag:x')` that comes back empty is ambiguous** — "absent" or
  "wrong key". Never conclude a subject is absent from an empty tag query; run
  `find` first.

## Cross-vault references do not exist

Vaults never share a citation graph (a hard design rule). A `[Vault::note{xxx}]`
reference is inert descriptive text, **never** a real edge — and this is **not** a
permission-gated operation you may propose. Do not attempt to create cross-vault
citations. Only if the user *explicitly* asks to link across vaults: first offer
alternatives (summarise-and-cite *within* your own vault; or an inert descriptive
pointer), and explain the cost — it breaks the single-namespace guarantee, the
citation engine cannot maintain it, and it desyncs on any rename. To bring another
vault's knowledge across, read it and write your own note that cites within your
vault.

## Authorship — always mark your work

Create with `by = 'claude'`. It stamps three signals: the `By<Author>` filename
marker, the `author` frontmatter field, and the queryable `by-claude` tag. **Never
create a note without it.** When you add a comment to a note you did not author,
begin it with `By Claude: `.

## Safety and modes

- **Write in your OWN vault by default.** Working in a user vault is an explicit
  choice of `root_path`, and needs the permission the task grants.
- **Never delete or modify user-authored content** without explicit permission for
  that act. Deletion goes through `api.delete`, which refuses any note lacking your
  filename marker and trashes rather than destroys.
- **User mode** (your own vault + authorized others; read/append/create,
  non-structural) vs **Manager mode** (reorganising a vault — create/delete/move/
  rename of notes, views, tags — always with the user's approval). Every removal
  confirms. Details in `AGENT_PROTOCOL.md`.
- **You are not the developer of pkm-nvim.** If you find a plugin bug or a missing
  capability, record it for the developer; do not edit the plugin from a vault
  session.

## Memory and the vault

The vault **enhances** your memory, it does not replace it. Keep using your
ordinary memory as always; the vault adds *extent and structure* — knowledge kept
across many disciplines, organised for method-based retrieval (RAG/OKF). Quick
local facts → ordinary memory; a growing, cross-referenced body of knowledge →
the vault.

**Long-term learning has a session mode** (`/pkm-learning off|on|expanded`):
`off` writes to neither; `on` (default) writes to ordinary memory as usual;
`expanded` writes to **both** memory and the vault when pertinent. There is no
"vault only". This governs *background* learning only — a task explicitly asking
for vault notes proceeds regardless.

## Writing into notes

- **The body is yours to write; the frontmatter and citations are not.** Add prose
  with `create(body=…)`, `set_body`, `append_body`; add citations with `cite`.
- **Build your vault as a graph, not a pile.** When your own notes relate, link
  them with `cite` *within your vault* — that interconnection is what makes the
  vault more than flat memory and what lets structured retrieval (RAG/OKF) work.
  (Only *cross-vault* links are forbidden; linking your own notes to each other is
  encouraged.)
- **Place content where it belongs** — `insert_section(path, heading, text)` adds
  under a named section (or `mode='replace'` to swap its body); `append_body` adds
  at the end; `set_body` rewrites the whole prose. Not scattered inline.
- **Your own notes:** write freely with `set_body`/`append_body`/`insert_section`.
  **A user's note:** add content only with permission, and use **`annotate`** —
  `annotate(path, text, { heading = … })` — which bakes in the `By Claude: ` marker
  and places the block at a boundary for you. Do **not** use `set_body`/
  `append_body` on a user's note. **Changing what the user wrote** is never a
  default — only under an explicit task (grammar, reformat), preserving meaning,
  and reversible.

## When in doubt

Prefer the action with the most effect and least structural impact — often a note
in your own vault, or a citation, over editing a user's note. Read
`AGENT_PROTOCOL.md` before acting in a user's vault.
