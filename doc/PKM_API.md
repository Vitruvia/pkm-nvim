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

**Clean stdout.** Under `--headless`, `print` and `vim.notify` go to the message
stream on **stderr**, so JSON printed with `print(vim.json.encode(...))` arrives
mixed with notify lines ("PKMView: saved view …"). Prefer `api.emit(value)`, which
writes only the JSON to **stdout**, and read stdout alone:

```sh
nvim --headless -u pkm-init.lua \
  -c "lua require('pkm.api').emit(require('pkm.api').structure())" -c "qa!" 2>/dev/null
# → {"ok":true,"total_notes":667,"views":[…],"tags":[…]}   (stdout only, parseable)
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
| `merge(survivor_ref, absorbed_ref, opts?)` | `{ ok, survivor, redirected, absorbed_title }` — fold `absorbed` into `survivor`: append its body (under `opts.heading` if given), **redirect** its citation graph onto the survivor (inbound citers re-pointed, the survivor gains the absorbed note's outbound cites), union its topical tags, then trash it. The graph is redirected *before* the trash, so nothing dangles. **Both notes must be assistant-authored.** Destructive — the act on `duplicates`/`unlinked_pairs` findings. |
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
| `context(term, opts?)` | `{ ok, query, seeds, notes }` — the one-call **RAG assembly** for a subject: `find`s the top `opts.seeds` (default 3, relevance-ranked) and expands each by its `neighborhood`, then merges/de-dupes/annotates — `notes` carry `relation` (`'seed'` \| `'linked'`) with seeds first by score, then linked by title. "Retrieve the relevant cluster before working" in one call. Composes `find` + `neighborhood`; single-vault. |
| `notes()` | every index entry, as an array. |
| `query(expr)` | `{ ok, matches }` — entries matching the filter DSL (as `:PKMBrowse`). |

### Views

| Function | Returns |
|---|---|
| `views()` | the view registry. |
| `view_members(name)` | the note paths matching a named view's full filter chain. |
| `set_membership(path, view_name, kind)` | `{ ok }` — add/remove a note from a view by writing the tags that define it. `kind` is `"add"`/`"remove"`. Resolves the view's tag condition **against the note's present tags**, so a subview under an OR parent the note already satisfies is written unambiguously; returns an error (never a prompt) only when the change is genuinely ambiguous (distinct cheapest tag-sets) or the view is not a tag condition. |
| `save_view(name, expr)` | `{ ok }` — save a **top-level** view defined by a filter expression (the parentless twin of `save_subproject`). Replaces an existing view of the same name. Fails when the name is blank or the filter does not parse. |
| `save_subproject(name, parent, filter_expr)` | `{ ok, warning? }` — save a sub-view under an existing parent, defined by a filter expression. Fails if the parent is missing or the filter does not parse. Because a subview AND-composes its parent, it can save yet match **nothing** when the parent excludes all its own notes — that case returns a non-blocking `warning` string (the view is still saved). To *move* an existing subview, use `reparent_view`, not a re-save. |
| `rename_view(old_name, new_name)` | `{ ok }` — rename a view in place, **re-pointing every child's `parent`** so a non-leaf renames without orphaning its subtree (unlike delete-old + save-new). Fails if the new name is taken; a config-defined view can't be renamed here. |
| `reparent_view(name, new_parent)` | `{ ok, warning? }` — move a subproject under a new parent (the explicit "change parent"). Guards against a cycle (a view under its own descendant), a missing parent, itself, and a config-only view. Returns the same empty-composition `warning` as `save_subproject` when the new parent would match **zero** of the child's notes. |
| `delete_view(name)` | `{ ok }` — delete a view from `views.json`. Promptless (the caller owns the confirmation). Deleting a view with children **orphans** them (they re-level to roots) — `reparent_view` them first, or `rename_view`. A config-defined view can't be deleted here. |

**The view/tag model.** A view is a saved **filter over tags** (the same DSL as
`query`). A subview's effective filter is its parent's filter **AND**-ed with its
own, composed down the whole parent chain — so a subview always matches a subset
of its parent. Putting a note "in" a view means giving it the tags the view
filters on; that is why membership needs a view to reduce to a **single defining
tag** (or a set the note already partly satisfies) to be writable — an OR of
alias tags is ambiguous to write (prefer one canonical tag; see
`doc/CONVENTIONS.md` § Tags). Read the whole shape cheaply with `structure()`.

### Structure (compact projection)

| Function | Returns |
|---|---|
| `structure()` | `{ ok, total_notes, views = [{ name, count, depth, parent, has_children }], tags = [{ tag, count }] }` — the view **tree** (roots first, children under each parent; each row carries its `depth`, its `parent`, and `has_children`) with per-view **match counts** (already reflecting each view's full parent AND-chain), the **tag catalog** with per-tag counts, and the note total — *without* dumping every full record the way `notes()` does. The cheap "what is in here / how is it organised" read to make **before** drilling in with `query`/`view_members`. |
| `tag_catalog()` | `{ ok, tags = [{ tag, count }] }` — the tag half of `structure()`, most-used first, for a caller that only needs the vocabulary. |

### Output (headless contract)

| Function | Returns |
|---|---|
| `emit(value)` | writes `value` as **one line of JSON to real stdout** (fd 1) and returns the encoded string. Use this instead of `print(vim.json.encode(...))` in headless invocations: under `--headless`, `print`/`vim.notify` land on the **message stream (stderr)**, so JSON printed that way is interleaved with notify noise. `emit` keeps stdout clean JSON — capture stdout alone (`2>/dev/null`) and it parses. |

### UI state (read)

| Function | Returns |
|---|---|
| `ui_state()` | `{ current = { buf, name, title?, type? }, sidebar = { open, cursor?, highlighted?, highlighted_view?, lines? }, bufpanel = { open } }` — a plain-data snapshot of the interactive UI. The *inspect* half of agent-assisted smoke testing: drive the real mappings with `feedkeys` in a headless Neovim, then read this to assert the path behaved. Opens nothing. |

### Audit

| Function | Returns |
|---|---|
| `audit()` | `{ kind, severity, path, message }[]` — vault-integrity findings, errors before warnings. Read-only. |

### Revision (surfacing what to revise)

| Function | Returns |
|---|---|
| `related_unlinked(ref, opts?)` | `{ ok, note, candidates }` — notes **related to** `ref` but **not linked to it**, ranked, so you can decide whether to `cite`. Three signals: shared tag (2), shared title term (1), and **co-citation** (2 each — a source both notes cite, so notes leaning on the same references surface without a shared tag). Each candidate: `{ path, title, note_type, score, shared_tags, shared_terms, co_citations }`. Already-linked notes and non-topical tags (`by-claude`, near-ubiquitous) excluded. `opts.limit` (10), `opts.min_score` (2), `opts.graph` (true; `false` = cheap index-only, no candidate edge reads). Advisory, read-only; single-vault. |
| `unlinked_pairs(opts?)` | `{ ok, pairs }` — the **vault-wide** twin: every *pair* of notes related but unlinked, ranked — the "review the whole vault for missing links" sweep. Same signals/exclusions as `related_unlinked`, over all pairs via inverted buckets; a bucket (tag / term / shared source) with more than `opts.bucket_cap` (30) members is skipped as non-discriminating. Each pair: `{ a, b, score, shared = { tags, terms, co_citations } }`. `opts.limit` (20), `opts.min_score` (3), `opts.graph` (true). Cost: one read of every note's edges — a deliberate sweep. Advisory, read-only; single-vault. |
| `stale(opts?)` | `{ ok, notes }` — the **review queue** for § 10: substantive `note`/`agg` notes likely to need re-checking, ranked. The strong signal is a **provenance gap** — no references (no bib citation and no `## References`/`## Sources` section) [3] or no date [1]; **age** only ranks among flagged notes (+1/yr, capped), never flags alone unless `opts.min_age_days` is set (then any note older than that is included). Each: `{ path, title, note_type, score, reasons = { no_references?, no_date?, age_days? } }`. Advisory/heuristic — "look again", not "this is wrong". `opts.limit` (20), `opts.min_score` (1). Reads each candidate's frontmatter; single-vault. |
| `duplicates(opts?)` | `{ ok, pairs }` — near-**duplicate** notes: pairs whose content is substantially the same — the candidates for `merge`. Similarity is a weighted Jaccard blend of **body** words (0.5, the truest signal), **title** terms (0.3), and **tags** (0.2), over every pair of substantive `note`/`agg` notes (bodies from the index; all pairs compared, so a body copy under a different title is still caught — quadratic, a deliberate sweep). Each pair: `{ a, b, similarity, body_sim, title_sim, tag_sim }`, most-similar first, at/above `opts.threshold` (0.5). `opts.limit` (10). Advisory, read-only; single-vault. |

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
subsumes `tags.merge`) landed in v1.18.0. Top-level view creation (`save_view`),
the compact projection (`structure` / `tag_catalog`), and the clean-stdout helper
(`emit`) landed in v1.75.0 — with `set_membership` made present-tag-aware so
OR-composed subviews are writable. The marked-comment write into a
*user's* note (`annotate`) landed in v1.19.0. The UI snapshot (`ui_state`) landed
in v1.20.0. The find-or-create source citation (`cite_source`) landed in v1.22.0.
Cross-vault search (`find_all`) landed in v1.23.0, relevance ranking in v1.24.0,
the retrieval reads (`read`, `neighborhood`) in v1.25.0, the RAG assembly
(`context`) in v1.26.0, and the first revision aid (`related_unlinked`) in v1.27.0.
Still not exposed (use the interactive commands, or a later increment): the in-place
`convert` normaliser and the vault lifecycle (create/merge/split). Track additions
here as they land.
