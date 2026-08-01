# PKM.nvim — `pkm.api` reference and invocation contract

*The programmatic surface an assistant or script drives the vault through. This
is the reference for `lua/pkm/api.lua` and the contract for calling it headless.
Policy — when and why an assistant uses it — lives in `doc/AGENT_PROTOCOL.md`;
this document is the mechanism.*

`require('pkm.api')` returns **data, never UI**. Every function is callable from
`nvim --headless`, so the surface is scriptable and testable without a screen.
It **wraps the existing cores** (it is a stable naming, not a second
implementation), and every write **reports what it changed** and keeps the index
in step — confirmation belongs to the interactive commands, so nothing here
acquires a prompt.

---

## Return convention

- **A write returns a table** `{ ok = boolean, … }`. On failure `ok = false` and
  `error` holds a one-line reason. On success the other fields carry the result
  (`path`, `applied`, `removed`, …).
- **A read returns its data directly** — an entry table, an array, a string, or
  `nil`.
- **Everything returned is plain data** (no functions), so any result is
  `vim.json.encode`-able. This is why `actions()` returns `{ id, label }` rows
  with the `run` closure stripped.

---

## Invocation

### From Lua, inside a running Neovim

```lua
local api = require('pkm.api')
local res = api.create('note', { title = 'Alpha', by = 'claude', tags = { 'foo' } })
-- res = { ok = true, path = '…/0007_note_ByClaude_Alpha.md', number = 7, … }
```

### Headless, returning JSON (the external contract)

An assistant running in a terminal shells out to Neovim, prints the JSON, and
quits. The one requirement is an init that puts pkm on the runtimepath and points
it at the vault — either the user's own config, or a minimal init:

```lua
-- pkm-init.lua  (minimal; assumes pkm is installed on the runtimepath)
vim.opt.runtimepath:append('/path/to/pkm-nvim')   -- omit if a plugin manager already adds it
require('pkm').setup({ root_path = '/path/to/Note-Vault/02 - LLM-Claude' })
```

Then any function is one command. **Quote the whole `-c` argument** (vault paths
contain spaces), and JSON-encode the result:

```sh
# create a note in the assistant's own vault
nvim --headless -u pkm-init.lua \
  -c "lua print(vim.json.encode(require('pkm.api').create('note', { title = 'Alpha', by = 'claude' })))" \
  -c "qa!"
# → {"ok":true,"path":"…/0007_note_ByClaude_Alpha.md","number":7,"filename":"0007_note_ByClaude_Alpha.md","title":"Alpha","tags":["by-claude"],"author":"Claude"}

# audit the vault
nvim --headless -u pkm-init.lua \
  -c "lua print(vim.json.encode(require('pkm.api').audit()))" -c "qa!"

# query
nvim --headless -u pkm-init.lua \
  -c "lua print(vim.json.encode(require('pkm.api').query('tag:direito AND type:note')))" -c "qa!"
```

**Vault selection.** The vault is whatever the init's `root_path` names, or the
registry default, or `$PKM_VAULT` — nothing outside the registry names a vault.
An assistant defaults to writing in its own vault; writing in another is an
explicit choice of `root_path` (see `doc/AGENT_PROTOCOL.md` § 5).

**Batch a task into one session.** Every headless launch starts cold and builds
the index on first use, so several operations belong in *one* invocation — chain
`-c "lua …"` calls or run one `lua` block — rather than one process per call. The
index then builds once and stays warm for the whole task; the saving grows with
vault size and applies to every `find`/`query`/`find_all`. (This is why a
persistent on-disk index is not needed yet — `doc/ROADMAP.md` Area 1.)

*A single-entry dispatcher (`pkm.api.cli(fn, json_args)`) is deliberately not
added yet; the raw form above is enough until the skill shows a concrete need.*

---

## Function reference

Grouped by domain. `path` arguments accept an absolute path; citation-taking
arguments (`target_ref`, `ref`) accept a `note[0042]` token, an identifier, or a
path.

### Notes

