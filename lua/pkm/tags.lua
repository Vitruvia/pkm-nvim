-- =============================================================================
-- pkm.tags — Tag computation and batch application
-- =============================================================================
-- Dependencies : pkm.yaml (lazy), pkm.utils, pkm.index (lazy),
--                pkm.picker / pkm.filter / pkm.views / pkm.bufsync
--                (lazy, interactive flow only)
-- Consumed by  : pkm.citations (merge_tags), pkm.notes (relative note),
--                pkm.commands (:PKMTags batch modes)
--
-- Four layers, deliberately separated:
--
--   plan()     pure — takes a tag list and an operation set, returns the new
--              tag list. No I/O, no state, no UI. Every rule of the feature
--              lives here, so it can be tested without touching a file.
--   preview()  read-only — runs plan() over many notes and reports what would
--              change. Writes nothing. tag_counts() is read-only too: it
--              answers "which tags exist here, and on how many notes".
--   apply()    the only writing function — same plan(), then one frontmatter
--              write per changed note.
--   batch_on()  the interactive layer on top of a selection that already
--              exists — the marks in a navigation panel, a view's notes, a
--              command argument. It decides nothing on its own: every rule it
--              obeys lives in plan(), every screen it shows belongs to
--              pkm.picker. batch_flow() is the same thing for callers with no
--              selection, and only adds the steps needed to build one.
--
-- Operation set (all fields optional):
--   { add    = { "tag", … },              -- appended when absent
--     remove = { "tag", … },              -- dropped when present
--     rename = { { from = "old", to = "new" }, … } }
--
-- Rules, applied in this order and asserted by test_v180_p1:
--   1. rename first, then remove, then add.
--   2. Comparison is case-insensitive, but a surviving tag keeps the exact form
--      it had in the file. Only tags this operation introduces (added or
--      renamed) are stored normalised, matching what :PKMTag add writes. This
--      is why a batch never rewrites a note merely to change "Beta" to "beta".
--   3. No duplicates ever: renaming onto an existing tag merges into it, and
--      adding a tag already present is a no-op.
--   4. Relative order of surviving tags is preserved; additions go last.
--   5. remove beats add for the same tag — an operation set that both adds and
--      removes "x" leaves the note without it.
--
-- Disk-write discipline: apply() writes files, so it MUST invalidate the index
-- for each one. This is the opposite of the buffer-only metadata commands
-- (citations.add_tag/remove_tag), which must NOT invalidate. Keep the two
-- paths apart.
--
-- Public API:
--   normalize(tag)         → canonical form of one tag, or nil when empty
--   plan(tags, ops)        → (new_tags, changed) — pure
--   preview(paths, ops)    → { {path, before, after}… } — read-only
--   tag_counts(paths?)     → { {tag, count, paths}… } sorted — read-only
--   rank_tags(rows, ctx)   → the same rows ordered by relevance — pure
--   suggest_tags(paths?)   → every tag, ranked for that selection — read-only
--   format_change(item)    → one "before → after" display line — pure
--   apply(paths, ops)      → (applied, errors) — writes and invalidates
--   all_note_paths()       → every indexed note path (helper for whole-vault ops)
--   scope_choices(path, view) → the scopes a batch can start from — pure
--   parse_command_args(fargs) → (mode, ops, header, err) for :PKMTags — pure
--   browse_by_tag()        → tag picker → browse pre-seeded to tag:<x>
--   batch_on(paths, kind, ops?, header?) → batch over notes already chosen
--   batch_flow(kind)       → the same, for callers that must first build one
--   view_membership(paths) → { {name, paths, total}… } — which views hold them
--   view_flow(paths, kind, ctx?) → add to / remove from a view, by tags
--   new_note_in_view(name, on_done?) → create a note already inside a view
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Pure core
-- =============================================================================

--- Canonical form of a tag: trimmed and lower-cased.
---@param tag any
---@return string|nil  nil when the value is not a usable tag
function M.normalize(tag)
  if type(tag) ~= 'string' then return nil end
  local t = tag:match('^%s*(.-)%s*$'):lower()
  if t == '' then return nil end
  return t
end

--- Build a lookup set from a tag list.
---@param list table|nil
---@return table<string, boolean>
local function to_set(list)
  local set = {}
  for _, tag in ipairs(list or {}) do
    local t = M.normalize(tag)
    if t then set[t] = true end
  end
  return set
end

