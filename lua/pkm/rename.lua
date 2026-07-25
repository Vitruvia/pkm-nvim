-- =============================================================================
-- pkm.rename — Pattern-based renaming over a set of notes
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy), pkm.index (lazy),
--                pkm.citations (lazy), pkm.picker (lazy, interactive flow only)
-- Consumed by  : pkm.actions (set_titles)
--
-- The notes in a selection do **not** share a name. So a bulk operation over
-- names is never "set it to X" — it is "change *this part* of each one", which
-- is why a pattern is the input rather than a value.
--
-- Two layers, the same split the tag engine uses:
--
--   plan_names()  pure — takes the current names and a pattern, returns what
--                 each one would become. No I/O, no state, no UI. Every rule
--                 lives here, so it is tested without touching a file.
--   apply_titles() the only writing function — one frontmatter write per
--                 changed note, plus index.invalidate (mandatory: this writes
--                 to disk), and **one** title propagation pass at the end.
--
-- Why propagation is batched: `citations.propagate_title` globs and reads every
-- note in three folders *per call*, so calling it note-by-note over a batch is
-- quadratic. `citations.propagate_titles` does the same work in one pass.
--
-- Patterns are **literal by default**. Real note names carry `-`, `.`, `(` and
-- `%`, all of which are Lua pattern magic; a plain "replace this text" that
-- silently misfired on them would be worse than useless. The one form that does
-- take a Lua pattern (`capture`) is a mode the user chooses on purpose.
--
-- Pattern shape (one op per operation):
--   { op = 'prefix',  text = 'draft — ' }   → prepend
--   { op = 'suffix',  text = ' (wip)'   }   → append
--   { op = 'remove',  text = '[wip] '   }   → drop every literal occurrence
--   { op = 'replace', from = 'Draft', to = 'Notes' }   → literal, all matches
--   { op = 'capture', from = 'Aula (%d+) %- (.+)', to = '%2 (aula %1)' }
--
-- Public API:
--   plan_names(items, pattern)  → { {key, before, after, changed, error?}… } pure
--   describe(pattern)           → one-line description of the operation — pure
--   format_change(item)         → "stem   before → after" display row — pure
--   read_title(path)            → (fm, title) — read-only
--   apply_titles(plan)          → (applied, errors) — writes and propagates
--   title_flow(paths)           → interactive: pattern → preview → apply
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Pure core
-- =============================================================================

--- Trim surrounding whitespace.
---@param text string
---@return string
local function trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Apply one pattern to one name.
--- Returns the new name, or nil plus a reason when the pattern cannot produce
--- a usable one. A pattern that simply does not match is not an error: it
--- returns the name unchanged, and the caller reports it as "no change".
---@param before  string
---@param pattern table
---@return string|nil after
---@return string|nil err
local function apply_pattern(before, pattern)
  local op = pattern and pattern.op

  if op == 'prefix' then
    if not pattern.text or pattern.text == '' then return nil, 'no text given' end
    return pattern.text .. before

  elseif op == 'suffix' then
    if not pattern.text or pattern.text == '' then return nil, 'no text given' end
    return before .. pattern.text

  elseif op == 'remove' then
    if not pattern.text or pattern.text == '' then return nil, 'no text given' end
    -- Literal: the text is escaped, so "(v2)" removes "(v2)" and not a group.
    -- Cutting from the middle would leave the two surrounding spaces touching,
    -- so runs are collapsed — removal is about the text, not about respacing.
    local after = before:gsub(vim.pesc(pattern.text), '')
    after = after:gsub('%s%s+', ' ')
    return trim(after)

  elseif op == 'replace' then
    if not pattern.from or pattern.from == '' then return nil, 'no text to replace' end
    -- Both sides literal. The replacement is escaped separately and bound to
    -- its own local first: `s:gsub(a, b)` where `b` is itself a gsub call would
    -- pass that call's *count* as gsub's third argument — a substitution limit
    -- of zero, which silently does nothing.
    local repl  = (pattern.to or ''):gsub('%%', '%%%%')
    local after = before:gsub(vim.pesc(pattern.from), repl)
    return trim(after)

  elseif op == 'capture' then
    if not pattern.from or pattern.from == '' then return nil, 'no pattern given' end
    -- The one place a Lua pattern is honoured. A malformed one raises, so it
    -- is caught and reported per note rather than aborting the batch.
    local ok, after = pcall(string.gsub, before, pattern.from, pattern.to or '')
    if not ok then return nil, 'invalid pattern' end
    return trim(after)
  end

  return nil, 'unknown operation'
