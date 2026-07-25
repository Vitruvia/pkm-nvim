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
--      renamed) are stored normalised, matching what :PKMAddTag writes. This
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
    -- into it — the same operation :PKMMergeTags performs, reached from here.
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
  fargs = fargs or {}
  if #fargs == 0 then return 'browse' end

  --- A quoted argument reaches us with its quotes; a tag never wants them.
  ---@param arg string|nil
  ---@return string|nil
  local function unquote(arg)
    if type(arg) ~= 'string' then return nil end
    return M.normalize((arg:gsub('^(["\'])(.*)%1$', '%2')))
  end

  local mode = fargs[1]:lower()

  if mode == 'browse' then
    if #fargs > 1 then return nil, nil, nil, 'browse takes no further argument' end
    return 'browse'
  end

  if mode == 'add' or mode == 'remove' then
    if #fargs > 2 then
      return nil, nil, nil, mode .. ' takes at most one tag'
    end
    if #fargs == 1 then return mode end

    local tag = unquote(fargs[2])
    if not tag then return nil, nil, nil, 'empty tag' end

    if mode == 'add' then
      return mode, { add = { tag } }, "Add tag '" .. tag .. "'"
    end
    return mode, { remove = { tag } }, "Remove tag '" .. tag .. "'"
  end

  if mode == 'rename' then
    if #fargs ~= 3 then
      return nil, nil, nil, 'rename needs both the old and the new tag'
    end

    local from, to = unquote(fargs[2]), unquote(fargs[3])
    if not from or not to then return nil, nil, nil, 'empty tag' end
    if from == to then return nil, nil, nil, 'same tag — nothing to do' end

    return mode,
      { rename = { { from = from, to = to } } },
      string.format("Rename '%s' to '%s'", from, to)
  end

  return nil, nil, nil, "unknown mode '" .. fargs[1] .. "'"
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
---@param paths  string[]
---@param ops    table
---@param header string   e.g. "Rename 'draf' to 'draft'"
local function confirm_and_apply(paths, ops, header)
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

  require('pkm.picker').select(changed, {
    title     = 'PKMTags ' .. header,
    hint      = 'apply to listed',
    display   = function(path) return M.format_change(by_path[path]) end,
    on_cancel = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
  }, function(confirmed)
    -- Notes open with unsaved edits are asked about before anything is
    -- written, and every open buffer is re-read afterwards so what is on
    -- screen agrees with what is on disk.
    local bufsync = require('pkm.bufsync')
    bufsync.guard(confirmed, function()
      local applied, errors = M.apply(confirmed, ops)
      bufsync.reload(confirmed)

      vim.notify(string.format('[pkm] %s — %d note%s updated%s',
        header, applied, applied == 1 and '' or 's',
        errors > 0 and (', ' .. errors .. ' failed') or ''),
        errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
    end)
  end)
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

return M
