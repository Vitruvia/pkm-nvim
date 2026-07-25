-- =============================================================================
-- pkm.tags — Tag computation and batch application
-- =============================================================================
-- Dependencies : pkm.yaml (lazy), pkm.utils, pkm.index (lazy),
--                pkm.picker / pkm.filter / pkm.views (lazy, interactive flow only)
-- Consumed by  : pkm.citations (merge_tags), pkm.notes (relative note),
--                pkm.commands (:PKMTags batch modes)
--
-- Four layers, deliberately separated:
--
--   plan()     pure — takes a tag list and an operation set, returns the new
--              tag list. No I/O, no state, no UI. Every rule of the feature
--              lives here, so it can be tested without touching a file.
--   preview()  read-only — runs plan() over many notes and reports what would
--              change. Writes nothing.
--   apply()    the only writing function — same plan(), then one frontmatter
--              write per changed note.
--   batch_flow() the interactive layer on top: pick a scope, pick the notes,
--              name the tag, look at the preview, then apply. It decides
--              nothing on its own — every rule it obeys lives in plan().
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
--   format_preview(plan, header) → string[] display lines — pure
--   apply(paths, ops)      → (applied, errors) — writes and invalidates
--   all_note_paths()       → every indexed note path (helper for whole-vault ops)
--   batch_flow(kind)       → interactive add / remove / rename over a selection
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

--- Render a preview() result as display lines.
--- Pure, so the wording of a destructive confirmation is testable.
---@param plan   table   Result of preview()
---@param header string  First line, e.g. "Add tag 'draft'"
---@return string[]
function M.format_preview(plan, header)
  local count = #plan
  local lines = {
    string.format('  %s — %d note%s change%s  ·  <CR> apply  ·  q/<Esc> cancel',
      header, count, count == 1 and '' or 's', count == 1 and 's' or ''),
    '  ' .. string.rep('─', 64),
  }

  for _, item in ipairs(plan) do
    lines[#lines + 1] = '  ' .. vim.fn.fnamemodify(item.path, ':t:r')
    lines[#lines + 1] = string.format('      %s  →  %s',
      #item.before > 0 and table.concat(item.before, ', ') or '(none)',
      #item.after  > 0 and table.concat(item.after,  ', ') or '(none)')
  end

  if count == 0 then
    lines[#lines + 1] = '  (nothing would change)'
  end

  return lines
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

--- Resolve the candidate notes for a batch operation and pass them on.
--- Scopes: the note in the current buffer, the active view, or a filter.
---@param on_paths function(paths: string[])
local function choose_scope(on_paths)
  local views   = require('pkm.views')
  local current = vim.api.nvim_buf_get_name(0)
  local active  = views.get_last_view()

  local choices = { 'Filter…  (tag:x AND title:y)' }
  local kinds   = { 'filter' }
  if current ~= '' and current:match('%.md$') then
    choices[#choices + 1] = 'Current note  (' .. vim.fn.fnamemodify(current, ':t:r') .. ')'
    kinds[#kinds + 1]     = 'note'
  end
  if active then
    choices[#choices + 1] = "Current view  ('" .. active .. "')"
    kinds[#kinds + 1]     = 'view'
  end

  vim.ui.select(choices, { prompt = 'Which notes?' }, function(_, idx)
    if not idx then return end
    local kind = kinds[idx]

    if kind == 'note' then
      on_paths({ current })

    elseif kind == 'view' then
      on_paths(views.match_all(active))

    else
      vim.ui.input({ prompt = 'Filter: ' }, function(expr)
        if not expr or expr:match('^%s*$') then return end
        local paths = paths_matching(expr)
        if paths then vim.schedule(function() on_paths(paths) end) end
      end)
    end
  end)
end

--- Ask for the tag(s) an operation needs.
--- `remove` and `rename` offer the tags that exist in the vault, since acting
--- on a tag that is not there is always a mistake; `add` takes free text.
---@param kind    string  'add' | 'remove' | 'rename'
---@param on_ops  function(ops: table, header: string)
local function ask_tags(kind, on_ops)
  if kind == 'add' then
    vim.ui.input({ prompt = 'Tag to add: ' }, function(tag)
      local t = M.normalize(tag)
      if not t then return end
      vim.schedule(function() on_ops({ add = { t } }, "Add tag '" .. t .. "'") end)
    end)
    return
  end

  local existing = require('pkm.citations').get_all_tags()
  if #existing == 0 then
    vim.notify('[pkm] no tags exist yet', vim.log.levels.INFO)
    return
  end

  local prompt = kind == 'remove' and 'Tag to remove:' or 'Tag to rename:'
  vim.ui.select(existing, { prompt = prompt }, function(chosen)
    if not chosen then return end
    local from = M.normalize(chosen)
    if not from then return end

    if kind == 'remove' then
      vim.schedule(function()
        on_ops({ remove = { from } }, "Remove tag '" .. from .. "'")
      end)
      return
    end

    vim.ui.input({ prompt = string.format("Rename '%s' to: ", from) }, function(to)
      local target = M.normalize(to)
      if not target then return end
      if target == from then
        vim.notify('[pkm] same tag — nothing to do', vim.log.levels.INFO)
        return
      end
      vim.schedule(function()
        on_ops({ rename = { { from = from, to = target } } },
          string.format("Rename '%s' to '%s'", from, target))
      end)
    end)
  end)
end

--- Run one batch tag operation end to end.
--- Writes only after the preview float has been confirmed; an operation that
--- would change nothing says so and stops there.
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
      ask_tags(kind, function(ops, header)
        local plan = M.preview(selected, ops)
        if #plan == 0 then
          vim.notify(
            string.format('[pkm] %s — no note in the selection would change', header),
            vim.log.levels.INFO)
          return
        end

        require('pkm.picker').confirm({
          title      = 'PKMTags: confirm',
          lines      = M.format_preview(plan, header),
          on_cancel  = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
          on_confirm = function()
            local applied, errors = M.apply(selected, ops)
            vim.notify(string.format('[pkm] %s — %d note%s updated%s',
              header, applied, applied == 1 and '' or 's',
              errors > 0 and (', ' .. errors .. ' failed') or ''),
              errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
          end,
        })
      end)
    end)
  end)
end

return M
