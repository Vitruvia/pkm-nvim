-- =============================================================================
-- pkm.rename — Substitution over the names of a set of notes
-- =============================================================================
-- Dependencies : pkm.utils, pkm.yaml (lazy), pkm.index (lazy),
--                pkm.citations (lazy), pkm.picker / pkm.bufsync
--                (lazy, interactive flow only)
-- Consumed by  : pkm.actions (set_titles)
--
-- The notes in a selection do **not** share a name, so a bulk operation over
-- names is never "set it to X" — it is a substitution: match this, write that.
-- One input expresses it, in the syntax already in everyone's fingers:
--
--     pattern/replacement          the two halves of a :%s command
--     Aula \(\d\+\)/Aula 0\1       Neovim regex, with capture groups
--     rascunho                     no '/' yet: just show what matches
--     \/dados/ e dados             '\/' is a literal slash, not the separator
--
-- The regex is **Neovim's own** (`vim.fn.match` / `vim.fn.substitute`), not
-- Lua's: the same expression that works in `:%s` works here, including `\1`
-- backreferences, `\v`, `\c` and the rest.
--
-- Two layers:
--
--   plan_names()   pure-ish — takes names and a substitution, returns what each
--                  becomes. Its only outside call is Neovim's regex engine, so
--                  it is testable headlessly with no file and no UI.
--   apply_titles() the only writing function — one frontmatter write per
--                  changed note plus the mandatory index.invalidate, then a
--                  **single** title-propagation pass over the vault.
--
-- The flow is one panel: typing the substitution *is* the preview. See
-- picker.select_live — the rows update on every keystroke, showing
-- "before → after", and `<CR>` writes what is listed.
--
-- Public API:
--   parse_substitution(input)   → { find, replace? } | nil — pure
--   plan_names(items, sub)      → { {key, before, after, matched, changed, error?}… }
--   describe(sub)               → one-line description — pure
--   format_change(item)         → "stem   before → after" display row — pure
--   read_title(path)            → (fm, title) — read-only
--   title_items(paths)          → { {key, before}… } — read-only
--   apply_titles(plan)          → (applied, errors) — writes and propagates
--   title_flow(paths)           → the live panel
-- =============================================================================

local M = {}

local utils = require('pkm.utils')

-- =============================================================================
-- SECTION: Pure core
-- =============================================================================

--- Split a substitution expression into its two halves.
--- The separator is the first unescaped `/`; `\/` is a literal slash and does
--- not split. With no separator at all the whole text is the pattern and there
--- is no replacement yet — which is what makes "type to see what matches" a
--- state of its own rather than an accidental deletion.
---@param input string|nil
---@return { find: string, replace: string|nil }|nil
function M.parse_substitution(input)
  if not input or input == '' then return nil end

  local find_part, replace_part
  local i = 1
  while i <= #input do
    local c = input:sub(i, i)
    if c == '\\' then
      i = i + 2                      -- skip the escaped character
    elseif c == '/' then
      find_part    = input:sub(1, i - 1)
      replace_part = input:sub(i + 1)
      break
    else
      i = i + 1
    end
  end

  find_part = find_part or input
  if find_part == '' then return nil end

  --- `\/` reaches the regex engine as a plain slash.
  local function unescape(text)
    return (text:gsub('\\/', '/'))
  end

  return {
    find    = unescape(find_part),
    replace = replace_part and unescape(replace_part) or nil,
  }
end

--- Work out what each name would become under a substitution.
--- The input list is never mutated. A name that does not match is reported as
--- `matched = false` rather than as an error — not matching is information, not
--- a failure.
---@param items { key: string, before: string }[]
---@param sub   table|nil  Result of parse_substitution
---@return { key: string, before: string, after: string, matched: boolean, changed: boolean, error: string|nil }[]
function M.plan_names(items, sub)
  local out = {}

  for _, item in ipairs(items or {}) do
    local before = item.before or ''
    local matched, after, err = false, before, nil

    if not sub or not sub.find or sub.find == '' then
      matched = true                 -- nothing typed yet: everything is in play
    else
      local ok, pos = pcall(vim.fn.match, before, sub.find)
      if not ok then
        err = 'invalid pattern'
      else
        matched = pos >= 0
        if matched and sub.replace ~= nil then
          local ok2, result = pcall(vim.fn.substitute, before, sub.find, sub.replace, 'g')
          if not ok2 then
            err = 'invalid replacement'
          elseif result == '' then
            err = 'would leave it empty'
          else
            after = result
          end
        end
      end
    end

    out[#out + 1] = {
      key     = item.key,
      before  = before,
      after   = after,
      matched = matched,
      changed = (err == nil) and (after ~= before) or false,
      error   = err,
    }
  end

  return out