| Function | Returns |
|---|---|
| `create(note_type, opts)` | `{ ok, path, number, filename, title, tags, author }` — `note_type` is `"note"`/`"agg"`/`"bib"`; `opts = { title?, by?, tags?, body?, source_author?, source_type? }`. `body` (string or list of lines) populates the note; `by` stamps the authorship demarcation (§ 7). Headless: no prompt, no buffer opened. |
| `set_body(path, content)` | `{ ok }` — replace a note's body (the prose after the frontmatter); the frontmatter is preserved and the citation graph is reconciled to the new body. Refuses behind an unsaved buffer. |
| `append_body(path, content)` | `{ ok }` — add to a note's body, same rules. |
| `insert_section(path, heading, content, opts)` | `{ ok }` — write into a *named section* (found by heading text); `opts.mode` is `'append'` (default) or `'replace'`. Frontmatter preserved, graph reconciled. |
| `annotate(ref, content, opts)` | `{ ok }` — add a **marked comment** to a note that is **not** your own. The `By <Author>: ` marker is applied for you (not optional) and the block lands at a boundary — the end of `opts.heading`'s section, or the note's end — never inline. `opts = { heading?, by? }` (`by` defaults to `claude`). It writes only your block; the user's text is untouched. Authorisation is the caller's (see §§ 5.3, 7 in `doc/AGENT_PROTOCOL.md`); this supplies mechanism + marker, not permission. |
| `rename(ref, new_name)` | `{ ok, path, filename, title }` — rename a note. A consolidated note keeps its number and type prefix; `new_name` is the *human* part only, sanitised for you. Propagates through every citation. Headless twin of `:PKMNote rename`. |
| `changetype(ref, new_type)` | `{ ok, path, filename, type, title }` — change a consolidated note's type (`"note"`/`"agg"`/`"bib"`); renames the file to the new prefix and propagates through citations. Twin of `:PKMNote changetype`. |
| `transpose(ref, target, opts)` | `{ ok, path, filename, type, title, original_deleted }` — move a note to another PKM type (`target` = `"note"`/`"journal"`/`"scratchpad"`). This is both **promote** and **transpose**: the original is deleted unless `opts.keep_original`. For `target="note"`, `opts.subtype` picks note/agg/bib and `opts.title` names it. Twin of `:PKMNote promote`/`transpose`. |
| `delete(path)` | `{ ok, author, trashed }` — through the guard: refuses any note with no `By<Author>` marker, and trashes rather than hard-deletes. |
| `authored_by(path)` | the agent author read from the filename, or `nil` for a human note. |

### Citations

| Function | Returns |
|---|---|
| `cite(source, target_ref)` | `{ ok }` — appends the citation and syncs both sides of the graph. Idempotent. |
| `uncite(source, target_ref)` | `{ ok, removed }` — removes every citation to the target; `removed` counts the tokens taken out. |
| `cite_source(citing_ref, source, opts?)` | `{ ok, bib = { path, number, title, created }, cited, heading, token }` — record a **source**: find its bib note (by `source.title`, exact then substring, among indexed `bib` notes) or **create** one (`source.bibtex` at the top, optional `source.notes`, `by` default `claude`), then cite it. Places the token under `opts.heading` (default `References`, created if absent) or, with `opts.heading = false`, at the body's end. Idempotent (`cited = false` if already present). Single-vault, like every citation. |
| `resolve(ref)` | `{ ok, identifier, type, short_id, path, title }` — resolve a reference to the note it names. |

### Tags

| Function | Returns |
|---|---|
| `tag(paths, ops)` | `{ ok, applied, errors }` — apply `{ add?, remove?, rename? }` across notes, writing to disk. |
| `tag_preview(paths, ops)` | `{ path, before, after }[]` — what `tag` would change, touching nothing. |
| `tag_note(path, ops)` | `{ ok }` — one named note; refuses to run behind an unsaved buffer. |
| `rename_tag(from, to)` | `{ ok, applied, errors }` — rename a tag across the whole vault. Renaming onto a tag that already exists **merges** the two (deduplicated); this is the vault-wide "merge tags" operation. `applied` counts the notes changed. |

### Query (read-only)

