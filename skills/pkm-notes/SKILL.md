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
-- create a note (ALWAYS pass by='claude' — it stamps your authorship)
api.create('note', { title = 'AFO audit', by = 'claude', tags = { 'afo' } })
--   → { ok=true, path=…, number=…, filename='…_ByClaude_…', tags={…,'by-claude'} }

api.cite(source, target_ref)   -- link two notes (keeps both sides of the graph)
api.tag(paths, { add = { 'x' }, remove = { 'y' } })   -- bulk retag
api.query('tag:afo AND type:note')   -- filter the index → { ok, matches }
api.get(path)                  -- one note's index entry
api.audit()                    -- vault-integrity findings (read-only)
api.delete(path)               -- guarded: removes only notes YOU authored, trashes them
api.actions()                  -- discover the enumerable bulk operations
```

See `PKM_API.md` for the complete list and every return shape.

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

## When in doubt

Prefer the action with the most effect and least structural impact — often a note
in your own vault, or a citation, over editing a user's note. Read
`AGENT_PROTOCOL.md` before acting in a user's vault.
