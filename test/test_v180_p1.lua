-- test/test_v180_p1.lua
-- Tests for v1.8.0 Phase 1: the tag engine and the relative note.
--
-- The pure core (tags.plan) is tested first and hardest: it is where a wrong
-- rule would silently rewrite frontmatter across the whole vault. The batch
-- layer is then checked against a disposable corpus, including the invariant
-- that preview() writes nothing and that apply() only touches notes that
-- actually change.
--
-- Runs against a real headless Neovim instance on the disposable temp root
-- created by test/min_init.lua — never the live Notes tree.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== tag engine + relative note (v1.8.0 Ph1) ==")

local pkm   = require('pkm')
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')
local index = require('pkm.index')
local tags  = require('pkm.tags')
local notes = require('pkm.notes')

--- Compare a tag list against an expected sequence, order included.
---@param got      string[]
---@param expected string[]
---@return boolean ok, string detail
local function same_list(got, expected)
  local g, e = table.concat(got, ','), table.concat(expected, ',')
  return g == e, string.format('got {%s}, expected {%s}', g, e)
end

-- =============================================================================
-- Pure core: tags.plan()
-- =============================================================================

do
  local out, changed = tags.plan({ 'alpha', 'beta' }, {})
  local ok, detail = same_list(out, { 'alpha', 'beta' })
  check("empty ops leaves the list untouched", ok and changed == false, detail)
end

do
  local out, changed = tags.plan({ 'alpha' }, { add = { 'beta' } })
  local ok, detail = same_list(out, { 'alpha', 'beta' })
  check("add appends at the end", ok and changed, detail)
end

do
  local out, changed = tags.plan({ 'alpha', 'beta' }, { remove = { 'alpha' } })
  local ok, detail = same_list(out, { 'beta' })
  check("remove drops the tag and keeps the order", ok and changed, detail)
end

do
  local out, changed = tags.plan({ 'alpha', 'beta' },
    { rename = { { from = 'alpha', to = 'gamma' } } })
  local ok, detail = same_list(out, { 'gamma', 'beta' })
  check("rename replaces in place", ok and changed, detail)
end

do
  -- Renaming onto a tag the note already has must merge, not duplicate.
  local out, changed = tags.plan({ 'draft', 'review' },
    { rename = { { from = 'draft', to = 'review' } } })
  local ok, detail = same_list(out, { 'review' })
  check("rename onto an existing tag merges into it", ok and changed, detail)
end

do
  local out, changed = tags.plan({ 'alpha' }, { add = { 'ALPHA' } })
  local ok, detail = same_list(out, { 'alpha' })
  check("adding a tag that differs only in case is a no-op",
    ok and changed == false, detail)
end

do
  -- The spelling already in the file is preserved; only new values are
  -- normalised. This is what keeps a batch from rewriting every note that
  -- happens to capitalise a tag.
  local out, changed = tags.plan({ 'Beta' }, { add = { 'Gamma' } })
  local ok, detail = same_list(out, { 'Beta', 'gamma' })
  check("existing spelling kept, new tag normalised", ok and changed, detail)
end

do
  local out, changed = tags.plan({ 'Alpha', 'beta' }, { remove = { 'ALPHA' } })
  local ok, detail = same_list(out, { 'beta' })
  check("remove matches case-insensitively", ok and changed, detail)
end

do
  local out, changed = tags.plan({ 'alpha' }, { remove = { 'nowhere' } })
  local ok, detail = same_list(out, { 'alpha' })
  check("removing an absent tag changes nothing", ok and changed == false, detail)
end

do
  -- Documented precedence: remove beats add for the same tag.
  local out, changed = tags.plan({ 'alpha' }, { add = { 'beta' }, remove = { 'beta' } })
  local ok, detail = same_list(out, { 'alpha' })
  check("remove beats add for the same tag", ok and changed == false, detail)
end

do
  -- Order of operations: rename, then remove, then add.
  local out, changed = tags.plan({ 'old', 'keep' }, {
    rename = { { from = 'old', to = 'new' } },
    remove = { 'keep' },
    add    = { 'extra' },
  })
  local ok, detail = same_list(out, { 'new', 'extra' })
  check("rename, then remove, then add", ok and changed, detail)