| Function | Returns |
|---|---|
| `find(term)` | `{ ok, term, views, tags, notes }` — case- and accent-insensitive search across view names, tags, and titles at once, in the **active** vault. The first call for "where are the notes about X", since a subject is often a *view*, not a tag. `notes` are **relevance-ranked** (each with a `score`, best first: exact title > prefix > word-boundary > substring > filename, a matching tag boosting, recency breaking ties); `tags` lead with the exact match. |
| `find_all(term)` | `{ ok, term, vaults }` — the **cross-vault** twin of `find`: sweeps every registered vault (and the active root), grouping matches per vault (`{ vault, number, root, active, notes, tags }`), each vault's `notes` **relevance-ranked** with a `score` exactly as `find`. Answers "which of my vaults holds X". Reads non-active vaults from disk without switching the active root (`index.scan_root`); matches titles/filenames/tags, not views. |
| `get(path)` | the index entry, or `nil`. |
| `read(ref)` | `{ ok, path, title, note_type, tags, author, body, cites, cited_by }` — one note **in full**: its body plus its **resolved** citation edges (`cites`/`cited_by`, each `{ ref, title, path, note_type }`). The retrieval atom for "retrieve before working" (§ 11.6); accepts a path or a citation reference. |
| `neighborhood(ref, opts?)` | `{ ok, seed, notes }` — the citation-connected **neighbourhood** of a note as readable entries (`{ path, title, note_type }`), walking the graph to `opts.cites_depth` / `opts.cited_by_depth` (default 1 each). The seed is returned separately and excluded from `notes`. Built on `export.collect_deep`; single-vault. |
| `notes()` | every index entry, as an array. |
| `query(expr)` | `{ ok, matches }` — entries matching the filter DSL (as `:PKMBrowse`). |

### Views

| Function | Returns |
|---|---|
| `views()` | the view registry. |
| `view_members(name)` | the note paths matching a named view's full filter chain. |
| `set_membership(path, view_name, kind)` | `{ ok }` — add/remove a note from a view by writing the tags that define it. `kind` is `"add"`/`"remove"`. Returns an error (never a prompt) when the view is not a single-way tag condition. |
| `save_subproject(name, parent, filter_expr)` | `{ ok }` — save a sub-view under an existing parent, defined by a filter expression. Fails if the parent is missing or the filter does not parse. |

### UI state (read)

| Function | Returns |
|---|---|
| `ui_state()` | `{ current = { buf, name, title?, type? }, sidebar = { open, cursor?, highlighted?, highlighted_view?, lines? }, bufpanel = { open } }` — a plain-data snapshot of the interactive UI. The *inspect* half of agent-assisted smoke testing: drive the real mappings with `feedkeys` in a headless Neovim, then read this to assert the path behaved. Opens nothing. |

### Audit

| Function | Returns |
|---|---|
| `audit()` | `{ kind, severity, path, message }[]` — vault-integrity findings, errors before warnings. Read-only. |

### Export

| Function | Returns |
|---|---|
| `collect(seed_paths, opts)` | `string[]` — the citation neighbourhood of the seeds within the depth budget (`{ cites_depth?, cited_by_depth? }`). Pure. |
| `export(paths, dest)` | `{ ok, copied, errors, dest }` — copy notes into a directory. |

### Vault

| Function | Returns |
|---|---|
| `vaults()` | every registered vault. |
| `active_vault()` / `default_vault()` | the active / default vault. |
| `vault_of(path)` | the vault a path belongs to. |

### Actions (enumerable bulk operations)

| Function | Returns |
|---|---|
| `actions()` | `{ id, label }[]` — the bulk operations the plugin exposes, so an assistant can *discover* them. JSON-safe. |
| `run_action(id, paths, ctx)` | run one bulk operation by id over a list of notes, without the picker. |

---

## Authorship

`create` with `by = <agent>` stamps authorship three ways
(`doc/AGENT_PROTOCOL.md` § 7): the `By<Author>` filename marker, the `author`
frontmatter field, and the queryable `by-claude` tag. `delete` honours the
filename marker — the one signal that survives a copy or a move between vaults.

## Coverage

The surface above is the base layer; it grows as the protocol's operations are
wrapped. The note-lifecycle writes (`rename`, `changetype`, `transpose` — the
last covering both promote and transpose), the view-membership writes
(`set_membership`, `save_subproject`), and the vault-wide `rename_tag` (which
subsumes `tags.merge`) landed in v1.18.0. The marked-comment write into a
*user's* note (`annotate`) landed in v1.19.0. The UI snapshot (`ui_state`) landed
in v1.20.0. The find-or-create source citation (`cite_source`) landed in v1.22.0.
Cross-vault search (`find_all`) landed in v1.23.0, relevance ranking in v1.24.0,
and the retrieval reads (`read`, `neighborhood`) in v1.25.0. Still not exposed (use
the interactive commands, or a later increment): the in-place `convert` normaliser
and the vault lifecycle (create/merge/split). Track additions here as they land.
