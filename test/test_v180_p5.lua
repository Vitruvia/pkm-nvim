-- test/test_v180_p5.lua
-- Tests for v1.8.0 Phase 5: naming a tag goes through the picker.
--
-- The ranking is pure and gets asserted directly; suggest_tags is read-only and
-- runs over a disposable corpus; the picker's "create what you typed" path is
-- exercised through the no-Telescope fallback, which is the one available in
-- headless.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p5.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== tag entry through the picker (v1.8.0 Ph5) ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local yaml   = require('pkm.yaml')
local index  = require('pkm.index')
local tags   = require('pkm.tags')
local picker = require('pkm.picker')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

---@param stem string
---@param note_tags string[]
---@return string path
local function write_note(stem, note_tags)
  local fm_lines = yaml.generate_yaml({ title = 'Note ' .. stem, tags = note_tags })
  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

---@param rows table[]
---@return string[]
local function tag_order(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.tag end
  return out
end

---@param rows table[]
---@param tag  string
---@return table|nil
local function row_for(rows, tag)
  for _, row in ipairs(rows) do
    if row.tag == tag then return row end
  end
  return nil
end

-- =============================================================================
-- rank_tags(): pure, and the whole reason the list is ordered the way it is
-- =============================================================================

do
  local rows = {
    { tag = 'alpha', count = 1,  paths = {} },
    { tag = 'beta',  count = 50, paths = {} },
    { tag = 'gamma', count = 3,  paths = {} },
    { tag = 'delta', count = 2,  paths = {} },
  }

  local ranked = tags.rank_tags(rows, {
    selected_count = 4,
    on_selected    = { alpha = 2, delta = 4 },
    cooccurrence   = { gamma = 7 },
  })

  check("a tag on some of the selection comes first",
    ranked[1].tag == 'alpha', table.concat(tag_order(ranked), ', '))
  check("then a co-occurring tag",
    ranked[2].tag == 'gamma', table.concat(tag_order(ranked), ', '))
  check("then the unrelated ones, most used first",
    ranked[3].tag == 'beta', table.concat(tag_order(ranked), ', '))
  check("and a tag already on every selected note goes last",
    ranked[4].tag == 'delta', table.concat(tag_order(ranked), ', '))

  check("partial coverage is spelled out",
    ranked[1].note == 'on 2 of 4 selected', tostring(ranked[1].note))
  check("co-occurrence is spelled out",
    ranked[2].note == 'co-occurs on 7 notes', tostring(ranked[2].note))
  check("an unrelated tag needs no explanation", ranked[3].note == nil)
  check("full coverage warns that nothing would change",
    ranked[4].note == 'already on all selected', tostring(ranked[4].note))

  check("the input rows are not reordered", rows[1].tag == 'alpha' and rows[2].tag == 'beta')
  check("and are not annotated", rows[1].note == nil)
end

do
  local rows   = { { tag = 'b', count = 5, paths = {} }, { tag = 'a', count = 5, paths = {} } }
  local ranked = tags.rank_tags(rows, {})
  check("with no context at all, usage decides, ties broken by name",
    ranked[1].tag == 'a' and ranked[2].tag == 'b', table.concat(tag_order(ranked), ', '))
end

-- =============================================================================
-- suggest_tags(): the same ranking, over a real corpus
-- =============================================================================

local p1 = write_note('0601_note_one',   { 'physics', 'draft' })
local p2 = write_note('0602_note_two',   { 'physics' })
local p4 = write_note('0604_note_four',  { 'cooking' })
-- Outside the selection used below, so 'quantum' can only surface through
-- co-occurrence with 'physics'.
write_note('0603_note_three', { 'physics', 'quantum' })
index.rebuild()

do
  local rows = tags.suggest_tags({ p1, p2 })

  local draft = row_for(rows, 'draft')
  check("a tag on part of the selection is ranked first",
    rows[1].tag == 'draft' and draft.note == 'on 1 of 2 selected',
    rows[1].tag .. ' / ' .. tostring(draft and draft.note))

  local quantum = row_for(rows, 'quantum')
  check("a tag that keeps company with the selection's tags is suggested",
    quantum ~= nil and quantum.note ~= nil and quantum.note:find('co-occurs', 1, true),
    quantum and tostring(quantum.note) or 'missing')

  local cooking = row_for(rows, 'cooking')
  check("an unrelated tag is offered without a reason",
    cooking ~= nil and cooking.note == nil, cooking and tostring(cooking.note) or 'missing')

  local physics = row_for(rows, 'physics')
  check("the tag the whole selection already has goes last",
    rows[#rows].tag == 'physics' and physics.note == 'already on all selected',
    rows[#rows].tag)

  check("every vault tag is offered", #rows == 4, '#' .. #rows)
end

do
  local rows = tags.suggest_tags({ p4 })
  check("a selection sharing nothing gets no co-occurrence noise", (function()
    for _, row in ipairs(rows) do
      if row.note and row.note:find('co-occurs', 1, true) then return false end
    end
    return true
  end)())

  check("with no selection at all, it is just the tag list, most used first",
    tags.suggest_tags(nil)[1].tag == 'physics', tags.suggest_tags(nil)[1].tag)
end

-- =============================================================================
-- select_tag(allow_new): naming a tag that does not exist yet
-- =============================================================================

do
  local orig_select, orig_input = vim.ui.select, vim.ui.input
  local offered, chosen

  -- The fallback puts the "new tag" entry first; taking it opens an input.
  vim.ui.select = function(items, opts, on_choice)
    offered = opts.format_item(items[1])
    on_choice(items[1], 1)
  end
  vim.ui.input = function(_, on_input) on_input('  Recém-Criada  ') end

  picker.select_tag(tags.tag_counts(), { title = 'Tag to add', allow_new = true },
    function(tag) chosen = tag end)
  vim.wait(1000, function() return chosen ~= nil end, 10)

  check("the fallback offers to create a tag", offered == '+ new tag…', tostring(offered))
  check("and what is typed comes back normalised",
    chosen == 'recém-criada', tostring(chosen))

  -- Without allow_new the entry is absent, and the first row is a real tag.
  chosen = nil
  picker.select_tag(tags.tag_counts(), { title = 'Tag to remove' },
    function(tag) chosen = tag end)
  vim.wait(1000, function() return chosen ~= nil end, 10)
  check("without it, the first entry is an existing tag",
    chosen == 'cooking', tostring(chosen))
  check("and its label carries the count",
    offered:find('(1 note)', 1, true) ~= nil, offered)

  -- An empty vault plus allow_new goes straight to free text.
  chosen = nil
  local selected_ran = false
  vim.ui.select = function() selected_ran = true end
  picker.select_tag({}, { title = 'Tag to add', allow_new = true },
    function(tag) chosen = tag end)
  vim.wait(1000, function() return chosen ~= nil end, 10)
  check("with no tags at all, it asks for one directly",
    selected_ran == false and chosen == 'recém-criada', tostring(chosen))

  vim.ui.select, vim.ui.input = orig_select, orig_input
end

do
  local orig = vim.ui.select
  local ran  = false
  vim.ui.select = function() ran = true end
  picker.select_tag({}, { title = 'Tag to remove' }, function() end)
  vim.ui.select = orig
  check("an empty list without allow_new still opens nothing", ran == false)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