--- Apply an operation set to a tag list.
--- Pure: no I/O, no globals, and the input list is never mutated.
---@param tags table|nil  Current tags (any case; non-strings are dropped)
---@param ops  table|nil  { add?, remove?, rename? }
---@return string[] new_tags
---@return boolean  changed  true when new_tags differs from the input
function M.plan(tags, ops)
  ops = ops or {}

  -- Baseline: the tags as they are written in the file, de-duplicated
  -- case-insensitively (first spelling wins). `raw` is what gets written back
  -- when the tag survives untouched; `norm` is what every comparison uses.
  local original, seen_original = {}, {}
  for _, tag in ipairs(tags or {}) do
    local norm = M.normalize(tag)
    if norm and not seen_original[norm] then
      seen_original[norm] = true
      original[#original + 1] = { raw = tag, norm = norm }
    end
  end

  -- 1. rename — map old names onto new ones in place, merging duplicates.
  --    A renamed tag is a new value, so it is stored normalised.
  local rename_map = {}
  for _, pair in ipairs(ops.rename or {}) do
    local from = M.normalize(pair.from or pair[1])
    local to   = M.normalize(pair.to   or pair[2])
    if from and to then rename_map[from] = to end
  end

  local renamed, seen = {}, {}
  for _, item in ipairs(original) do
    local target = rename_map[item.norm]
    local norm   = target or item.norm
    local raw    = target or item.raw
    if not seen[norm] then
      seen[norm] = true
      renamed[#renamed + 1] = { raw = raw, norm = norm }
    end
  end

  -- 2. remove.
  local remove_set = to_set(ops.remove)
  local kept = {}
  for _, item in ipairs(renamed) do
    if not remove_set[item.norm] then kept[#kept + 1] = item end
  end

  -- 3. add — appended in the order given, skipping anything already present
  --    and anything the same operation set removes.
  local present = {}
  for _, item in ipairs(kept) do present[item.norm] = true end
  for _, tag in ipairs(ops.add or {}) do
    local norm = M.normalize(tag)
    if norm and not present[norm] and not remove_set[norm] then
      present[norm] = true
      kept[#kept + 1] = { raw = norm, norm = norm }
    end
  end

  local out = {}
  for _, item in ipairs(kept) do out[#out + 1] = item.raw end

  local changed = #out ~= #original
  if not changed then
    for i = 1, #out do
      if out[i] ~= original[i].raw then changed = true break end
    end
  end

  return out, changed
end

-- =============================================================================
-- SECTION: Batch — read-only
-- =============================================================================

--- Every note path the index knows about.
--- Convenience for whole-vault operations; callers with their own selection
--- (a view, a picker) pass that instead.
---@return string[]
function M.all_note_paths()
  local paths = {}
  for _, entry in ipairs(require('pkm.index').get_all()) do
    paths[#paths + 1] = entry.path
  end
  return paths
end

--- Read one note's frontmatter and current tag list.
---@param path string
---@return table|nil fm
---@return string[]  tags
local function read_tags(path)
  local lines = utils.read_lines(path)
  if not lines or #lines == 0 then return nil, {} end

  local fm = require('pkm.yaml').parse_frontmatter(lines)
  if not fm then return nil, {} end

  local tags = {}
  if type(fm.tags) == 'table' then
    tags = fm.tags
  elseif type(fm.tags) == 'string' then
    tags = { fm.tags }
  end
  return fm, tags
end

--- Report what apply() would change, without touching any file.
--- Notes that are unreadable, have no frontmatter, or would not change are
--- simply absent from the result.
---@param paths string[]
---@param ops   table
---@return { path: string, before: string[], after: string[] }[]
function M.preview(paths, ops)
  local out = {}
  for _, path in ipairs(paths or {}) do
    local fm, tags = read_tags(path)
    if fm then
      local after, changed = M.plan(tags, ops)
      if changed then
        out[#out + 1] = { path = path, before = tags, after = after }
      end
    end
  end
  return out
end

--- Which tags exist, and on how many notes.
--- Reads the index, never the disk: index entries already carry a normalised
--- tag list, so two spellings of the same tag ("Draft", "draft") collapse into
--- one row here — which is precisely what the old disk scan failed to do.
--- Passing `paths` restricts the counts to that selection, so a batch operation
--- can offer only the tags its own notes actually carry.
---@param paths string[]|nil  Restrict to these notes; nil means the whole vault
---@return { tag: string, count: integer, paths: string[] }[]  sorted by tag
function M.tag_counts(paths)
  local index   = require('pkm.index')
  local entries = {}

  if paths then
    for _, path in ipairs(paths) do
      local entry = index.get(path)
      if entry then entries[#entries + 1] = entry end
    end
  else
    entries = index.get_all()
  end

  local rows, by_tag = {}, {}
  for _, entry in ipairs(entries) do
    -- A note listing the same tag twice still counts once.
    local counted = {}
    for _, tag in ipairs(entry.tags or {}) do
      local norm = M.normalize(tag)
      if norm and not counted[norm] then
        counted[norm] = true
        local row = by_tag[norm]
        if not row then
          row = { tag = norm, count = 0, paths = {} }
          by_tag[norm] = row
          rows[#rows + 1] = row
        end
        row.count = row.count + 1
        row.paths[#row.paths + 1] = entry.path
      end
    end
  end

  table.sort(rows, function(a, b) return a.tag < b.tag end)
  return rows
end

--- Order tags by how likely they are to be the one wanted for a selection.
--- Pure: every input is explicit, so the ranking can be asserted without a
--- vault. Rows are copied, never reordered in place, and each copy carries the
--- `note` explaining why it sits where it does.
---
--- Four tiers, in this order:
---   1. already on *some* of the selected notes — completing a set is the most
---      common reason to reach for a tag;
---   2. tags that co-occur, elsewhere in the vault, with the tags the selection
---      already has;
---   3. everything else, most used first;
---   4. already on *all* of them — adding it would change nothing, so it goes
---      last rather than being hidden.
---@param rows table[]  { { tag, count, paths }, … }
---@param ctx  table    { selected_count, on_selected = {tag→n}, cooccurrence = {tag→n} }
---@return { tag: string, count: integer, paths: string[], note: string|nil }[]
function M.rank_tags(rows, ctx)
  ctx = ctx or {}
  local selected_count = ctx.selected_count or 0
  local on_selected    = ctx.on_selected or {}
  local cooccurrence   = ctx.cooccurrence or {}

  local ranked = {}
  for _, row in ipairs(rows) do
    local on   = on_selected[row.tag] or 0
    local cooc = cooccurrence[row.tag] or 0

    local tier, score, note
    if on > 0 and on < selected_count then
      tier, score = 1, on
      note = string.format('on %d of %d selected', on, selected_count)
    elseif on > 0 then
      tier, score = 4, on
      note = 'already on all selected'
    elseif cooc > 0 then
      tier, score = 2, cooc
      note = string.format('co-occurs on %d note%s', cooc, cooc == 1 and '' or 's')
    else
      tier, score = 3, row.count
    end

    ranked[#ranked + 1] = {
      tag   = row.tag,
      count = row.count,
      paths = row.paths,
      note  = note,
      _tier = tier,
      _score = score,
    }
  end

  table.sort(ranked, function(a, b)
    if a._tier ~= b._tier then return a._tier < b._tier end
    if a._score ~= b._score then return a._score > b._score end
    return a.tag < b.tag
  end)

  return ranked
end

--- Every vault tag, ordered by relevance to a selection of notes.
--- Read-only. The ranking itself is `rank_tags`; this only gathers the context
--- it needs — which of the selection's notes already carry each tag, and which
--- tags keep company with the selection's tags elsewhere in the vault.
---@param paths string[]|nil  The selection; nil ranks by usage alone
---@return { tag: string, count: integer, paths: string[], note: string|nil }[]
function M.suggest_tags(paths)
  local all = M.tag_counts()
  if not paths or #paths == 0 then
    return M.rank_tags(all, {})
  end

  local on_selected = {}
  local sel_set     = {}
  for _, row in ipairs(M.tag_counts(paths)) do
    on_selected[row.tag] = row.count
    sel_set[row.tag]     = true
  end

  -- Co-occurrence: on every note that shares a tag with the selection, count
  -- the tags the selection does not have yet.
  local cooccurrence = {}
  for _, entry in ipairs(require('pkm.index').get_all()) do
    local shares, others = false, {}
    for _, tag in ipairs(entry.tags or {}) do
      local norm = M.normalize(tag)
      if norm then
        if sel_set[norm] then shares = true else others[norm] = true end
      end
    end
    if shares then
      for tag in pairs(others) do
        cooccurrence[tag] = (cooccurrence[tag] or 0) + 1
      end
    end
  end

  return M.rank_tags(all, {
    selected_count = #paths,
    on_selected    = on_selected,
    cooccurrence   = cooccurrence,
  })
end

--- Render one preview() item as a display row: "stem   before → after".
--- Pure, so the wording shown before a destructive write is testable.
---@param item table  One entry of a preview() result
---@return string
function M.format_change(item)
  return string.format('%s   %s  →  %s',
    vim.fn.fnamemodify(item.path, ':t:r'),
    #item.before > 0 and table.concat(item.before, ', ') or '(none)',
    #item.after  > 0 and table.concat(item.after,  ', ') or '(none)')
end

-- =============================================================================
-- SECTION: Batch — writes
-- =============================================================================

--- Apply an operation set to every note in paths that it changes.
--- Writes the frontmatter to disk and invalidates the index entry for each
--- changed note — mandatory here, precisely because this path does write.
---@param paths string[]
---@param ops   table
---@return integer applied  Notes written
---@return integer errors   Notes that could not be written
function M.apply(paths, ops)
  local yaml    = require('pkm.yaml')
  local index   = require('pkm.index')
  local applied, errors = 0, 0

  for _, path in ipairs(paths or {}) do
    local fm, tags = read_tags(path)
    if fm then
      local after, changed = M.plan(tags, ops)
      if changed then
        fm.tags = after
        local ok = pcall(yaml.save_frontmatter, fm, nil, path)
        if ok then
          index.invalidate(path)
          applied = applied + 1
        else
          errors = errors + 1
        end
      end
    end
  end

  return applied, errors
end

--- Apply a tag operation to one *named* note and keep an open buffer in step.
--- The typed counterpart to the buffer-only :PKMTag add/remove: it writes
--- to disk, so — like a citation or a vault switch — it refuses to run behind an
--- unsaved buffer rather than persist edits the user has not seen, then reloads
--- the buffer so what it wrote is what is shown.
---@param path string  Absolute note path
---@param ops  table   { add?, remove?, rename? } — see M.plan
---@return boolean ok
---@return string|nil err
function M.write_note_tags(path, ops)
  if type(path) ~= 'string' or vim.fn.filereadable(path) == 0 then
    return false, 'note not found: ' .. tostring(path)
  end

  local bufsync = require('pkm.bufsync')
  local bufnr   = bufsync.buffer_for(path)
  if bufnr and vim.bo[bufnr].modified then
    return false, 'the note has unsaved changes — save it first'
  end

  M.apply({ path }, ops)
  bufsync.reload({ path })
  return true
end

-- =============================================================================
-- SECTION: Interactive flow
-- =============================================================================
--
-- Scope → notes → tag → preview → apply. Every step can be backed out of, and
-- nothing is written before the preview has been confirmed.

--- Paths of the notes matching a filter expression, using the same DSL as
--- :PKMBrowse and the view filters.
---@param expr string
---@return string[]|nil paths  nil when the expression does not parse
local function paths_matching(expr)
  local filter    = require('pkm.filter')
  local tree, err = filter.parse(expr)
  if not tree then
    vim.notify('[pkm] ' .. (err or 'invalid filter'), vim.log.levels.ERROR)
    return nil
  end

  local out = {}
  for _, entry in ipairs(require('pkm.index').get_all()) do
    if filter.eval(tree, entry) then out[#out + 1] = entry.path end
  end
  return out
end

--- The scopes a batch operation can start from, given the session's state.
--- Pure, so the one case that matters can be asserted: with nothing open and no
--- active view only 'filter' remains, and a menu of one option is a step that
--- decides nothing.
---@param current_path string|nil  Name of the buffer in the current window
---@param active_view  string|nil  Name of the last opened view, if any
---@return { kind: string, label: string }[]  never empty; 'filter' is always last
function M.scope_choices(current_path, active_view)
  local choices = {}

  if current_path and current_path ~= '' and current_path:match('%.md$') then
    choices[#choices + 1] = {
      kind  = 'note',
      label = 'Current note  (' .. vim.fn.fnamemodify(current_path, ':t:r') .. ')',
    }
  end
  if active_view then
    choices[#choices + 1] = {
      kind  = 'view',
      label = "Current view  ('" .. active_view .. "')",
    }
  end

  choices[#choices + 1] = { kind = 'filter', label = 'Filter…  (tag:x AND title:y)' }
  return choices
end

--- Prompt for a filter expression and hand over what it matches.
---@param on_paths function(paths: string[])
local function ask_filter(on_paths)
  vim.ui.input({ prompt = 'Filter: ' }, function(expr)
    if not expr or expr:match('^%s*$') then return end
    local paths = paths_matching(expr)
    if paths then vim.schedule(function() on_paths(paths) end) end
  end)
end

--- Resolve the candidate notes for a batch operation and pass them on.
--- Only reached when the caller has no selection of its own — from a navigation
--- panel the notes are already chosen, and none of this runs.
---@param on_paths function(paths: string[])
local function choose_scope(on_paths)
  local views   = require('pkm.views')
  local current = vim.api.nvim_buf_get_name(0)
  local active  = views.get_last_view()
  local choices = M.scope_choices(current, active)

  -- One viable scope is not a choice: go straight to it.
  if #choices == 1 then
    ask_filter(on_paths)
    return
  end

  local labels = {}
  for _, choice in ipairs(choices) do labels[#labels + 1] = choice.label end

  vim.ui.select(labels, { prompt = 'Which notes?' }, function(_, idx)
    if not idx then return end
    local kind = choices[idx].kind

    if kind == 'note' then
      on_paths({ current })
    elseif kind == 'view' then
      on_paths(views.match_all(active))
    else
      ask_filter(on_paths)
    end
  end)
end

--- Ask for the tag(s) an operation needs. Every mode goes through the same
--- picker, so naming a tag always looks the same and always shows what the tag
--- already means in the vault:
---
---   add     every tag, ordered by relevance to the selection (see
---           suggest_tags), and typing a tag that does not exist creates it.
---   remove  only the tags the selected notes actually carry — removing one
---           they do not have could only be a mistake.
---   rename  the same list for the source; then every tag for the destination,
---           where picking an existing one merges into it and typing a new one
---           renames to it.
---@param kind    string    'add' | 'remove' | 'rename'
---@param paths   string[]  The notes the operation will run over
---@param on_ops  function(ops: table, header: string)
local function ask_tags(kind, paths, on_ops)
  local picker = require('pkm.picker')

  if kind == 'add' then
    picker.select_tag(M.suggest_tags(paths), {
      title     = 'Tag to add',
      allow_new = true,
    }, function(chosen)
      local tag = M.normalize(chosen)
      if not tag then return end
      on_ops({ add = { tag } }, "Add tag '" .. tag .. "'")
    end)
    return
  end

  local rows = M.tag_counts(paths)
  if #rows == 0 then
    vim.notify('[pkm] no tags on the selected notes', vim.log.levels.INFO)
    return
  end

  local title = kind == 'remove' and 'Tag to remove' or 'Tag to rename'
  picker.select_tag(rows, { title = title }, function(chosen)
    local from = M.normalize(chosen)
    if not from then return end

    if kind == 'remove' then
      on_ops({ remove = { from } }, "Remove tag '" .. from .. "'")
      return
    end

    -- Destination: every tag but the source. Choosing one that exists merges
    -- into it — the same operation :PKMTag merge performs, reached from here.
    local targets = {}
    for _, row in ipairs(M.suggest_tags(paths)) do
      if row.tag ~= from then targets[#targets + 1] = row end
    end

    picker.select_tag(targets, {
      title     = string.format("Rename '%s' to", from),
      allow_new = true,
    }, function(to)
      local target = M.normalize(to)
      if not target then return end
      if target == from then
        vim.notify('[pkm] same tag — nothing to do', vim.log.levels.INFO)
        return
      end
      on_ops({ rename = { { from = from, to = target } } },
        string.format("Rename '%s' to '%s'", from, target))
    end)
  end)
end

--- Interpret `:PKMTags` arguments.
--- Pure: no editor state, no I/O, so the command's contract — the one an
--- advanced user or a script relies on — is testable on its own.
---
---   (nothing)              → browse
---   browse                 → browse
---   add|remove <tag>       → that operation, tag already resolved
---   add|remove             → that operation, tag to be prompted for
---   rename <from> <to>     → rename, both tags resolved
---
---@param fargs string[]|nil  Command arguments, already split by Neovim
---@return string|nil mode    'browse' | 'add' | 'remove' | 'rename'; nil on error
---@return table|nil  ops     Operation set when the arguments carry the tags
---@return string|nil header  Wording for the confirmation, alongside ops
---@return string|nil err     Message when the arguments do not make sense
function M.parse_command_args(fargs)
  --- A quoted argument reaches us with its quotes; a tag never wants them.
  ---@param arg string|nil
  ---@return string|nil
  local function unquote(arg)
    if type(arg) ~= 'string' then return nil end
    return M.normalize((arg:gsub('^(["\'])(.*)%1$', '%2')))
  end

  -- The verb dispatch comes from pkm.args. `browse` is the default, and — unlike
  -- views — a first word that is not a declared verb is a mistake here, not the
  -- name of anything, so `is_verb` is what turns it into an error.
  local p = require('pkm.args').parse({ fargs = fargs }, {
    verbs   = { 'browse', 'add', 'remove', 'rename' },
    default = 'browse',
  })

  if not p.is_verb and #p.positional > 0 then
    return nil, nil, nil, "unknown mode '" .. p.positional[1] .. "'"
  end

  local mode, pos = p.verb, p.positional

  if mode == 'browse' then
    if #pos > 0 then return nil, nil, nil, 'browse takes no further argument' end
    return 'browse'
  end

  if mode == 'add' or mode == 'remove' then
    if #pos > 1 then return nil, nil, nil, mode .. ' takes at most one tag' end
    if #pos == 0 then return mode end

    local tag = unquote(pos[1])
    if not tag then return nil, nil, nil, 'empty tag' end

    if mode == 'add' then
      return mode, { add = { tag } }, "Add tag '" .. tag .. "'"
    end
    return mode, { remove = { tag } }, "Remove tag '" .. tag .. "'"
  end

  if mode == 'rename' then
    if #pos ~= 2 then
      return nil, nil, nil, 'rename needs both the old and the new tag'
    end

    local from, to = unquote(pos[1]), unquote(pos[2])
    if not from or not to then return nil, nil, nil, 'empty tag' end
    if from == to then return nil, nil, nil, 'same tag — nothing to do' end

    return mode,
      { rename = { { from = from, to = to } } },
      string.format("Rename '%s' to '%s'", from, to)
  end

  return nil, nil, nil, "unknown mode"
end

--- Pick a tag and browse the notes carrying it.
--- The picker shows how many notes each tag is on and previews them, so the
--- choice is informed before the browser opens.
function M.browse_by_tag()
  local rows = M.tag_counts()
  if #rows == 0 then
    vim.notify('[pkm] no tags found', vim.log.levels.INFO)
    return
  end

  require('pkm.picker').select_tag(rows, { title = 'Browse by tag' }, function(tag)
    -- A tag with a space must reach the filter parser quoted.
    local expr = 'tag:' .. (tag:find('%s') and ('"' .. tag .. '"') or tag)
    if pcall(require, 'telescope') then
      require('pkm.telescope').browse(expr)
    else
      require('pkm.ui').browse(expr)
    end
  end)
end

--- Show the change list for `ops` over `paths`, and write what is confirmed.
--- The confirmation is the ordinary note picker, so narrowing or marking there
--- drops notes from the batch; nothing is written until it returns.
---
--- A batch of **one** note is a different screen. There is nothing to narrow,
--- so the note picker would promise a per-note choice the operation does not
--- have — which is what made `:PKMView add` end in a Telescope list of a single
--- entry. It gets an all-or-nothing gate instead; and with `opts.typed` — the
--- user having already named both the operation and its target on the command
--- line — it gets no screen at all, because typing *was* the operation.
--- Removal keeps its gate either way (`doc/PRINCIPLES.md`: every removal
--- confirms).
---@param paths  string[]
---@param ops    table
---@param header string   e.g. "Rename 'draf' to 'draft'"
---@param opts   table|nil  { typed? = boolean, removal? = boolean }
local function confirm_and_apply(paths, ops, header, opts)
  opts = opts or {}

  local plan = M.preview(paths, ops)
  if #plan == 0 then
    vim.notify(
      string.format('[pkm] %s — no note in the selection would change', header),
      vim.log.levels.INFO)
    return
  end

  -- Only the notes that would actually change reach the confirmation, each
  -- rendered as its own before → after row.
  local changed, by_path = {}, {}
  for _, item in ipairs(plan) do
    changed[#changed + 1] = item.path
    by_path[item.path]    = item
  end

  --- Notes open with unsaved edits are asked about before anything is written,
  --- and every open buffer is re-read afterwards so what is on screen agrees
  --- with what is on disk.
  ---@param confirmed string[]
  local function write(confirmed)
    local bufsync = require('pkm.bufsync')
    bufsync.guard(confirmed, function()
      local applied, errors = M.apply(confirmed, ops)
      bufsync.reload(confirmed)

      vim.notify(string.format('[pkm] %s — %d note%s updated%s',
        header, applied, applied == 1 and '' or 's',
        errors > 0 and (', ' .. errors .. ' failed') or ''),
        errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
    end)
  end

  if #changed == 1 then
    if opts.typed and not opts.removal then
      write(changed)
      return
    end

    require('pkm.picker').confirm({
      title = 'PKMTags ' .. header,
      lines = {
        '  ' .. header .. '  ·  <CR> apply  ·  q/<Esc> cancel',
        '  ' .. string.rep('─', 64),
        '  ' .. M.format_change(by_path[changed[1]]),
      },
      on_cancel  = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
      on_confirm = function() write(changed) end,
    })
    return
  end

  require('pkm.picker').select(changed, {
    title     = 'PKMTags ' .. header,
    hint      = 'apply to listed',
    display   = function(path) return M.format_change(by_path[path]) end,
    on_cancel = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
  }, write)
end

--- Run a batch tag operation over notes that are **already chosen** — the marks
--- in a navigation panel, a view's notes, a command's argument. This is the
--- entry point every panel uses: no scope menu, no note picker, straight to the
--- tag prompt and then the confirmation.
--- With `ops` supplied the tag prompt is skipped too, which is what makes
--- `:PKMTags rename old new` a single step.
---@param paths  string[]
---@param kind   string       'add' | 'remove' | 'rename'
---@param ops    table|nil    Ready-made operation set; prompts when omitted
---@param header string|nil   Wording for the confirmation; derived when omitted
function M.batch_on(paths, kind, ops, header)
  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return
  end

  if ops then
    confirm_and_apply(paths, ops, header or 'Tag change')
    return
  end

  ask_tags(kind, paths, function(built_ops, built_header)
    confirm_and_apply(paths, built_ops, built_header)
  end)
end

--- Run one batch tag operation end to end, starting from a scope.
--- The fallback path, for when the operation is invoked without a selection:
--- resolve a scope, pick the notes, then hand over to batch_on.
---@param kind string  'add' | 'remove' | 'rename'
function M.batch_flow(kind)
  choose_scope(function(candidates)
    if #candidates == 0 then
      vim.notify('[pkm] no notes in that scope', vim.log.levels.INFO)
      return
    end

    require('pkm.picker').select(candidates, {
      title = 'PKMTags ' .. kind,
      hint  = 'use listed',
    }, function(selected)
      M.batch_on(selected, kind)
    end)
  end)
end

-- =============================================================================
-- SECTION: View membership
-- =============================================================================
--
-- A view is a filter, so putting a note in one means making the filter match.
-- Tags are the only part of a note a bulk operation may rewrite for that —
-- a title or a body cannot be invented — so this asks `filter.tag_sets` which
-- tag sets satisfy the view, and applies one of them.
--
-- Removing is the same question about the negation: which tag sets make the
-- filter *false*. Both directions therefore run through the same machinery, and
-- through the same preview and write as every other tag batch.

--- Human-readable form of one alternative, for the choice menu.
---@param alt table
---@return string
local function describe_alt(alt)
  local parts = {}
  for _, tag in ipairs(alt.add) do parts[#parts + 1] = '+' .. tag end
  for _, tag in ipairs(alt.remove) do parts[#parts + 1] = '-' .. tag end
  if #parts == 0 then return '(no tag change)' end
  return table.concat(parts, ', ')
end

--- The part of an alternative that is not already true of every note in scope.
---
--- `filter.tag_sets` answers "what does this view require", so an alternative
--- lists the whole requirement — including the tags the note already carries.
--- Offering *"+administração-financeira-orçamentária, +concursos-públicos"* to a
--- note that already has the first one describes the destination rather than
--- the change, and makes two alternatives hard to tell apart.
---
--- A tag is dropped only when it is redundant for **every** note in scope, so
--- the reduced form is still accurate for the whole batch. Pure, and display
--- only: the operation keeps applying the full set, which is idempotent —
--- `plan()` already leaves a tag that is present exactly where it is.
---@param alt   table
---@param scope string[]  The notes the operation will act on
---@return table  A copy, with the redundant tags removed
local function narrow_alt(alt, scope)
  local index = require('pkm.index')

  local carried = {}      -- tag → how many notes in scope have it
  local counted = 0
  for _, path in ipairs(scope or {}) do
    local entry = index.get(path)
    if entry then
      counted = counted + 1
      local seen = {}
      for _, tag in ipairs(entry.tags or {}) do
        local norm = M.normalize(tag)
        if norm and not seen[norm] then
          seen[norm]    = true
          carried[norm] = (carried[norm] or 0) + 1
        end
      end
    end
  end

  if counted == 0 then return alt end

  local out = { add = {}, remove = {}, blockers = alt.blockers }
  for _, tag in ipairs(alt.add) do
    -- Every note already has it: adding says nothing.
    if (carried[tag] or 0) < counted then out.add[#out.add + 1] = tag end
  end
  for _, tag in ipairs(alt.remove) do
    -- No note has it: removing says nothing either.
    if (carried[tag] or 0) > 0 then out.remove[#out.remove + 1] = tag end
  end
  return out
end

--- Which of the defined views currently hold the given notes.
--- Read-only. One index lookup per path and one filter pass per (view, path),
--- so it costs V·N evaluations and materialises no sorted path array — the
--- selection is a handful of notes, not the vault.
--- `total` counts the paths that could be evaluated at all: a path absent from
--- the index contributes to neither.
---@param paths string[]
---@return { name: string, paths: string[], total: integer }[]  in view order
function M.view_membership(paths)
  local views  = require('pkm.views')
  local index  = require('pkm.index')
  local filter = require('pkm.filter')

  local entries = {}
  for _, path in ipairs(paths or {}) do
    local entry = index.get(path)
    if entry then entries[#entries + 1] = entry end
  end

  local rows = {}
  for _, name in ipairs(views.list()) do
    -- An unreadable view is not an error here: it simply holds nothing. Saying
    -- so is `match_all`'s job, and it already notifies.
    local tree  = views.get_tree(name)
    local inside = {}
    if tree then
      for _, entry in ipairs(entries) do
        if filter.eval(tree, entry) then inside[#inside + 1] = entry.path end
      end
    end
    rows[#rows + 1] = { name = name, paths = inside, total = #entries }
  end
  return rows
end

--- Add the selected notes to a view, or take them out of it, by tags.
--- Reports rather than guesses when the view's filter cannot be satisfied by
--- tags alone: adding tags that will not make the note match would be worse
--- than saying so.
---
--- `ctx.view` — the view the notes were chosen from — **orders the choice, it
--- never makes it**. Knowing where a selection came from says nothing about
--- where it should go: from inside a view, adding to *that* view is the one
--- pointless option, and the note may equally need removing from a different
--- view that also contains it. So `add` offers every view, and `remove` offers
--- exactly the views the selection is actually in.
---
--- `ctx.target` is the opposite: a view the user named outright
--- (`:PKMView add leituras`). That *is* the answer, so no menu is shown.
---@param paths string[]
---@param kind  string     'add' | 'remove'
---@param ctx   table|nil   { view? = string, target? = string, on_back? = function }
function M.view_flow(paths, kind, ctx)
  ctx = ctx or {}

  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return
  end

  local views = require('pkm.views')

  --- Everything after the view is known.
  ---@param name  string
  ---@param scope string[]  The notes the operation acts on
  local function with_view(name, scope)
    local tree, err = views.get_tree(name)
    if not tree then
      vim.notify('[pkm] ' .. (err or 'view has no filter'), vim.log.levels.ERROR)
      return
    end

    -- Removal is satisfying the negation: the same question, mirrored.
    local target = (kind == 'add') and tree or { type = 'NOT', args = { tree } }
    local alts   = require('pkm.filter').tag_sets(target)

    local usable = {}
    for _, alt in ipairs(alts) do
      if #alt.blockers == 0 and (#alt.add > 0 or #alt.remove > 0) then
        usable[#usable + 1] = alt
      end
    end

    if #usable == 0 then
      -- Say which condition is in the way; a blocker is the whole reason.
      local blocker
      for _, alt in ipairs(alts) do
        if #alt.blockers > 0 then blocker = alt.blockers[1] break end
      end
      vim.notify(blocker
        and string.format("[pkm] '%s' cannot be satisfied with tags alone — it "
          .. 'also requires %s', name, blocker)
        or string.format("[pkm] '%s' has no tag condition to change", name),
        vim.log.levels.WARN)
      return
    end

    local verb = (kind == 'add') and 'Add to' or 'Remove from'

    ---@param alt table
    local function apply(alt)
      confirm_and_apply(scope, { add = alt.add, remove = alt.remove },
        string.format("%s '%s' (%s)", verb, name,
          describe_alt(narrow_alt(alt, scope))),
        { typed = ctx.target ~= nil, removal = (kind == 'remove') })
    end

    if #usable == 1 then
      apply(usable[1])
      return
    end

    -- Several tag sets satisfy the view: which one is a judgement about
    -- meaning, not something to guess. Same panel as every other screen in the
    -- flow — a Telescope user should not drop into the command line here.
    -- Each is described by what it would *change*, not by what the view
    -- requires in full.
    require('pkm.picker').choose(usable, {
      title   = string.format("%s '%s' — which tags?", verb, name),
      display = function(alt) return describe_alt(narrow_alt(alt, scope)) end,
    }, apply)
  end

  local rows = M.view_membership(paths)
  if #rows == 0 then
    vim.notify('[pkm] no views defined', vim.log.levels.INFO)
    return
  end

  -- A view the user *named* is an answer, and the only kind of answer this
  -- function accepts from its caller. `ctx.view` is provenance and merely
  -- orders (see above); `ctx.target` is `:PKMView remove leituras`, where the
  -- question was already asked and answered on the command line. Keeping the
  -- two apart is what stops the v1.8.1 defect from growing back.
  if ctx.target then
    for _, row in ipairs(rows) do
      if row.name == ctx.target then
        if kind == 'remove' and #row.paths == 0 then
          vim.notify(string.format("[pkm] not in '%s' — nothing to remove",
            ctx.target), vim.log.levels.INFO)
          return
        end
        with_view(row.name, (kind == 'remove') and row.paths or paths)
        return
      end
    end
    vim.notify(string.format("[pkm] no view named '%s'", ctx.target),
      vim.log.levels.ERROR)
    return
  end

  -- Which views are even candidates. Removing a note from a view it is not in
  -- is not an operation, it is a mistake, so removal never offers one.
  local candidates = {}
  for _, row in ipairs(rows) do
    if kind ~= 'remove' or #row.paths > 0 then
      candidates[#candidates + 1] = row
    end
  end

  if #candidates == 0 then
    vim.notify('[pkm] no selected note belongs to a view', vim.log.levels.INFO)
    return
  end

  -- Ordering, and only ordering, is where `ctx.view` counts. For removal it is
  -- the likeliest target, so it leads; for adding it is the one view the notes
  -- are already in, so it gets no privilege and the views with something left
  -- to add lead instead. Names break every tie, so the menu is reproducible.
  table.sort(candidates, function(a, b)
    if kind == 'remove' then
      if (a.name == ctx.view) ~= (b.name == ctx.view) then
        return a.name == ctx.view
      end
      if #a.paths ~= #b.paths then return #a.paths > #b.paths end
    else
      local a_done = a.total > 0 and #a.paths == a.total
      local b_done = b.total > 0 and #b.paths == b.total
      if a_done ~= b_done then return b_done end
    end
    return a.name:lower() < b.name:lower()
  end)

  ---@param row table
  ---@return string
  local function label(row)
    local n = #row.paths
    if kind == 'remove' then
      return (n == row.total)
        and string.format('%s  (all %d selected)', row.name, n)
        or  string.format('%s  (%d of %d selected)', row.name, n, row.total)
    end
    if n == 0 then return row.name end
    return (n == row.total)
      and string.format('%s  (all selected already in)', row.name)
      or  string.format('%s  (%d of %d already in)', row.name, n, row.total)
  end

  --- Removal acts on the notes that are actually in the view; adding acts on
  --- everything chosen, since a note already there simply does not change.
  ---@param row table
  local function enter(row)
    with_view(row.name, (kind == 'remove') and row.paths or paths)
  end

  -- A menu that decides nothing is a step to cut, not a step to keep.
  if #candidates == 1 then
    enter(candidates[1])
    return
  end

  --- What the row under the cursor means for this selection, spelled out: the
  --- label can only carry a count, and "which of my notes is it talking about"
  --- is the question a count raises.
  ---@param row table
  ---@return string[]
  local function preview(row)
    local inside = {}
    for _, path in ipairs(row.paths) do
      inside[path] = true
    end

    local lines = { '# ' .. row.name, '' }
    lines[#lines + 1] = (kind == 'remove')
      and string.format('%d of %d selected note%s in this view:',
        #row.paths, row.total, row.total == 1 and ' is' or 's are')
      or  string.format('%d of %d selected note%s already in this view:',
        #row.paths, row.total, row.total == 1 and ' is' or 's are')
    lines[#lines + 1] = ''

    for _, path in ipairs(paths) do
      lines[#lines + 1] = string.format('  %s %s',
        inside[path] and '·' or ' ', vim.fn.fnamemodify(path, ':t'))
    end
    return lines
  end

  require('pkm.picker').choose(candidates, {
    title         = (kind == 'add') and 'Add to which view?' or 'Remove from which view?',
    display       = label,
    preview       = preview,
    preview_title = 'This view, and your selection',
    on_back       = ctx.on_back,
  }, enter)
end

--- Create a note that already belongs to a view.
---
--- The same question as `view_flow('add')`, asked before the note exists: which
--- tags make this view's filter match. Because the note is new it carries none,
--- so only the tags to *add* matter and there is nothing to remove — and the
--- tags are seeded at creation rather than written afterwards, so the note is
--- born matching instead of being edited into place.
---
--- A view tags cannot fully satisfy does not block creation: the note is still
--- created with whatever tags do apply, and the condition in the way is named,
--- because "this will not match until you write the title" is information the
--- author needs *while* writing the note, not instead of it.
---@param name string  The view the note should belong to
---@param opts table|nil  { where? = nil|'left'|'right'|integer  which window to
---                         open it in, see `utils.focus_editing_win`;
---                         on_done? = function(path) }
function M.new_note_in_view(name, opts)
  opts = opts or {}
  local on_done = opts.on_done

  local views = require('pkm.views')
  local notes = require('pkm.notes')

  local tree, err = views.get_tree(name)
  if not tree then
    vim.notify('[pkm] ' .. (err or 'view has no filter'), vim.log.levels.ERROR)
    return
  end

  local alts = require('pkm.filter').tag_sets(tree)

  ---@param alt table|nil
  local function create(alt)
    local seeds = alt and alt.add or {}
    if alt and #alt.blockers > 0 then
      vim.notify(string.format(
        "[pkm] '%s' also requires %s — the new note will not match until that "
        .. 'is true', name, alt.blockers[1]), vim.log.levels.WARN)
    end

    local path = notes.create_new_note(nil, { tags = seeds, where = opts.where })
    -- create_new_note returns nil when it still has prompts to run; it finishes
    -- on its own either way, and the caller only ever wants the refresh.
    if on_done then on_done(path) end
  end

  -- Tags alone cannot reach it at all: still worth creating, still worth
  -- saying so.
  if #alts == 0 then
    vim.notify(string.format(
      "[pkm] '%s' cannot be satisfied by tags — creating a plain note", name),
      vim.log.levels.WARN)
    create(nil)
    return
  end

  -- Prefer the alternatives tags can actually satisfy; fall back to the
  -- blocked ones so the warning above has something to name.
  local usable = {}
  for _, alt in ipairs(alts) do
    if #alt.blockers == 0 and #alt.add > 0 then usable[#usable + 1] = alt end
  end
  if #usable == 0 then usable = alts end

  if #usable == 1 then
    create(usable[1])
    return
  end

  require('pkm.picker').choose(usable, {
    title   = string.format("New note in '%s' — which tags?", name),
    display = describe_alt,
  }, create)
end

return M