end

--- One-line description of a substitution, for the panel title.
---@param sub table|nil
---@return string
function M.describe(sub)
  if not sub or not sub.find then return 'Change titles' end
  if sub.replace == nil then
    return string.format("matching '%s'", sub.find)
  end
  return string.format("'%s' → '%s'", sub.find, sub.replace)
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
  if not item.changed then
    return string.format('%s   %s', stem, item.before)
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
  local yaml      = require('pkm.yaml')
  local index     = require('pkm.index')
  local citations = require('pkm.citations')
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

--- The note as it would read after the substitution: the frontmatter title line
--- carries the new value, so the preview shows the result and not the file as
--- it is now.
---@param item table  One planned row
---@return string[]
local function preview_lines(item)
  local lines = utils.read_lines(item.key)
  if not lines then return { '(unreadable)' } end

  local out = {}
  local in_frontmatter, done = false, false
  for idx, line in ipairs(lines) do
    if idx == 1 and line == '---' then
      in_frontmatter = true
      out[#out + 1] = line
    elseif in_frontmatter and not done and line == '---' then
      in_frontmatter = false
      done = true
      out[#out + 1] = line
    elseif in_frontmatter and line:match('^title:') then
      out[#out + 1] = 'title: ' .. item.after
    else
      out[#out + 1] = line
    end
  end

  return out
end

--- Change the titles of several notes at once, in one panel.
--- Typing the substitution is the preview: rows show `before → after` as the
--- expression is written, and `<CR>` applies to what is listed. There is no
--- form and no separate confirmation screen — the panel is both.
---
--- The panel comes back after a write, so several substitutions can be made in
--- a row without reopening anything; `<Esc>` is what ends the session. `<C-b>`
--- steps back to a picker over the same notes, for when the *selection* was
--- wrong rather than the expression.
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

  --- Rows for what has been typed so far. Before a `/` appears this is the set
  --- of titles that match; after it, the same set with their new values.
  ---@param prompt string|nil
  ---@return table[]
  local function compute(prompt)
    local sub  = M.parse_substitution(prompt)
    local plan = M.plan_names(items, sub)

    local rows = {}
    for _, row in ipairs(plan) do
      if row.matched or row.error then rows[#rows + 1] = row end
    end
    return rows
  end

  local picker = require('pkm.picker')

  --- Re-choose which notes, then come straight back here.
  local function go_back()
    picker.select(paths, {
      title = 'Notes to retitle',
      hint  = 'use listed',
    }, function(chosen) M.title_flow(chosen) end)
  end

  picker.select_live({
    title     = string.format('Change %d title%s  ·  pattern/replacement',
      #items, #items == 1 and '' or 's'),
    hint      = 'apply to listed',
    compute   = compute,
    display   = M.format_change,
    preview   = preview_lines,
    on_back   = go_back,
    on_cancel = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
  }, function(rows)
    local targets = {}
    for _, row in ipairs(rows) do
      if row.changed and not row.error then targets[#targets + 1] = row.key end
    end

    if #targets == 0 then
      vim.notify('[pkm] nothing to change — no replacement given?', vim.log.levels.INFO)
      M.title_flow(paths)
      return
    end

    -- Notes open with unsaved edits are asked about before anything is written;
    -- the common case never sees a prompt.
    local bufsync = require('pkm.bufsync')
    bufsync.guard(targets, function()
      local applied, errors = M.apply_titles(rows)

      -- What is on screen must agree with what is now on disk.
      bufsync.reload(targets)

      vim.notify(string.format('[pkm] %d title%s updated%s',
        applied, applied == 1 and '' or 's',
        errors > 0 and (', ' .. errors .. ' failed') or ''),
        errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)

      -- Back to the panel, over the notes as they now read: one more
      -- substitution costs no reopening, and <Esc> is what ends the session.
      M.title_flow(paths)
    end)
  end)
end

return M
