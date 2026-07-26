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
--   split_stem(stem)            → (prefix, name) for a consolidated stem — pure
--   stem_items(paths)           → (items, skipped) — read-only
--   planned_stem(item)          → the final stem for one planned row — pure
--   find_collisions(plan, fn)   → rows that would share a name — pure
--   apply_titles(plan)          → (applied, errors) — writes and propagates
--   apply_filenames(plan)       → (applied, errors, refusal) — renames and
--                                 rewrites every reference in one pass
--   title_flow(paths, ctx)      → the live panel, over titles
--   filename_flow(paths, ctx)   → the live panel, over filenames
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
      -- Carried through untouched: filenames need the fixed prefix the
      -- substitution must not see (see split_stem).
      prefix  = item.prefix,
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
-- SECTION: Filenames — read
-- =============================================================================
--
-- A consolidated note is named `NNNN_type_Rest_Of_It`. Only the last part is
-- the note's own name; the number and type are identity, not description, so
-- the substitution never sees them and the result is rebuilt around them.
--
-- Journal and scratchpad names *are* their timestamp. Renaming those in bulk
-- would destroy the convention their whole ordering rests on, so they are
-- reported as skipped instead of silently left out.

--- Split a consolidated stem into its fixed prefix and its editable part.
---@param stem string
---@return string|nil prefix  e.g. "0042_note_"
---@return string|nil name    e.g. "Kant_On_Duty"
function M.split_stem(stem)
  local number, note_type, name = stem:match('^(%d+)_([a-z]+)_(.+)$')
  if not number then return nil, nil end
  return string.format('%s_%s_', number, note_type), name
end

