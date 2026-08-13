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

-- Relevance of one index entry to a folded search needle, for ordering find /
-- find_all results best-first instead of in the index's iteration order. Clear
-- tiers, strongest first: an exact title (100), a title prefix (70), a
-- word-boundary hit mid-title (50), a substring mid-word (35), then a filename
-- prefix (25) / substring (15). A small bonus rewards an earlier position within
-- a tier; a matching tag boosts (exact +15, partial +5) — but tags only lift a
-- note already matched by its title or filename, they never make one a match on
-- their own (that is the tag list's job). Recency is the caller's tiebreaker, not
-- part of the score. Returns 0 when neither title nor filename matches.
local function score_note(entry, needle)
  local title = fold(entry.title or '')
  local fname = fold(entry.filename or vim.fn.fnamemodify(entry.path or '', ':t:r'))
  local ti    = title:find(needle, 1, true)
  local fi    = fname:find(needle, 1, true)

  local score
  if title == needle then
    score = 100
  elseif ti == 1 then
    score = 70
  elseif ti and title:sub(ti - 1, ti - 1):match('%W') then
    score = 50
  elseif ti then
    score = 35
  elseif fi == 1 then
    score = 25
  elseif fi then
    score = 15
  else
    return 0
  end

  if ti and ti > 1 then
    score = score + math.max(0, 8 - math.floor((ti - 1) / 5))
  end
  for _, t in ipairs(entry.tags or {}) do
    local ft = fold(t)
    if ft == needle then
      score = score + 15
    elseif ft:find(needle, 1, true) then
      score = score + 5
    end
  end
  return score
end

-- Score the matching entries and return them best-first: relevance, then recency
-- (mtime), then title. Each note carries its `score` so the ranking is legible.
local function ranked_notes(entries, needle)
  local out = {}
  for _, e in ipairs(entries) do
    local s = score_note(e, needle)
    if s > 0 then
      out[#out + 1] = {
        path = e.path, title = e.title or '', note_type = e.note_type,
        score = s, mtime = e.mtime,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if (a.mtime or 0) ~= (b.mtime or 0) then return (a.mtime or 0) > (b.mtime or 0) end
    return (a.title or '') < (b.title or '')
  end)
  return out
end

-- Two absolute paths naming the same file, tolerant of separator and (on
-- case-insensitive filesystems) case differences — for excluding a seed from its
-- own neighbourhood, where the seed path and the graph-resolved paths are spelled
-- by different code.
local function samepath(a, b)
  return vim.fs.normalize(tostring(a or '')):lower()
      == vim.fs.normalize(tostring(b or '')):lower()
end

-- The meaningful words of a title, folded, as a set — for measuring title
-- overlap between notes. Words shorter than four characters and a few common
-- 4+-letter stop words are dropped, so the overlap reflects subject terms, not
-- glue words. (Sub-four-letter stop words — the, and, for, de, da, os — fall out
-- on length alone.)
local TITLE_STOP = {
  that = true, this = true, with = true, from = true, into = true, your = true,
  para = true, como = true, mais = true, pelo = true, pela = true, sobre = true,
  entre = true, uma = true, nao = true,
}
local function title_terms(title)
  local out = {}
  for w in fold(title or ''):gmatch('[%w]+') do
    if #w >= 4 and not TITLE_STOP[w] then out[w] = true end
  end
  return out
end

-- Jaccard overlap of two sets (tables used as sets): |A ∩ B| / |A ∪ B|, in [0,1].
-- Empty-vs-empty is 0. Used to measure how near-duplicate two notes are.
local function jaccard(a, b)
  local na, inter = 0, 0
  for k in pairs(a) do
    na = na + 1
    if b[k] then inter = inter + 1 end
  end
  local nb = 0
  for _ in pairs(b) do nb = nb + 1 end
  local uni = na + nb - inter
  if uni == 0 then return 0 end
  return inter / uni
end

-- The unique tags matching the needle, ordered by relevance: an exact tag first,
-- then a prefix match, then alphabetical.
local function ranked_tags(entries, needle)
  local seen, tags = {}, {}
  for _, e in ipairs(entries) do
    for _, t in ipairs(e.tags or {}) do
      if not seen[t] and fold(t):find(needle, 1, true) then
        seen[t] = true
        tags[#tags + 1] = t
      end
    end
  end
  table.sort(tags, function(a, b)
    local fa, fb = fold(a), fold(b)
    local ra = (fa == needle) and 0 or (fa:find(needle, 1, true) == 1 and 1 or 2)
    local rb = (fb == needle) and 0 or (fb:find(needle, 1, true) == 1 and 1 or 2)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  return tags
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

--- Set a note's frontmatter title on disk — the post-hoc, persisting twin of
--- :PKMNote settitle (which is buffer-only). Keeps any open buffer in step and
--- propagates the new title to every note that cites this one, so correcting a
--- title no longer needs an uncite → delete → recreate cycle.
---@param ref string  path or citation reference
---@param title string  Taken verbatim (may be empty)
---@return table  { ok, error? }
function M.set_title(ref, title)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  local ok, err = require('pkm.notes').set_title_at(path, title)
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Set a bib note's source metadata (source_author / source_type) on disk.
--- Only the keys present in `opts` are written. Like set_title, correcting these
--- after creation no longer forces recreating the note.
---@param ref string  path or citation reference
---@param opts table  { author?=string, type?=string }
---@return table  { ok, error? }
function M.set_source_meta(ref, opts)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  local ok, err = require('pkm.notes').set_source_meta_at(path, opts or {})
  if not ok then return { ok = false, error = err } end
  return { ok = true }
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

--- Add a *marked comment* to a note — the mechanism for writing into a note that
--- is **not** the assistant's own. The `By <Author>: ` marker is applied for you
--- and the block lands at a boundary (the end of `opts.heading`'s section, or the
--- note's end), never inline. For your own notes, set_body/append_body/
--- insert_section write freely; this is for a *user's* note.
---
--- Authorisation is the caller's, not this function's: the protocol requires the
--- user's permission for that specific act (`doc/AGENT_PROTOCOL.md` §§ 5.3, 7).
--- This supplies the mechanism and the attribution marker, not the permission.
---@param ref string  path or citation reference
---@param content string|string[]
---@param opts table|nil  { heading?, by? }
---@return table  { ok, error? }
function M.annotate(ref, content, opts)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end
  local ok, err = require('pkm.notes').annotate(path, content, opts or {})
  if not ok then return { ok = false, error = err } end
  return { ok = true }
end

--- Merge the `absorbed` note into the `survivor`: fold its body in, **redirect** its
--- citation graph onto the survivor (inbound citers are re-pointed; the survivor
--- gains the absorbed note's outbound cites via the copied body), union its topical
--- tags, and trash it. The graph is redirected before the trash, so nothing dangles.
--- Both notes must be assistant-authored — the survivor's body is rewritten and the
--- absorbed note deleted. The act on `unlinked_pairs`/`duplicates` findings.
---@param survivor_ref string  the note that remains (path or citation reference)
---@param absorbed_ref string  the note folded in and trashed
---@param opts table|nil  { heading?: string }  place the absorbed body under a heading
---@return table  { ok, survivor?, redirected?, absorbed_title?, error? }
function M.merge(survivor_ref, absorbed_ref, opts)
  local survivor = to_path(survivor_ref)
  if not survivor then return { ok = false, error = 'survivor not found: ' .. tostring(survivor_ref) } end
  local absorbed = to_path(absorbed_ref)
  if not absorbed then return { ok = false, error = 'absorbed not found: ' .. tostring(absorbed_ref) } end

  local path, err, meta = require('pkm.notes').merge_notes(survivor, absorbed, opts or {})
  if not path then return { ok = false, error = err } end
  return {
    ok             = true,
    survivor       = path,
    redirected     = meta.redirected,
    absorbed_title = meta.absorbed_title,
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

--- Cite a *source* from a note — find the source's bib note, or create one, and
--- record the citation, in a single call. This is the affordance § 10 was missing:
--- it points reference-recording at the vault's **bib-note** mechanism instead of
--- a freetext `## References` prose block, so a source becomes a citable,
--- graph-linked note rather than a dangling line.
---
--- `source` names the bibliographic source; `citing_ref` is the note that cites it:
---   - `source.title`   the source's name — the search key, and the title of a new
---                      bib note. Required unless `source.ref` is given.
---   - `source.ref`     an explicit existing bib note (path / identifier / token),
---                      skipping the search.
---   - `source.bibtex`  the BibTeX entry, placed at the top of a *newly created*
---                      bib note (`doc/CONVENTIONS.md` § Assistant-Authored Notes).
---   - `source.notes`   an optional summary / part-notes, added below the bibtex.
---   - `source.by`      authorship for a created bib note (default `'claude'`);
---                      pass `''` for an unmarked, citation-only bib note.
---   - `source.source_author` / `source.source_type`  provenance frontmatter.
---   - `source.create`  set false to error rather than create when none is found.
---
--- The bib note is matched by its title (exact first, then substring, then the
--- filename), among indexed notes of type `bib`, in the **active vault only** —
--- like every citation, this never crosses vaults. The token is placed under
--- `opts.heading` (default `'References'`, created if absent); pass
--- `opts.heading = false` to append it at the body's end instead. Idempotent: a
--- note already carrying the token is left as it is (`cited = false`).
---@param citing_ref string  the note that will cite the source (path or ref)
---@param source table  { title?, ref?, bibtex?, notes?, by?, source_author?, source_type?, create? }
---@param opts table|nil  { heading?: string|false }
---@return table  { ok, bib?={ path, number, title, created }, cited?, heading?, token?, error? }
function M.cite_source(citing_ref, source, opts)
  source = source or {}
  opts   = opts or {}

  local citing = to_path(citing_ref)
  if not citing then
    return { ok = false, error = 'citing note not found: ' .. tostring(citing_ref) }
  end

  local citations = require('pkm.citations')
  local index     = require('pkm.index')

  -- 1. Resolve the bib note: an explicit ref, else a title search over indexed
  --    bib notes (exact title, then substring, then filename) in this vault.
  local bib_path, created = nil, false
  if type(source.ref) == 'string' and source.ref ~= '' then
    bib_path = to_path(source.ref)
    if not bib_path then
      return { ok = false, error = 'bib note not found: ' .. source.ref }
    end
  else
    if type(source.title) ~= 'string' or source.title == '' then
      return { ok = false, error = 'a source needs a title (or an explicit ref)' }
    end
    local needle, partial = fold(source.title), nil
    for _, e in ipairs(index.get_all()) do
      if e.note_type == 'bib' then
        if fold(e.title or '') == needle then bib_path = e.path break end
        if not partial and (fold(e.title or ''):find(needle, 1, true)
            or fold(vim.fn.fnamemodify(e.path, ':t')):find(needle, 1, true)) then
          partial = e.path
        end
      end
    end
    bib_path = bib_path or partial
  end

  -- 2. Create the bib note when none matched — bibtex at the top, optional notes.
  if not bib_path then
    if source.create == false then
      return { ok = false, error = 'no bib note matches "' .. source.title .. '"; creation disabled' }
    end
    local body = {}
    if type(source.bibtex) == 'string' and source.bibtex ~= '' then
      vim.list_extend(body, vim.split(source.bibtex, '\n', { plain = true }))
    end
    if type(source.notes) == 'string' and source.notes ~= '' then
      if #body > 0 then body[#body + 1] = '' end
      vim.list_extend(body, vim.split(source.notes, '\n', { plain = true }))
    end
    local path, err = require('pkm.notes').write_new_note('bib', {
      title         = source.title,
      by            = (source.by ~= nil) and source.by or 'claude',
      body          = body,
      source_author = source.source_author,
      source_type   = source.source_type,
    })
    if not path then return { ok = false, error = err } end
    bib_path, created = path, true
  end

  -- 3. Cite the bib note from the citing note — idempotent, placement-aware.
  local item, rerr = citations.resolve_citable(bib_path)
  if not item then return { ok = false, error = rerr or 'could not resolve the bib note' } end
  local token   = string.format('%s[%s]', item.type, item.short_id)  -- bib[NNNN]
  local bib_title = (index.get(bib_path) or {}).title

  local already = false
  for _, l in ipairs(vim.fn.readfile(citing)) do
    if l:find(token, 1, true) then already = true break end
  end

  local heading = opts.heading
  if heading == nil then heading = 'References' end
  local place_heading = (type(heading) == 'string' and heading ~= '') and heading or nil

  local cited = false
  if not already then
    if place_heading then
      local wrapped = string.format('[%s]', token)
      local ok, werr = require('pkm.notes').write_section(
        citing, place_heading, wrapped, { mode = 'append' })
      if not ok and type(werr) == 'string' and werr:find('no section', 1, true) then
        -- No such section yet: open one at the note's end, then the token under it.
        ok, werr = require('pkm.notes').write_body(
          citing, { '## ' .. place_heading, '', wrapped }, { mode = 'append' })
      end
      if not ok then return { ok = false, error = werr } end
    else
      local ok, cerr = citations.cite(citing, bib_path)
      if not ok then return { ok = false, error = cerr } end
    end
    cited = true
  end

  return {
    ok      = true,
    bib     = { path = bib_path, number = tonumber(item.short_id), title = bib_title, created = created },
    cited   = cited,
    heading = place_heading,
    token   = token,
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

--- Read one note in full — the retrieval *atom* for "retrieve before working"
--- (`doc/AGENT_PROTOCOL.md` § 11.6). Unlike `get` (an index entry) this returns the
--- note's **body** plus its **resolved** citation edges: who it cites and who
--- cites it, each as `{ ref, title, path, note_type }` you can hand straight to
--- another `read`. Accepts a path or a citation reference. Single vault, like the
--- graph it reads.
---@param ref string  path or citation reference
---@return table  { ok, path?, title?, note_type?, tags?, author?, body?, cites?, cited_by?, error? }
function M.read(ref)
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end

  local entry = require('pkm.index').get(path)
  local title, note_type, tags, body
  if entry then
    title, note_type, tags, body = entry.title, entry.note_type, entry.tags, entry.body
  else
    -- A readable note the active index does not hold (e.g. an odd folder): parse
    -- the minimum from the file so read still answers.
    local lines = vim.fn.readfile(path)
    local fm, cs = require('pkm.yaml').parse_frontmatter(lines)
    title = (fm and type(fm.title) == 'string' and fm.title ~= '' and fm.title)
      or vim.fn.fnamemodify(path, ':t:r')
    tags = (fm and type(fm.tags) == 'table') and fm.tags or {}
    local parts = {}
    if cs then for i = cs, #lines do parts[#parts + 1] = lines[i] end end
    body = table.concat(parts, '\n')
  end

  local edges = require('pkm.export').read_citation_edges(path)
  local map   = require('pkm.citations').get_citable_items_map()
  local function resolve(ids)
    local out = {}
    for _, id in ipairs(ids) do
      local it = map[id]
      if it then
        out[#out + 1] = { ref = id, title = it.title, path = it.path, note_type = it.type }
      end
    end
    return out
  end

  return {
    ok        = true,
    path      = path,
    title     = title,
    note_type = note_type,
    tags      = tags or {},
    author    = require('pkm.notes').agent_authored(path),
    body      = body or '',
    cites     = resolve(edges.cites),
    cited_by  = resolve(edges.cited_by),
  }
end

--- The citation-connected **neighbourhood** of a note — the navigation aid for
--- "retrieve everything linked before working". Walks the graph the assistant
--- built (`cite`) out to a depth and returns the reachable notes as readable
--- entries, so a subject and its context arrive together rather than one lookup at
--- a time. `opts.cites_depth` / `opts.cited_by_depth` bound the walk (default 1
--- each: what this note cites and what cites it, one hop). The seed is returned
--- separately and excluded from `notes`. Single vault (the graph never crosses
--- vaults); built on `export.collect_deep`.
---@param ref string  path or citation reference
---@param opts table|nil  { cites_depth?: integer, cited_by_depth?: integer }
---@return table  { ok, seed?, notes?, error? }
---              seed/notes entries: { path, title, note_type }
function M.neighborhood(ref, opts)
  opts = opts or {}
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end

  local index = require('pkm.index')
  local function info(p)
    local e = index.get(p)
    return {
      path = p,
      title = (e and e.title) or vim.fn.fnamemodify(p, ':t:r'),
      note_type = e and e.note_type,
    }
  end

  local paths = require('pkm.export').collect_deep({ path }, {
    cites_depth    = opts.cites_depth    or 1,
    cited_by_depth = opts.cited_by_depth or 1,
  })

  local notes = {}
  for _, p in ipairs(paths) do
    if not samepath(p, path) then notes[#notes + 1] = info(p) end
  end
  table.sort(notes, function(a, b) return (a.title or '') < (b.title or '') end)

  return { ok = true, seed = info(path), notes = notes }
end

--- Assemble the relevant, connected cluster of notes for a **subject** — the
--- one-call "retrieve before working" (`doc/AGENT_PROTOCOL.md` § 11.6). It composes
--- the two reads: `find` locates the best matches for `term` (relevance-ranked,
--- active vault), and each of the top `opts.seeds` is expanded by its citation
--- `neighborhood`, then the whole set is merged, de-duplicated, and annotated —
--- `relation = 'seed'` for a search hit, `'linked'` for a note pulled in by the
--- graph. So a subject arrives *with its context*, ready to read, instead of one
--- lookup at a time. For a note you already hold, use `neighborhood` directly.
---@param term string  the subject to retrieve
---@param opts table|nil  { seeds?: integer (default 3), cites_depth?, cited_by_depth?: integer (default 1 each) }
---@return table  { ok, query?, seeds?, notes?, error? }
---              seeds: { path, title, note_type, score }[] (the search hits used)
---              notes: { path, title, note_type, relation, score? }[] (the whole
---                     cluster, seeds first by score, then linked by title)
function M.context(term, opts)
  if type(term) ~= 'string' or term == '' then
    return { ok = false, error = 'no search term' }
  end
  opts = opts or {}
  local max_seeds = opts.seeds or 3
  local cd, cbd = opts.cites_depth or 1, opts.cited_by_depth or 1

  local found = M.find(term)
  local seeds = {}
  for i, n in ipairs(found.notes or {}) do
    if i > max_seeds then break end
    seeds[i] = { path = n.path, title = n.title, note_type = n.note_type, score = n.score }
  end

  local seen, notes = {}, {}
  local function keyof(p) return vim.fs.normalize(tostring(p or '')):lower() end
  local function add(entry, relation, score)
    local k = keyof(entry.path)
    local prior = seen[k]
    if prior then
      -- A note reached both as a search hit and via the graph is a seed: the
      -- stronger relation and its score win.
      if relation == 'seed' and prior.relation ~= 'seed' then
        prior.relation, prior.score = 'seed', score
      end
      return
    end
    local e = {
      path = entry.path, title = entry.title, note_type = entry.note_type,
      relation = relation, score = score,
    }
    seen[k] = e
    notes[#notes + 1] = e
  end

  for _, s in ipairs(seeds) do add(s, 'seed', s.score) end
  for _, s in ipairs(seeds) do
    local nb = M.neighborhood(s.path, { cites_depth = cd, cited_by_depth = cbd })
    if nb.ok then
      for _, n in ipairs(nb.notes) do add(n, 'linked', nil) end
    end
  end

  table.sort(notes, function(a, b)
    local ar = (a.relation == 'seed') and 0 or 1
    local br = (b.relation == 'seed') and 0 or 1
    if ar ~= br then return ar < br end
    if ar == 0 and (a.score or 0) ~= (b.score or 0) then
      return (a.score or 0) > (b.score or 0)
    end
    return (a.title or '') < (b.title or '')
  end)

  return { ok = true, query = term, seeds = seeds, notes = notes }
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
--- empty is ambiguous, and this disambiguates it. `notes` are **relevance-ranked**
--- (each carries its `score`, best first: exact title > prefix > word-boundary >
--- substring > filename, recency breaking ties); `tags` lead with the exact match.
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

  local all   = require('pkm.index').get_all()
  local tags  = ranked_tags(all, needle)
  local notes = ranked_notes(all, needle)

  return { ok = true, term = term, views = views, tags = tags, notes = notes }
end

--- Find where a subject lives **across every vault** — the cross-vault twin of
--- `find`. `find`/`query` read one vault's index, so they cannot answer "which of
--- my vaults holds X"; this sweeps each registered vault (and the active root, even
--- if unregistered) and reports the matches grouped by vault. Each non-active vault
--- is read straight from its files (`index.scan_root`) without switching the active
--- root or rebuilding the live index, so it is safe to call from anywhere; the
--- active vault is read once, from the live index.
---
--- Matches note titles and filenames and tags, case- and accent-insensitively (the
--- same folding as `find`), and each vault's `notes` are **relevance-ranked** best
--- first, exactly as `find` ranks them (with a `score` per note). Views are a
--- per-vault concept and are *not* swept here — use `find` for the active vault's
--- views. Only vaults with at least one match
--- appear in `vaults`.
---@param term string
---@return table  { ok, term?, vaults?, error? }
---              vaults: { vault, number?, root, active, notes, tags }[]
function M.find_all(term)
  if type(term) ~= 'string' or term == '' then
    return { ok = false, error = 'no search term' }
  end
  local needle = fold(term)
  local vault  = require('pkm.vault')
  local index  = require('pkm.index')

  local active      = vault.active()
  local active_root = (require('pkm').config or {}).root_path

  -- The roots to sweep: every registered vault, plus the active root when it is
  -- not itself registered. Deduplicated so the active vault is read once (from the
  -- live index), never also re-scanned from disk.
  local roots, saw_active = {}, false
  for _, v in ipairs(vault.list()) do
    local root = vault.path_of(v)
    if root then
      local is_active = active ~= nil and active.number == v.number
      saw_active = saw_active or is_active
      roots[#roots + 1] = { name = v.name, number = v.number, root = root, live = is_active }
    end
  end
  if not saw_active and active_root and active_root ~= '' then
    roots[#roots + 1] = { name = active and active.name or 'active', root = active_root, live = true }
  end

  local out = {}
  for _, r in ipairs(roots) do
    local entries = r.live and index.get_all() or index.scan_root(r.root)
    local notes = ranked_notes(entries, needle)
    local tags  = ranked_tags(entries, needle)
    if #notes > 0 or #tags > 0 then
      out[#out + 1] = {
        vault  = r.name,
        number = r.number,
        root   = r.root,
        active = r.live or nil,
        notes  = notes,
        tags   = tags,
      }
    end
  end

  return { ok = true, term = term, vaults = out }
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

--- Save a *top-level* view defined by a filter expression — the parentless twin
--- of `save_subproject`. Until now only subprojects could be created through the
--- API, so an agent reorganising a vault could add children but not the root view
--- they hang from. Replaces an existing view of the same name, exactly as
--- `views.save` (and the interactive `:PKMView new`) does. Fails when the name is
--- blank or the filter does not parse.
---@param name string
---@param expr string  A filter expression in the :PKMBrowse / views DSL
---@return table  { ok, error? }
function M.save_view(name, expr)
  if type(name) ~= 'string' or name:match('^%s*$') then
    return { ok = false, error = 'a view name is required' }
  end
  if type(expr) ~= 'string' or expr:match('^%s*$') then
    return { ok = false, error = 'a filter expression is required' }
  end
  local ok = require('pkm.views').save(name, expr)
  if not ok then
    return { ok = false, error = 'could not save view (filter invalid)' }
  end
  return { ok = true }
end

-- =============================================================================
-- SECTION: Structure (compact projection)
-- =============================================================================

--- A compact structural projection of the vault — the view list with per-view
--- match counts, the tag catalog with per-tag counts, and the note total —
--- WITHOUT dumping every full note record the way `notes()` does. This is the
--- cheap "what is in here, how is it organised" read an agent makes to orient
--- itself before drilling in with `query` / `view_members`. Counts come from the
--- same AND-chained filter each view resolves to, so a subview's count already
--- reflects its parent composition.
---@return table  { ok, total_notes, views = {{name,count}}, tags = {{tag,count}} }
function M.structure()
  local entries = require('pkm.index').get_all()
  local names   = require('pkm.views').list()
  local counts  = require('pkm.views').count_many(names)

  local views = {}
  for _, name in ipairs(names) do
    views[#views + 1] = { name = name, count = counts[name] or 0 }
  end

  local tally = {}
  for _, e in ipairs(entries) do
    for _, t in ipairs(e.tags or {}) do
      tally[t] = (tally[t] or 0) + 1
    end
  end
  local tags = {}
  for tag, count in pairs(tally) do tags[#tags + 1] = { tag = tag, count = count } end
  table.sort(tags, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.tag < b.tag
  end)

  return { ok = true, total_notes = #entries, views = views, tags = tags }
end

--- The tag catalog alone (tag → count, most-used first) — the tag half of
--- `structure()`, for a caller that only needs the vocabulary.
---@return table  { ok, tags = {{tag,count}} }
function M.tag_catalog()
  return { ok = true, tags = M.structure().tags }
end

-- =============================================================================
-- SECTION: Output (headless contract)
-- =============================================================================

--- Write a value as one line of JSON to real stdout (fd 1). Under
--- `nvim --headless`, `print()` and `vim.notify` go to the message stream on
--- **stderr**, so JSON emitted with `print` is interleaved with notify noise
--- ("PKMView: saved view …") and an agent must strip stderr to parse it. `emit`
--- bypasses the message stream: it writes only the JSON to stdout, giving the
--- clean-stdout contract `PKM_API.md` documents. Returns the encoded string too.
---@param value any  Any JSON-encodable value
---@return string json
function M.emit(value)
  local json = vim.json.encode(value)
  io.stdout:write(json)
  io.stdout:write('\n')
  return json
end

-- =============================================================================
-- SECTION: UI state (read)
-- =============================================================================

--- A snapshot of the interactive UI, as plain JSON-encodable data — what buffer
--- is current, whether the views sidebar and the buffer panel are open, and what
--- the sidebar is showing and has highlighted. This is the *inspect* half of
--- agent-assisted smoke testing: drive the real mappings with `feedkeys` in a
--- headless Neovim, then read this to assert the interactive path behaved — the
--- part the headless *unit* suite cannot otherwise see. Opens nothing; pure read.
---@return table  { current = { buf, name, title?, type? },
---                 sidebar = { open, cursor?, highlighted?, highlighted_view?, lines? },
---                 bufpanel = { open } }
function M.ui_state()
  local views = require('pkm.views')

  local cur_buf  = vim.api.nvim_get_current_buf()
  local cur_name = vim.api.nvim_buf_get_name(cur_buf)
  local current  = { buf = cur_buf, name = cur_name }
  if cur_name ~= '' then
    local entry = require('pkm.index').get(vim.fn.fnamemodify(cur_name, ':p'))
    if entry then
      current.title = entry.title
      current.type  = entry.note_type
    end
  end

  local sidebar = { open = views.is_sidebar_open() }
  if sidebar.open then
    local win = views.get_sidebar_win()
    if win then
      local buf = vim.api.nvim_win_get_buf(win)
      sidebar.lines       = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      sidebar.cursor      = vim.api.nvim_win_get_cursor(win)[1]
      sidebar.highlighted = sidebar.lines[sidebar.cursor]
      -- Best-effort view name under the cursor, parsed from the "• Name  (n)"
      -- row the sidebar renders; nil when the cursor is on a non-view line.
      local label = sidebar.highlighted
        and sidebar.highlighted:match('•%s*(.-)%s*%(%d+%)%s*$')
      sidebar.highlighted_view = label and vim.trim(label) or nil
    end
  end

  return {
    current  = current,
    sidebar  = sidebar,
    bufpanel = { open = require('pkm.ui').is_bufpanel_open() },
  }
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
-- SECTION: Revision (surfacing what to revise)
-- =============================================================================

--- Notes **related to** a given note but **not linked to it** — the revision aid
--- for "a vault is a graph, not a pile" (`doc/AGENT_PROTOCOL.md` §§ 7, 11.6). It
--- surfaces candidates the assistant can then connect with `cite`: notes that
--- share the focus note's tags or title terms yet have no citation edge to it in
--- either direction. Advisory, read-only — it proposes, the assistant (and the
--- user) decide; a shared tag is a hint, not a mandate to link.
---
--- Scoring: each shared tag counts 2 (a shared tag is a strong same-subject
--- signal), each shared title term counts 1. Notes the focus already cites or is
--- cited by are excluded (that is the point — they are *already* linked). Ranked
--- best first. Single vault.
---
--- Three relatedness signals: a shared tag (2), a shared title term (1), and — the
--- graph one — a **co-citation** (2 each): a third note both the focus and the
--- candidate cite (or are cited by), so notes that lean on the same sources surface
--- even with no shared tag. Co-citation reads each candidate's edges, so it is set
--- behind `opts.graph` (default on); pass `graph = false` for the cheap index-only
--- pass (tags/titles plus one read of the focus note's own edges).
---@param ref string  the note to find unlinked relations for (path or citation reference)
---@param opts table|nil  { limit?: integer (10), min_score?: integer (2), graph?: boolean (true) }
---@return table  { ok, note?, candidates?, error? }
---              candidates: { path, title, note_type, score, shared_tags, shared_terms, co_citations }[]
function M.related_unlinked(ref, opts)
  opts = opts or {}
  local path = to_path(ref)
  if not path then return { ok = false, error = 'note not found: ' .. tostring(ref) } end

  local index = require('pkm.index')
  local focus = index.get(path)
  if not focus then return { ok = false, error = 'note not indexed: ' .. path } end

  local limit     = opts.limit or 10
  local min_score = opts.min_score or 2
  local graph     = opts.graph ~= false

  local ftags = {}
  for _, t in ipairs(focus.tags or {}) do ftags[t] = true end
  local fterms = title_terms(focus.title)

  -- A tag only counts toward relatedness if it is *topical*. The `by-claude`
  -- authorship tag rides every assistant note, and any tag on almost the whole
  -- vault is glue, not subject — either would make every note "related" to every
  -- other. Compute each tag's document frequency once and drop the ubiquitous.
  local entries = index.get_all()
  local n, df = #entries, {}
  for _, e in ipairs(entries) do
    for _, t in ipairs(e.tags or {}) do df[t] = (df[t] or 0) + 1 end
  end
  local function topical(tag)
    if tag == 'by-claude' then return false end
    if n >= 5 and df[tag] and df[tag] > 0.8 * n then return false end
    return true
  end

  -- The notes the focus is already linked to (either direction), by identifier —
  -- one read of its frontmatter edges, so they can be excluded.
  local linked = {}
  local edges  = require('pkm.export').read_citation_edges(path)
  for _, id in ipairs(edges.cites) do linked[id] = true end
  for _, id in ipairs(edges.cited_by) do linked[id] = true end

  local citations = require('pkm.citations')
  local out = {}
  for _, e in ipairs(entries) do
    if not samepath(e.path, path) then
      local _, eid = citations.get_note_type_and_id(e.path)
      if not (eid and linked[eid]) then
        local shared_tags = {}
        for _, t in ipairs(e.tags or {}) do
          if ftags[t] and topical(t) then shared_tags[#shared_tags + 1] = t end
        end
        local shared_terms, et = {}, title_terms(e.title)
        for term in pairs(fterms) do if et[term] then shared_terms[#shared_terms + 1] = term end end

        -- Co-citation: sources this candidate cites (or is cited by) that the
        -- focus also links to. `linked` already holds the focus's own neighbours,
        -- so a candidate edge landing in it is a shared third note.
        local co = 0
        if graph then
          local ce = require('pkm.export').read_citation_edges(e.path)
          for _, id in ipairs(ce.cites) do if linked[id] then co = co + 1 end end
          for _, id in ipairs(ce.cited_by) do if linked[id] then co = co + 1 end end
        end

        local score = 2 * #shared_tags + #shared_terms + 2 * co
        if score >= min_score then
          out[#out + 1] = {
            path = e.path, title = e.title, note_type = e.note_type,
            score = score, shared_tags = shared_tags, shared_terms = shared_terms,
            co_citations = co,
          }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.title or '') < (b.title or '')
  end)
  local limited = {}
  for i = 1, math.min(limit, #out) do limited[i] = out[i] end

  return { ok = true, note = { path = path, title = focus.title }, candidates = limited }
end

--- Vault-wide relatedness sweep: every **pair** of notes that is related (shared
--- tags, title terms, or co-citations) but has **no citation edge** between them —
--- the "review the whole vault for missing links" pass, where `related_unlinked`
--- answers the same for a single focus note. Advisory and read-only; the assistant
--- reviews the pairs and `cite`s the ones that belong together.
---
--- Same signals and weights as `related_unlinked` (shared tag 2, title term 1,
--- co-citation 2), the same non-topical-tag exclusion, the same direct-edge
--- exclusion — over every unordered pair. To stay bounded, a signal *bucket* (a
--- tag, a term, a shared source) with more than `opts.bucket_cap` members is
--- skipped: it is too common to implicate any specific pair — the same reasoning
--- that drops ubiquitous tags. Cost: one read of every note's edges, then a
--- co-occurrence accumulation; a deliberate sweep, not a hot path.
---@param opts table|nil  { limit? (20), min_score? (3), bucket_cap? (30), graph? (true) }
---@return table  { ok, pairs?, error? }
---              pairs: { a, b, score, shared = { tags, terms, co_citations } }[]
---              a / b: { path, title, note_type }
function M.unlinked_pairs(opts)
  opts = opts or {}
  local limit      = opts.limit or 20
  local min_score  = opts.min_score or 3
  local bucket_cap = opts.bucket_cap or 30
  local graph      = opts.graph ~= false

  local index     = require('pkm.index')
  local citations = require('pkm.citations')
  local export    = require('pkm.export')

  local entries = index.get_all()
  local n = #entries
  if n < 2 then return { ok = true, pairs = {} } end

  -- Per-note identity + terms; tag document frequency for the topical filter.
  local items, by_id, df = {}, {}, {}
  for _, e in ipairs(entries) do
    local _, id = citations.get_note_type_and_id(e.path)
    if id then
      local it = {
        id = id, path = e.path, title = e.title, note_type = e.note_type,
        tags = e.tags or {}, terms = title_terms(e.title),
      }
      items[#items + 1] = it
      by_id[id] = it
    end
    for _, t in ipairs(e.tags or {}) do df[t] = (df[t] or 0) + 1 end
  end
  local function topical(tag)
    if tag == 'by-claude' then return false end
    if n >= 5 and df[tag] and df[tag] > 0.8 * n then return false end
    return true
  end

  -- Direct edges (to exclude), and each note's neighbours (for co-citation).
  local direct = {}
  local function pairkey(a, b) if a > b then a, b = b, a end return a .. '\0' .. b end
  for _, it in ipairs(items) do
    local edges, nb = export.read_citation_edges(it.path), {}
    for _, x in ipairs(edges.cites) do nb[#nb + 1] = x; direct[pairkey(it.id, x)] = true end
    for _, x in ipairs(edges.cited_by) do nb[#nb + 1] = x; direct[pairkey(it.id, x)] = true end
    it.neighbors = nb
  end

  -- Inverted buckets: a signal value → the note ids carrying it.
  local tag_b, term_b, cocite_b = {}, {}, {}
  local function push(bucket, key, id)
    local b = bucket[key]; if not b then b = {}; bucket[key] = b end
    b[#b + 1] = id
  end
  for _, it in ipairs(items) do
    for _, t in ipairs(it.tags) do if topical(t) then push(tag_b, t, it.id) end end
    for term in pairs(it.terms) do push(term_b, term, it.id) end
    if graph then for _, x in ipairs(it.neighbors) do push(cocite_b, x, it.id) end end
  end

  -- Accumulate pair scores across the buckets, skipping direct pairs and buckets
  -- too large to discriminate.
  local scored = {}
  local function accumulate(bucket, weight, kind)
    for key, ids in pairs(bucket) do
      if #ids >= 2 and #ids <= bucket_cap then
        for i = 1, #ids - 1 do
          for j = i + 1, #ids do
            local pk = pairkey(ids[i], ids[j])
            if not direct[pk] then
              local p = scored[pk]
              if not p then
                p = { a = ids[i], b = ids[j], score = 0, tags = {}, terms = {}, co = 0 }
                scored[pk] = p
              end
              p.score = p.score + weight
              if kind == 'tag' then p.tags[#p.tags + 1] = key
              elseif kind == 'term' then p.terms[#p.terms + 1] = key
              else p.co = p.co + 1 end
            end
          end
        end
      end
    end
  end
  accumulate(tag_b, 2, 'tag')
  accumulate(term_b, 1, 'term')
  accumulate(cocite_b, 2, 'cocite')

  local out = {}
  for _, p in pairs(scored) do
    if p.score >= min_score then
      local ia, ib = by_id[p.a], by_id[p.b]
      if ia and ib then
        out[#out + 1] = {
          a = { path = ia.path, title = ia.title, note_type = ia.note_type },
          b = { path = ib.path, title = ib.title, note_type = ib.note_type },
          score = p.score,
          shared = { tags = p.tags, terms = p.terms, co_citations = p.co },
        }
      end
    end
  end
  table.sort(out, function(x, y)
    if x.score ~= y.score then return x.score > y.score end
    local xk = (x.a.title or '') .. '\0' .. (x.b.title or '')
    local yk = (y.a.title or '') .. '\0' .. (y.b.title or '')
    return xk < yk
  end)
  local limited = {}
  for i = 1, math.min(limit, #out) do limited[i] = out[i] end

  return { ok = true, pairs = limited }
end

-- Age in whole days of an ISO-8601 date (`2026-08-01T12:21:30`), or nil if it does
-- not parse. Only the calendar day is read, which is all the staleness heuristic
-- needs.
local function iso_age_days(iso, now)
  local y, m, d = tostring(iso or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not y then return nil end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  if not t then return nil end
  return math.max(0, math.floor((now - t) / 86400))
end

-- True when the body carries a references/sources section — a heading named
-- References, Sources, Fontes, Bibliografia (or "…consultadas"). One of the two
-- ways a note records provenance (the other is a bib citation).
local function has_references_section(body)
  for line in (tostring(body or '') .. '\n'):gmatch('(.-)\n') do
    local h = line:match('^%s*#+%s*(.-)%s*$')
    if h then
      local hl = fold(h)
      if hl:match('^references') or hl:match('^sources')
        or hl:match('^fontes') or hl:match('^bibliografia') or hl:match('consultad') then
        return true
      end
    end
  end
  return false
end

--- Notes that likely need **re-checking** — the review queue for § 10 (a vault is
--- provisional knowledge, weighed by its provenance). It is advisory and heuristic:
--- it says "look at this again", never "this is wrong" — the judgement is the
--- assistant's, cross-checking the note against current knowledge and sources.
---
--- The strong, actionable signal is a **provenance gap**: a *substantive* note
--- (real body) that records **no references** — neither a bib citation nor a
--- `## References`/`## Sources` section — cannot be weighed, so it is flagged
--- (weight 3), as is a note with **no date** in its frontmatter (weight 1). **Age**
--- is a weak secondary signal: old is not wrong, so it only *ranks* among flagged
--- notes (+1 per year, capped) and never flags on its own — unless `opts.min_age_days`
--- is set, which adds every substantive note older than that (the plain review-queue
--- use). An age-driven flag is the weakest kind and needs the assistant's judgement
--- before acting: whether the note's topic is *age-sensitive* (see the skill and
--- `doc/AGENT_PROTOCOL.md` § 10) — this is left to judgement rather than a tag weight
--- on purpose, since a tag cannot vouch for a note's actual subject. Scoped to
--- `note`/`agg` (bib notes are sources; journals/scratch are logs). Reads each
--- candidate's frontmatter for its dates and bib citations; body comes from the index.
---@param opts table|nil  { limit? (20), min_score? (1), min_age_days?: integer }
---@return table  { ok, notes? }
---              notes: { path, title, note_type, score, reasons }[]
---              reasons: { no_references?, no_date?, age_days? }
function M.stale(opts)
  opts = opts or {}
  local limit        = opts.limit or 20
  local min_score    = opts.min_score or 1
  local min_age_days = opts.min_age_days
  local now          = os.time()

  local index = require('pkm.index')
  local yaml  = require('pkm.yaml')
  local out   = {}

  for _, e in ipairs(index.get_all()) do
    if e.note_type == 'note' or e.note_type == 'agg' then
      local body = e.body or ''
      if #(body:gsub('%s+', '')) >= 40 then   -- substantive: has claims worth sourcing
        local fm      = yaml.parse_frontmatter(vim.fn.readfile(e.path))
        local has_bib = fm and type(fm.cites) == 'table'
          and type(fm.cites.bib) == 'table' and #fm.cites.bib > 0
        local updated = fm and (fm.last_updated_on or fm.created_on)
        local age     = updated and iso_age_days(updated, now) or nil

        local reasons, score = {}, 0
        if not (has_bib or has_references_section(body)) then
          reasons.no_references = true
          score = score + 3
        end
        if not (updated and updated ~= '') then
          reasons.no_date = true
          score = score + 1
        end
        if age then
          reasons.age_days = age
          score = score + math.min(3, math.floor(age / 365))
        end

        local flagged = reasons.no_references or reasons.no_date
          or (min_age_days and age and age >= min_age_days)
        if flagged and score >= min_score then
          out[#out + 1] = {
            path = e.path, title = e.title, note_type = e.note_type,
            score = score, reasons = reasons,
          }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.title or '') < (b.title or '')
  end)
  local limited = {}
  for i = 1, math.min(limit, #out) do limited[i] = out[i] end

  return { ok = true, notes = limited }
end

--- Near-**duplicate** notes — pairs whose content is substantially the same, the
--- candidates for `merge`. Where `unlinked_pairs` finds notes that are *related*,
--- this finds notes that are nearly the *same*, so a fork or an accidental
--- re-creation can be folded back together. Advisory and read-only.
---
--- Similarity is a weighted blend of three Jaccard overlaps — **body** words (0.5,
--- the truest signal: two notes with the same body are duplicates), **title** terms
--- (0.3), and **tags** (0.2, the `by-claude` marker ignored) — over every pair of
--- *substantive* `note`/`agg` notes (bodies compared from the index, so no file
--- reads). All pairs are compared, so a pure body copy under a different title is
--- still caught; the cost is quadratic in the substantive-note count — a deliberate
--- sweep. Pairs at or above `opts.threshold` are returned, most-similar first.
---@param opts table|nil  { limit? (10), threshold?: number 0..1 (0.5) }
---@return table  { ok, pairs? }
---              pairs: { a, b, similarity, body_sim, title_sim, tag_sim }[]
---              a / b: { path, title, note_type }
function M.duplicates(opts)
  opts = opts or {}
  local limit     = opts.limit or 10
  local threshold = opts.threshold or 0.5

  local index = require('pkm.index')
  local items = {}
  for _, e in ipairs(index.get_all()) do
    if e.note_type == 'note' or e.note_type == 'agg' then
      local bw, wc = title_terms(e.body or ''), 0
      for _ in pairs(bw) do wc = wc + 1 end
      if wc >= 5 then                    -- enough content to compare meaningfully
        local tags = {}
        for _, t in ipairs(e.tags or {}) do if t ~= 'by-claude' then tags[t] = true end end
        items[#items + 1] = {
          path = e.path, title = e.title, note_type = e.note_type,
          tt = title_terms(e.title), tags = tags, bw = bw,
        }
      end
    end
  end

  local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

  local out = {}
  for i = 1, #items - 1 do
    for j = i + 1, #items do
      local A, B = items[i], items[j]
      local body_sim  = jaccard(A.bw, B.bw)
      local title_sim = jaccard(A.tt, B.tt)
      local tag_sim   = jaccard(A.tags, B.tags)
      local sim = 0.5 * body_sim + 0.3 * title_sim + 0.2 * tag_sim
      if sim >= threshold then
        out[#out + 1] = {
          a = { path = A.path, title = A.title, note_type = A.note_type },
          b = { path = B.path, title = B.title, note_type = B.note_type },
          similarity = round2(sim),
          body_sim = round2(body_sim), title_sim = round2(title_sim), tag_sim = round2(tag_sim),
        }
      end
    end
  end

  table.sort(out, function(x, y)
    if x.similarity ~= y.similarity then return x.similarity > y.similarity end
    local xk = (x.a.title or '') .. '\0' .. (x.b.title or '')
    local yk = (y.a.title or '') .. '\0' .. (y.b.title or '')
    return xk < yk
  end)
  local limited = {}
  for i = 1, math.min(limit, #out) do limited[i] = out[i] end

  return { ok = true, pairs = limited }
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