end

do
  local out = tags.plan({ 'dup', 'DUP', 'other' }, { add = { 'x' } })
  local ok, detail = same_list(out, { 'dup', 'other', 'x' })
  check("duplicates differing only in case collapse to the first", ok, detail)
end

do
  local out = tags.plan({ 'ok', 42, '', '  ', false }, {})
  local ok, detail = same_list(out, { 'ok' })
  check("non-string and blank entries are dropped", ok, detail)
end

do
  local out = tags.plan(nil, { add = { '  Spaced  ' } })
  local ok, detail = same_list(out, { 'spaced' })
  check("nil tag list and padded input are handled", ok, detail)
end

do
  local input = { 'alpha' }
  tags.plan(input, { add = { 'beta' }, remove = { 'alpha' } })
  local ok, detail = same_list(input, { 'alpha' })
  check("plan() does not mutate its input", ok, detail)
end

-- =============================================================================
-- Batch layer over a disposable corpus
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

--- Write a fixture note with the given tags.
---@param stem string
---@param note_tags string[]
---@return string path
local function write_note(stem, note_tags)
  local fm_lines = yaml.generate_yaml({
    title = 'Note ' .. stem,
    tags  = note_tags,
  })
  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })

  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

--- Current tags of a note, read back from disk.
---@param path string
---@return string[]
local function read_tags(path)
  local fm = yaml.parse_frontmatter(utils.read_lines(path) or {})
  return (fm and type(fm.tags) == 'table') and fm.tags or {}
end

local p_alpha = write_note('0201_note_alpha',      { 'alpha', 'shared' })
local p_beta  = write_note('0202_note_beta',       { 'beta', 'shared' })
local p_caps  = write_note('0203_note_capitalised', { 'Shared' })
local p_none  = write_note('0204_note_untagged',   {})

local p_bare = utils.join(notes_dir, '0205_note_no_frontmatter.md')
vim.fn.writefile({ 'no frontmatter at all' }, p_bare)

index.rebuild()

local corpus = { p_alpha, p_beta, p_caps, p_none, p_bare }