end

--- Work out what each name would become.
--- Pure: no I/O, no globals, and the input list is never mutated.
---@param items   { key: string, before: string }[]
---@param pattern table
---@return { key: string, before: string, after: string, changed: boolean, error: string|nil }[]
function M.plan_names(items, pattern)
  local out = {}

  for _, item in ipairs(items or {}) do
    local before = item.before or ''
    local after, err = apply_pattern(before, pattern)

    if after and after == '' then
      after, err = nil, 'would leave it empty'
    end

    out[#out + 1] = {
      key     = item.key,
      before  = before,
      after   = after or before,
      changed = (after ~= nil) and (after ~= before) or false,
      error   = err,
    }
  end

  return out
end

--- One-line description of what a pattern does, for the confirmation header.
---@param pattern table
---@return string
function M.describe(pattern)
  local op = pattern and pattern.op

  if op == 'prefix'  then return string.format("Prefix with '%s'", pattern.text or '') end
  if op == 'suffix'  then return string.format("Suffix with '%s'", pattern.text or '') end
  if op == 'remove'  then return string.format("Remove '%s'", pattern.text or '') end
  if op == 'replace' then
    return string.format("Replace '%s' with '%s'", pattern.from or '', pattern.to or '')
  end
  if op == 'capture' then
    return string.format("Pattern '%s' → '%s'", pattern.from or '', pattern.to or '')
  end
  return 'Rename'
end

--- Render one planned change as a display row.
--- Pure, so the wording shown before a write is testable.
---@param item table  One entry of a plan_names() result
---@return string
function M.format_change(item)
  local stem = vim.fn.fnamemodify(item.key, ':t:r')
  if item.error then
    return string.format('%s   %s  ✗  %s', stem, item.before, item.error)
  end
  return string.format('%s   %s  →  %s', stem, item.before, item.after)
end

-- =============================================================================
-- SECTION: Titles — read
-- =============================================================================

--- Read one note's frontmatter and its stored title.
--- The title comes from the file, not the index: this is what a write would be
--- based on, and an empty title stays empty rather than being humanised from
--- the filename the way `citations.get_note_title` does.
---@param path string
---@return table|nil fm
---@return string    title
function M.read_title(path)
  local lines = utils.read_lines(path)
  if not lines or #lines == 0 then return nil, '' end

  local fm = require('pkm.yaml').parse_frontmatter(lines)
  if not fm then return nil, '' end

  return fm, type(fm.title) == 'string' and fm.title or ''
end

