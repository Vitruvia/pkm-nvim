-- =============================================================================
-- pkm.api — the programmatic surface for assistants and scripts
-- =============================================================================
-- Dependencies : pkm.notes, pkm.citations, pkm.tags, pkm.index, pkm.filter,
--                pkm.views, pkm.check, pkm.export, pkm.vault, pkm.actions
-- Consumed by  : LLM assistants (via `doc/AGENT_PROTOCOL.md` + the skill), the
--                headless invocation contract, and advanced users from Lua.
--
-- The stable naming over the existing cores. Three rules make it what the
-- protocol can point an assistant at (`doc/ROADMAP.md` Near goals #4):
--
--   1. Returns data, never opens UI. Every function is callable from
--      `nvim --headless -c "lua ..."` and testable without a screen. Where a
--      core bakes in UI (create_new_note opens a buffer), this layer reaches the
--      headless seam beneath it (notes.write_new_note) instead.
--   2. Wraps cores, never reimplements them. The pure and read-only layers
--      already exist; this is the boundary, not a second copy.
--   3. Writes are auditable and promptless. A write reports what it changed and
--      keeps the index.invalidate discipline (the cores already do); confirmation
--      belongs to the *interactive* twin, so nothing here acquires a prompt.
--
-- Return convention: a write returns `{ ok = boolean, ... }` with `error` set on
-- failure; a read returns the data directly. Everything returned is plain data
-- (no functions), so Layer 2 can `vim.json.encode` it — which is why `actions()`
-- strips the `run` closure from each row.
-- =============================================================================

local M = {}

-- =============================================================================
-- SECTION: Helpers
-- =============================================================================

--- Resolve a note reference to an absolute path. Accepts a filesystem path or a
--- citation reference (`note[0042]`, an identifier, a title-less short id) and
--- falls back to the citation resolver so the caller may pass either.
---@param ref string
---@return string|nil path
local function to_path(ref)
  if type(ref) ~= 'string' or ref == '' then return nil end
  local p = vim.fn.fnamemodify(ref, ':p')
  if vim.fn.filereadable(p) == 1 then return p end
  local item = require('pkm.citations').resolve_citable(ref)
  if item and item.path then return item.path end
  return nil
end

-- Lower-case and strip common (Portuguese) accents, so a search for `afo` or
-- `orcamentaria` still matches `AFO` and `orçamentária`.
local ACCENTS = {
  ['á'] = 'a', ['à'] = 'a', ['â'] = 'a', ['ã'] = 'a', ['ä'] = 'a',
  ['é'] = 'e', ['ê'] = 'e', ['è'] = 'e', ['ë'] = 'e',
  ['í'] = 'i', ['ì'] = 'i', ['î'] = 'i', ['ï'] = 'i',
  ['ó'] = 'o', ['ô'] = 'o', ['õ'] = 'o', ['ö'] = 'o', ['ò'] = 'o',
  ['ú'] = 'u', ['ü'] = 'u', ['ù'] = 'u', ['û'] = 'u',
  ['ç'] = 'c', ['ñ'] = 'n',
}
local function fold(s)
  s = tostring(s or ''):lower()
  for seq, ascii in pairs(ACCENTS) do s = s:gsub(seq, ascii) end
  return s
end

-- =============================================================================
-- SECTION: Notes
-- =============================================================================

--- Create a consolidated note, headless and schema-correct — the safe creation
--- path an assistant must use instead of hand-writing YAML. Wraps
--- `notes.write_new_note`; `by` stamps the authorship demarcation (§7), and
--- `body` populates the note so it is not born hollow.
---@param note_type string  "note" | "agg" | "bib"
---@param opts table|nil  { title?, by?, tags?, body?, source_author?, source_type? }
---@return table  { ok, path?, number?, filename?, title?, tags?, author?, error? }
function M.create(note_type, opts)
  local path, err, meta = require('pkm.notes').write_new_note(note_type, opts)
  if not path then return { ok = false, error = err } end
  return {
    ok       = true,
    path     = path,
    number   = meta.number,
    filename = meta.filename,
    title    = meta.title,
    tags     = meta.tags,
    author   = meta.author,
  }
end

--- Delete a note on an agent's behalf, through the guard: refuses any note that
--- carries no `By<Author>` filename marker, and trashes rather than hard-deletes.
---@param path string
---@return table  { ok, author?, trashed?, error? }
function M.delete(path)
  local ok, res = require('pkm.notes').agent_delete(vim.fn.fnamemodify(path, ':p'))
  if not ok then return { ok = false, error = res } end
  return { ok = true, author = res, trashed = true }
end

--- The agent that authored a note, read from its filename, or nil for a
--- human-authored note.
---@param path string
---@return string|nil author
function M.authored_by(path)
  return require('pkm.notes').agent_authored(vim.fn.fnamemodify(path, ':p'))
end

--- Replace a note's body — the prose after the frontmatter — preserving the
--- frontmatter and reconciling the citation graph. The prose is yours to write;
--- citations are not raw tokens, they go through `cite`/`uncite`.
---@param path string
---@param content string|string[]
---@return table  { ok, error? }
function M.set_body(path, content)
  local ok, err = require('pkm.notes').write_body(vim.fn.fnamemodify(path, ':p'), content, { mode = 'replace' })
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Append to a note's body, under the same rules as `set_body`.
---@param path string
---@param content string|string[]
---@return table  { ok, error? }
function M.append_body(path, content)
  local ok, err = require('pkm.notes').write_body(vim.fn.fnamemodify(path, ':p'), content, { mode = 'append' })
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Write into a *named section* of a note — placement-aware. The section is
--- found by its heading text; `opts.mode` is `'append'` (default, add at the
--- section's end) or `'replace'` (swap its body, keeping the heading).
--- Frontmatter preserved, graph reconciled.
---@param path string
---@param heading string  the heading text, without the leading #'s
---@param content string|string[]
---@param opts table|nil  { mode?: 'append'|'replace' }
---@return table  { ok, error? }
function M.insert_section(path, heading, content, opts)
  local ok, err = require('pkm.notes').write_section(
    vim.fn.fnamemodify(path, ':p'), heading, content, opts or {})
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Rename a note, keeping a consolidated note's number and type prefix and
--- sanitising the human name for you, then propagate the rename through every
--- citation. `new_name` is the *human* part only. Headless twin of :PKMNote
--- rename.
---@param ref string  path or citation reference
---@param new_name string
---@return table  { ok, path?, filename?, title?, error? }
function M.rename(ref, new_name)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  local new_path, err, meta = require('pkm.notes').rename_note_at(path, new_name)
  if not new_path then return { ok = false, error = err } end
  return { ok = true, path = new_path, filename = meta.filename, title = meta.title }
end

--- Change a consolidated note's type (note/agg/bib): renames the file to the new
--- type prefix and propagates through citations. Headless twin of :PKMNote
--- changetype.
---@param ref string  path or citation reference
---@param new_type string  "note" | "agg" | "bib"
---@return table  { ok, path?, filename?, type?, title?, error? }
function M.changetype(ref, new_type)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  local new_path, err, meta = require('pkm.notes').changetype_file(path, new_type)
  if not new_path then return { ok = false, error = err } end
  return { ok = true, path = new_path, filename = meta.filename, type = meta.type, title = meta.title }
end

--- Move a note to another PKM type, writing it into the target folder and
--- propagating citations. This is both promote (scratchpad → note/journal) and
--- transpose (any folder → any other). The original is deleted unless
--- `opts.keep_original` is set. For `target = 'note'`, `opts.subtype` picks
--- note/agg/bib and `opts.title` names it. Headless twin of :PKMNote
--- promote / transpose.
---@param ref string  path or citation reference
---@param target string  "note" | "journal" | "scratchpad"
---@param opts table|nil  { subtype?, title?, keep_original? }
---@return table  { ok, path?, filename?, type?, title?, original_deleted?, error? }
function M.transpose(ref, target, opts)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  opts = opts or {}
  local new_path, err, meta = require('pkm.notes').convert_file(path, target, {
    subtype        = opts.subtype,
    title          = opts.title,
    delete_original = (opts.keep_original ~= true),
  })
  if not new_path then return { ok = false, error = err } end
  return {
    ok = true,
    path = new_path,
    filename = meta.filename,
    type = meta.type,
    title = meta.title,
    original_deleted = meta.original_deleted,
  }
end

-- =============================================================================
-- SECTION: Citations
-- =============================================================================

--- Add a citation from `source` (path or ref) to the note named by `target_ref`.
--- Idempotent; keeps both sides of the graph in step (cites / cited_by).
---@param source string
---@param target_ref string
---@return table  { ok, error? }
function M.cite(source, target_ref)
  local src = to_path(source)
  if not src then return { ok = false, error = 'source note not found: ' .. tostring(source) } end
  local ok, err = require('pkm.citations').cite(src, target_ref)
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Remove every citation from `source` to the note named by `target_ref`.
---@param source string
---@param target_ref string
---@return table  { ok, removed?, error? }
function M.uncite(source, target_ref)
  local src = to_path(source)
  if not src then return { ok = false, error = 'source note not found: ' .. tostring(source) } end
  local ok, removed, err = require('pkm.citations').uncite(src, target_ref)
  if not ok then return { ok = false, error = err } end
  return { ok = true, removed = removed }
end

--- Resolve a citation reference to the note it names, as plain data.
---@param ref string
---@return table  { ok, identifier?, type?, short_id?, path?, title?, error? }
function M.resolve(ref)
  local item, err = require('pkm.citations').resolve_citable(ref)
  if not item then return { ok = false, error = err } end
  return {
    ok         = true,
    identifier = item.identifier,
    type       = item.type,
    short_id   = item.short_id,
    path       = item.path,
    title      = item.title,
  }
end

-- =============================================================================
-- SECTION: Tags
-- =============================================================================

--- Apply a tag operation set to a list of notes, writing to disk.
---@param paths string[]
---@param ops table  { add?, remove?, rename? }
---@return table  { ok, applied, errors }
function M.tag(paths, ops)
  local applied, errors = require('pkm.tags').apply(paths, ops)
  return { ok = errors == 0, applied = applied, errors = errors }
end

--- Report what `tag` would change, touching nothing.
---@param paths string[]
---@param ops table
---@return { path: string, before: string[], after: string[] }[]
function M.tag_preview(paths, ops)
  return require('pkm.tags').preview(paths, ops)
end

--- Apply a tag operation to one named note, refusing to run behind an unsaved
--- buffer and keeping an open buffer in step.
---@param path string
---@param ops table
---@return table  { ok, error? }
function M.tag_note(path, ops)
  local ok, err = require('pkm.tags').write_note_tags(vim.fn.fnamemodify(path, ':p'), ops)
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Rename a tag across the whole vault — every note that carries it. Renaming
--- onto a tag that already exists *merges* the two: notes that had either end up
--- with the destination, deduplicated. This is the vault-wide "merge tags" op.
--- Reports how many notes changed.
---@param from string
---@param to string
---@return table  { ok, applied, errors }
function M.rename_tag(from, to)
  local tags     = require('pkm.tags')
  local ops      = { rename = { { from = from, to = to } } }
  local applied, errors = tags.apply(tags.all_note_paths(), ops)
  return { ok = errors == 0, applied = applied, errors = errors }
end

-- =============================================================================
-- SECTION: Query (read-only)
-- =============================================================================

--- The index entry for one note, or nil if it is not indexed.
---@param path string
---@return table|nil entry
function M.get(path)
  return require('pkm.index').get(vim.fn.fnamemodify(path, ':p'))
end

--- Every note the index knows about, as a flat array of entries.
---@return table[]
function M.notes()
  return require('pkm.index').get_all()
end

--- Notes matching a filter expression (the same DSL as :PKMBrowse and views).
---@param expr string
---@return table  { ok, matches?, error? }
function M.query(expr)
  local filter    = require('pkm.filter')
  local tree, err = filter.parse(expr)
  if not tree then return { ok = false, error = err or 'invalid filter' } end
  local matches = {}
  for _, entry in ipairs(require('pkm.index').get_all()) do
    if filter.eval(tree, entry) then matches[#matches + 1] = entry end
  end
  return { ok = true, matches = matches }
end

--- Find where a subject lives — across views, tags, and note titles at once —
--- so a subject that is a *view* rather than a tag is not missed, and an
--- accented or full-form tag is reached from an abbreviation or plain term.
--- Case- and accent-insensitive substring match. This is the first call to make
--- for "where are the notes about X"; a bare `query('tag:x')` that comes back
--- empty is ambiguous, and this disambiguates it.
---@param term string
---@return table  { ok, term?, views?, tags?, notes?, error? }
function M.find(term)
  if type(term) ~= 'string' or term == '' then
    return { ok = false, error = 'no search term' }
  end
  local needle = fold(term)

  local views = {}
  for _, name in ipairs(require('pkm.views').list()) do
    if fold(name):find(needle, 1, true) then views[#views + 1] = name end
  end

  local tags, seen, notes = {}, {}, {}
  for _, e in ipairs(require('pkm.index').get_all()) do
    for _, t in ipairs(e.tags or {}) do
      if not seen[t] and fold(t):find(needle, 1, true) then
        seen[t] = true
        tags[#tags + 1] = t
      end
    end
    local title = e.title or ''
    if fold(title):find(needle, 1, true)
      or fold(vim.fn.fnamemodify(e.path, ':t')):find(needle, 1, true) then
      notes[#notes + 1] = { path = e.path, title = title }
    end
  end
  table.sort(tags)

  return { ok = true, term = term, views = views, tags = tags, notes = notes }
end

-- =============================================================================
-- SECTION: Views (read)
-- =============================================================================

--- All views, as the view registry returns them.
---@return table
function M.views()
  return require('pkm.views').list()
end

--- The note paths matching a named view (its full AND-chain of filters).
---@param name string
---@return string[]
function M.view_members(name)
  return require('pkm.views').match_all(name)
end

--- Add or remove a note from a named view by writing the tags that define it.
--- Only works when the view is a pure tag condition satisfiable exactly one way;
--- returns an error (never a prompt) when the view is ambiguous or non-tag.
---@param path string
---@param view_name string
---@param kind string  "add" | "remove"
---@return table  { ok, error? }
function M.set_membership(path, view_name, kind)
  local ok, err = require('pkm.views').set_membership(
    vim.fn.fnamemodify(path, ':p'), view_name, kind)
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Save a sub-view under a parent view, defined by a filter expression. Fails if
--- the parent does not exist or the filter does not parse.
---@param name string
---@param parent string
---@param filter_expr string
---@return table  { ok, error? }
function M.save_subproject(name, parent, filter_expr)
  local ok = require('pkm.views').save_subproject(name, parent, filter_expr)
  if not ok then
    return { ok = false, error = 'could not save subproject (parent missing or filter invalid)' }
  end
  return { ok = true }
end

-- =============================================================================
-- SECTION: Audit
-- =============================================================================

--- The vault-integrity audit: a flat list of findings, errors before warnings.
--- Read-only; writes and opens nothing.
---@return { kind: string, severity: string, path: string|nil, message: string }[]
function M.audit()
  return require('pkm.check').run()
end

-- =============================================================================
-- SECTION: Export
-- =============================================================================

--- The transitive closure of a citation neighbourhood — seeds plus everything
--- reached within the depth budget. Pure: returns paths, copies nothing.
---@param seed_paths string[]
---@param opts table|nil  { cites_depth?, cited_by_depth? }
---@return string[] paths
function M.collect(seed_paths, opts)
  return require('pkm.export').collect_deep(seed_paths, opts)
end

--- Copy a set of notes into a destination directory.
---@param paths string[]
---@param dest string
---@return table  { ok, copied, errors, dest }
function M.export(paths, dest)
  local copied, errors = require('pkm.export').copy_files(paths, dest)
  return { ok = errors == 0, copied = copied, errors = errors, dest = dest }
end

-- =============================================================================
-- SECTION: Vault
-- =============================================================================

--- Every registered vault.
---@return table
function M.vaults()
  return require('pkm.vault').list()
end

--- The active vault.
---@return table|nil
function M.active_vault()
  return require('pkm.vault').active()
end

--- The default vault from the registry.
---@return table|nil
function M.default_vault()
  return require('pkm.vault').default()
end

--- The vault a path belongs to.
---@param path string
---@return table|nil
function M.vault_of(path)
  return require('pkm.vault').of(vim.fn.fnamemodify(path, ':p'))
end

-- =============================================================================
-- SECTION: Actions (enumerable bulk operations)
-- =============================================================================

--- The bulk operations the plugin exposes, as `{ id, label }` rows — the `run`
--- closure is stripped so the list is JSON-encodable. This is what lets an
--- assistant discover the operations instead of hard-coding them.
---@return { id: string, label: string }[]
function M.actions()
  local out = {}
  for _, a in ipairs(require('pkm.actions').list()) do
    out[#out + 1] = { id = a.id, label = a.label }
  end
  return out
end

--- Run a bulk operation by id over a list of notes, without the picker menu.
---@param id string
---@param paths string[]
---@param ctx table|nil
function M.run_action(id, paths, ctx)
  return require('pkm.actions').run_id(id, paths, ctx)
end

return M