do
  -- Of the five: two already carry `shared`, one carries `Shared` (a match,
  -- case-insensitively), one has no frontmatter at all, and only the untagged
  -- note would actually change.
  local plan = tags.preview(corpus, { add = { 'shared' } })
  check("preview reports only the note that would change", #plan == 1,
    string.format('%d entries', #plan))

  local names = {}
  for _, item in ipairs(plan) do names[#names + 1] = vim.fn.fnamemodify(item.path, ':t:r') end
  check("and it is the untagged one — case-different and absent frontmatter skipped",
    table.concat(names, ',') == '0204_note_untagged', table.concat(names, ','))

  if plan[1] then
    local ok, detail = same_list(plan[1].after, { 'shared' })
    check("preview shows the resulting tag list", ok, detail)
    check("preview shows the previous tag list too", #plan[1].before == 0,
      table.concat(plan[1].before, ','))
  end
end

do
  -- preview() must not touch a single byte.
  local before = {}
  for _, p in ipairs(corpus) do before[p] = vim.fn.getftime(p) .. '|' .. vim.fn.getfsize(p) end
  tags.preview(corpus, { add = { 'brand-new' }, remove = { 'shared' } })
  local untouched = true
  local culprit
  for _, p in ipairs(corpus) do
    if before[p] ~= (vim.fn.getftime(p) .. '|' .. vim.fn.getfsize(p)) then
      untouched, culprit = false, p
    end
  end
  check("preview writes nothing", untouched, culprit)
end

do
  local applied, errors = tags.apply(corpus, { add = { 'batch' } })
  check("apply writes every note with frontmatter", applied == 4,
    string.format('applied=%d errors=%d', applied, errors))
  check("apply reports no errors", errors == 0)

  local ok = true
  for _, p in ipairs({ p_alpha, p_beta, p_caps, p_none }) do
    local found = false
    for _, t in ipairs(read_tags(p)) do if t == 'batch' then found = true end end
    if not found then ok = false end
  end
  check("the tag is on disk in each of them", ok)

  check("the note without frontmatter was skipped",
    #(utils.read_lines(p_bare) or {}) == 1)
end

do
  -- Applying the same operation twice must be a no-op the second time.
  local applied = tags.apply(corpus, { add = { 'batch' } })
  check("re-applying the same op changes nothing", applied == 0,
    string.format('applied=%d', applied))
end

do
  local before = read_tags(p_caps)
  local kept = false
  for _, t in ipairs(before) do if t == 'Shared' then kept = true end end
  check("a batch never rewrote the capitalised tag", kept,
    table.concat(before, ','))
end

do
  -- The index must reflect the change immediately: apply() writes to disk, so
  -- it is required to invalidate — unlike the buffer-only tag commands.
  local entry = index.get(p_none)
  local indexed = false
  for _, t in ipairs(entry and entry.tags or {}) do
    if t == 'batch' then indexed = true end
  end
  check("the index sees the applied tag without a rebuild", indexed)
end

do
  local applied = tags.apply(corpus, { rename = { { from = 'batch', to = 'renamed' } } })
  check("rename applies across the corpus", applied == 4,
    string.format('applied=%d', applied))

  local still = false
  for _, p in ipairs({ p_alpha, p_beta, p_caps, p_none }) do
    for _, t in ipairs(read_tags(p)) do if t == 'batch' then still = true end end
  end
  check("the old tag is gone everywhere", not still)
end

do
  -- merge_tags now delegates to the engine; its contract must hold.
  local m1 = write_note('0211_note_merge_a', { 'todo', 'keep' })
  local m2 = write_note('0212_note_merge_b', { 'pending', 'todo' })
  index.invalidate(m1)
  index.invalidate(m2)

  local modified = require('pkm.citations').merge_tags({ 'pending' }, 'todo')
  check("merge_tags reports the notes it changed", modified == 1,
    string.format('modified=%d', modified))

  local a, b = read_tags(m1), read_tags(m2)
  check("the untouched note kept its tags", table.concat(a, ',') == 'todo,keep',
    table.concat(a, ','))
  check("the merged note has no duplicate target", table.concat(b, ',') == 'todo',
    table.concat(b, ','))
end

-- =============================================================================
-- Relative note
-- =============================================================================

do
  -- create_relative_note reads the *buffer*, so unsaved tag edits count.
  vim.cmd('edit ' .. vim.fn.fnameescape(p_alpha))
  local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  check("fixture note opened with tags in the buffer",
    fm ~= nil and type(fm.tags) == 'table' and #fm.tags > 0)

  -- Drive create_new_note's prompts without a user: type is passed in, title
  -- comes from vim.fn.input, which is stubbed for the duration.
  local real_input = vim.fn.input
  vim.fn.input = function() return 'Relative Child' end            -- luacheck: ignore
  local created = notes.create_relative_note('note')
  vim.fn.input = real_input                                        -- luacheck: ignore

  check("a relative note was created", created ~= nil and vim.fn.filereadable(created) == 1,
    tostring(created))

  if created then
    local child = read_tags(created)
    local source = read_tags(p_alpha)
    local ok, detail = same_list(child, source)
    check("the new note inherited exactly the source tags", ok, detail)
  end
end

do
  vim.cmd('edit ' .. vim.fn.fnameescape(p_none))
  -- p_none carries the batch tags applied above; strip them in the buffer only,
  -- to exercise the untagged path without touching disk.
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local fm, cs = yaml.parse_frontmatter(lines)
  fm.tags = {}
  yaml.save_frontmatter(fm, cs)

  local real_input = vim.fn.input
  vim.fn.input = function() return 'Child Of Untagged' end         -- luacheck: ignore
  local created = notes.create_relative_note('note')
  vim.fn.input = real_input                                        -- luacheck: ignore

  check("an untagged source still creates a note", created ~= nil)
  if created then
    check("and that note has no tags", #read_tags(created) == 0,
      table.concat(read_tags(created), ','))
  end
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