--- Current titles of a set of notes, as plan_names() input.
--- Read-only. Notes without frontmatter are left out.
---@param paths string[]
---@return { key: string, before: string }[]
function M.title_items(paths)
  local items = {}
  for _, path in ipairs(paths or {}) do
    local fm, title = M.read_title(path)
    if fm then items[#items + 1] = { key = path, before = title } end
  end
  return items
end

-- =============================================================================
-- SECTION: Titles — writes
-- =============================================================================

--- Write the planned titles, then propagate them in one pass.
--- Writes the frontmatter and invalidates the index entry for each changed
--- note — mandatory here, precisely because this path does write. Entries that
--- carry an error, or that would not change, are skipped.
---@param plan table  Result of plan_names() over title_items()
---@return integer applied  Notes written
---@return integer errors   Notes that could not be written
function M.apply_titles(plan)
  local yaml       = require('pkm.yaml')
  local index      = require('pkm.index')
  local citations  = require('pkm.citations')
  local applied, errors = 0, 0

  -- identifier → new title, so the propagation pass runs once for the batch
  -- rather than once per note.
  local titles = {}

  for _, item in ipairs(plan or {}) do
    if item.changed and not item.error then
      local fm = M.read_title(item.key)
      if not fm then
        errors = errors + 1
      else
        fm.title = item.after
        local ok = pcall(yaml.save_frontmatter, fm, nil, item.key)
        if ok then
          index.invalidate(item.key)
          applied = applied + 1

          local _, id = citations.get_note_type_and_id(item.key)
          if id then titles[id] = item.after end
        else
          errors = errors + 1
        end
      end
    end
  end

  if next(titles) then citations.propagate_titles(titles) end

  return applied, errors
end

-- =============================================================================
-- SECTION: Interactive flow
-- =============================================================================
--
-- Pattern → preview → apply. The preview is the ordinary note picker, so a note
-- can still be dropped from the batch: titles are independent of one another,
-- and applying to three of five leaves nothing inconsistent. (Filenames are the
-- opposite case, and get an all-or-nothing gate instead.)

--- Ask for the operation and its operands.
--- The operation list is small and fixed, so it stays `vim.ui.select` — the
--- same criterion as the Simple/Deep menu of `:PKMExport`.
---@param on_pattern function(pattern: table)
local function ask_pattern(on_pattern)
  local ops = {
    { op = 'prefix',  label = 'Add a prefix' },
    { op = 'suffix',  label = 'Add a suffix' },
    { op = 'remove',  label = 'Remove some text' },
    { op = 'replace', label = 'Replace some text' },
    { op = 'capture', label = 'Rebuild from a pattern  (advanced)' },
  }

  local labels = {}
  for _, entry in ipairs(ops) do labels[#labels + 1] = entry.label end

  vim.ui.select(labels, { prompt = 'Change the title how?' }, function(_, idx)
    if not idx then return end
    local op = ops[idx].op

    if op == 'prefix' or op == 'suffix' or op == 'remove' then
      local prompt = op == 'remove' and 'Text to remove: ' or 'Text to add: '
      vim.ui.input({ prompt = prompt }, function(text)
        if not text or text == '' then return end
        vim.schedule(function() on_pattern({ op = op, text = text }) end)
      end)
      return
    end

    local from_prompt = op == 'replace' and 'Text to replace: ' or 'Lua pattern: '
    vim.ui.input({ prompt = from_prompt }, function(from)
      if not from or from == '' then return end
      local to_prompt = op == 'replace' and 'Replace with: ' or 'Rebuild as (use %1): '
      vim.ui.input({ prompt = to_prompt }, function(to)
        if to == nil then return end
        vim.schedule(function() on_pattern({ op = op, from = from, to = to }) end)
      end)
    end)
  end)
end

--- Change the title of several notes at once.
---@param paths string[]  Notes already chosen, e.g. the marks in a panel
function M.title_flow(paths)
  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return
  end

  local items = M.title_items(paths)
  if #items == 0 then
    vim.notify('[pkm] no readable frontmatter in the selection', vim.log.levels.INFO)
    return
  end

  ask_pattern(function(pattern)
    local plan   = M.plan_names(items, pattern)
    local header = M.describe(pattern)

    -- Only what would actually change reaches the confirmation; an entry that
    -- errored is shown too, since a pattern that fails everywhere should say so
    -- rather than look like "nothing matched".
    local shown, by_key = {}, {}
    for _, item in ipairs(plan) do
      if item.changed or item.error then
        shown[#shown + 1] = item.key
        by_key[item.key]  = item
      end
    end

    if #shown == 0 then
      vim.notify(
        string.format('[pkm] %s — no title in the selection would change', header),
        vim.log.levels.INFO)
      return
    end

    require('pkm.picker').select(shown, {
      title     = 'PKMTitle ' .. header,
      hint      = 'apply to listed',
      display   = function(key) return M.format_change(by_key[key]) end,
      on_cancel = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
    }, function(confirmed)
      local chosen = {}
      for _, key in ipairs(confirmed) do chosen[#chosen + 1] = by_key[key] end

      local applied, errors = M.apply_titles(chosen)
      vim.notify(string.format('[pkm] %s — %d title%s updated%s',
        header, applied, applied == 1 and '' or 's',
        errors > 0 and (', ' .. errors .. ' failed') or ''),
        errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
    end)
  end)
end

return M