--- Editable filename parts of a set of notes, as plan_names() input.
--- Read-only. Notes whose name is not a consolidated stem come back in the
--- second return value, with the reason, so the panel can say why they are not
--- in the list rather than appearing to have lost them.
---@param paths string[]
---@return { key: string, before: string, prefix: string }[] items
---@return { key: string, reason: string }[] skipped
function M.stem_items(paths)
  local items, skipped = {}, {}

  for _, path in ipairs(paths or {}) do
    local stem = vim.fn.fnamemodify(path, ':t:r')
    local prefix, name = M.split_stem(stem)

    if prefix then
      items[#items + 1] = { key = path, before = name, prefix = prefix }
    else
      skipped[#skipped + 1] = {
        key    = path,
        reason = stem:match('^journal_') and 'journal name is its timestamp'
                 or stem:match('^scratch_') and 'scratchpad name is its timestamp'
                 or 'not a consolidated note',
      }
    end
  end

  return items, skipped
end

--- Filenames two notes would end up sharing.
--- Pure. A rename batch that produces a duplicate is refused whole rather than
--- resolved by inventing a suffix — the numbering prefix already guarantees
--- uniqueness, so a collision means the substitution was wrong.
---@param plan table  Result of plan_names() over stem_items()
---@param stems_of function(item: table)→string  Final stem for one planned row
---@return { key: string, other: string, stem: string }[]
function M.find_collisions(plan, stems_of)
  local seen, out = {}, {}

  for _, item in ipairs(plan or {}) do
    if not item.error then
      local stem = stems_of(item)
      if seen[stem] then
        out[#out + 1] = { key = item.key, other = seen[stem], stem = stem }
      else
        seen[stem] = item.key
      end
    end
  end

  return out
end

--- The stem a planned row would produce: its prefix plus the sanitised result.
---@param item table
---@return string
function M.planned_stem(item)
  local safe = (item.after or ''):gsub('%s+', '_'):gsub('[<>:"/\\|?*]', '')
    :gsub('_+', '_'):gsub('^_', ''):gsub('_$', '')
  return (item.prefix or '') .. safe
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

--- Rename the planned files, then rewrite every reference in one pass.
--- Refuses the whole batch when two notes would end up sharing a name: the
--- numbering prefix already guarantees uniqueness, so a collision means the
--- substitution was wrong, and half-applying it would leave dangling links.
---@param plan table  Result of plan_names() over stem_items()
---@return integer applied  Notes renamed
---@return integer errors   Notes that could not be renamed
---@return string|nil refusal  Set when nothing was attempted at all
function M.apply_filenames(plan)
  local notes     = require('pkm.notes')
  local citations = require('pkm.citations')

  local collisions = M.find_collisions(plan, M.planned_stem)
  if #collisions > 0 then
    local first = collisions[1]
    return 0, 0, string.format("two notes would both be named '%s'", first.stem)
  end

  local applied, errors = 0, 0
  local renames = {}

  for _, item in ipairs(plan or {}) do
    if item.changed and not item.error then
      local old_stem = vim.fn.fnamemodify(item.key, ':t:r')
      local new_stem = M.planned_stem(item)

      local ok, new_path, err = notes.rename_file(item.key, new_stem)
      if ok and new_path then
        applied = applied + 1
        local _, title = M.read_title(new_path)
        renames[#renames + 1] = { old = old_stem, new = new_stem, title = title }
      else
        errors = errors + 1
        vim.notify('[pkm] ' .. old_stem .. ': ' .. (err or 'rename failed'),
          vim.log.levels.ERROR)
      end
    end
  end

  -- One pass for the whole batch, rewriting each citing note once.
  if #renames > 0 then citations.update_references_on_renames(renames) end

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

--- What a rename would do, shown for the row under the cursor: the new
--- filename, how many notes would have to be rewritten because they cite this
--- one, and then the note itself for identification.
--- The citer count comes from the note's own `cited_by` — the backlink the
--- citation system maintains — so it costs one read, not a vault scan.
---@param item table  One planned row
---@return string[]
local function rename_preview_lines(item)
  local stem = vim.fn.fnamemodify(item.key, ':t:r')
  local out  = { '# ' .. stem .. '.md', '' }

  if item.error then
    out[#out + 1] = '✗ ' .. item.error
  elseif item.changed then
    out[#out + 1] = '→ ' .. M.planned_stem(item) .. '.md'
    local citers = #require('pkm.export').read_citation_edges(item.key).cited_by
    out[#out + 1] = string.format('%d note%s cite%s this one and would be rewritten',
      citers, citers == 1 and '' or 's', citers == 1 and 's' or '')
  else
    out[#out + 1] = '(unchanged)'
  end

  out[#out + 1] = ''
  out[#out + 1] = string.rep('─', 40)
  out[#out + 1] = ''
  vim.list_extend(out, utils.read_lines(item.key) or { '(unreadable)' })

  return out
end

--- Rename the files of several notes at once, in one panel.
--- The same substitution as titles, over the editable part of the filename —
--- the `NNNN_type_` prefix is identity and never enters it.
---
--- Unlike titles, the write is **all or nothing**: renaming rewrites `[[links]]`
--- in every citing note, and a batch that half-applies leaves dangling links. So
--- `<CR>` leads to a final gate that accepts or refuses the whole list, rather
--- than letting notes be dropped from it one by one.
---@param paths string[]  Notes already chosen, e.g. the marks in a panel
---@param ctx   table|nil  { on_back? = function }
function M.filename_flow(paths, ctx)
  ctx = ctx or {}
  if not paths or #paths == 0 then
    vim.notify('[pkm] no notes selected', vim.log.levels.INFO)
    return
  end

  local items, skipped = M.stem_items(paths)

  if #skipped > 0 then
    vim.notify(string.format('[pkm] %d note%s not renameable: %s',
      #skipped, #skipped == 1 and '' or 's', skipped[1].reason
      .. (#skipped > 1 and ' (and others)' or '')), vim.log.levels.WARN)
  end
  if #items == 0 then
    vim.notify('[pkm] no consolidated notes in the selection', vim.log.levels.INFO)
    return
  end

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

  local go_back = ctx.on_back or function()
    picker.select(paths, {
      title = 'Notes to rename',
      hint  = 'use listed',
    }, function(chosen) M.filename_flow(chosen, ctx) end)
  end

  picker.select_live({
    title     = string.format('Rename %d file%s  ·  pattern/replacement',
      #items, #items == 1 and '' or 's'),
    hint      = 'review and apply',
    compute   = compute,
    display   = M.format_change,
    preview   = rename_preview_lines,
    on_back   = go_back,
    on_cancel = function() vim.notify('[pkm] cancelled', vim.log.levels.INFO) end,
  }, function(rows)
    local planned = {}
    for _, row in ipairs(rows) do
      if row.changed and not row.error then planned[#planned + 1] = row end
    end

    if #planned == 0 then
      vim.notify('[pkm] nothing to rename — no replacement given?', vim.log.levels.INFO)
      M.filename_flow(paths, ctx)
      return
    end

    -- Collisions are refused before the gate is even shown: there is nothing to
    -- confirm about a batch that cannot be applied.
    local collisions = M.find_collisions(planned, M.planned_stem)
    if #collisions > 0 then
      vim.notify(string.format("[pkm] refused: two notes would both be named '%s'",
        collisions[1].stem), vim.log.levels.ERROR)
      M.filename_flow(paths, ctx)
      return
    end

    -- The all-or-nothing gate. Every line is shown, plus what it will cost in
    -- rewritten citing notes. The header already says the answer covers the
    -- whole list, so the closing line states the cost and nothing else — a
    -- caveat here reads as a warning about a problem, which this is not.
    local lines = {
      string.format('  Rename %d file%s  ·  <CR> apply all  ·  q/<Esc> cancel',
        #planned, #planned == 1 and '' or 's'),
      '  ' .. string.rep('─', 64),
    }
    local citers = 0
    for _, row in ipairs(planned) do
      lines[#lines + 1] = '  ' .. vim.fn.fnamemodify(row.key, ':t:r')
      lines[#lines + 1] = '      →  ' .. M.planned_stem(row) .. '.md'
      citers = citers + #require('pkm.export').read_citation_edges(row.key).cited_by
    end
    lines[#lines + 1] = ''
    lines[#lines + 1] = citers > 0
      and string.format('  Also updates %d citation%s in other notes.',
        citers, citers == 1 and '' or 's')
      or  '  No other note cites these.'

    local keys = {}
    for _, row in ipairs(planned) do keys[#keys + 1] = row.key end

    picker.confirm({
      title      = 'PKMRename: confirm',
      lines      = lines,
      on_cancel  = function()
        vim.notify('[pkm] cancelled', vim.log.levels.INFO)
        M.filename_flow(paths, ctx)
      end,
      on_confirm = function()
        local bufsync = require('pkm.bufsync')
        bufsync.guard(keys, function()
          local applied, errors, refusal = M.apply_filenames(planned)
          if refusal then
            vim.notify('[pkm] refused: ' .. refusal, vim.log.levels.ERROR)
            return
          end

          vim.notify(string.format('[pkm] %d file%s renamed%s',
            applied, applied == 1 and '' or 's',
            errors > 0 and (', ' .. errors .. ' failed') or ''),
            errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
        end)
      end,
    })
  end)
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
---@param ctx   table|nil  { on_back? = function } — reopens whatever chose them
function M.title_flow(paths, ctx)
  ctx = ctx or {}
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

  --- Back means *where the notes came from* — the browser, the view, the panel
  --- — so the selection can genuinely be redone. Only when the caller did not
  --- say how does this fall back to narrowing the set already in hand.
  local go_back = ctx.on_back or function()
    picker.select(paths, {
      title = 'Notes to retitle',
      hint  = 'use listed',
    }, function(chosen) M.title_flow(chosen, ctx) end)
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
      M.title_flow(paths, ctx)
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
      M.title_flow(paths, ctx)
    end)
  end)
end

return M
