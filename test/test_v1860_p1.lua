-- test/test_v1860_p1.lua
-- Tests for v1.86.0 (ferramentas-concursos queue, 21/10/2026):
--   P1  note lists put journal entries newest first (`utils.note_before`);
--   P2  the per-note tag panels stay open for repeated use (`keep_open`);
--   P3  tag suggestions rank companions by association (`affinity`), so a
--       broad tag on the note no longer drowns a narrow tag's companions.
-- The Telescope screens are not reachable headless; the flows run through the
-- no-Telescope fallback (vim.ui.select / vim.ui.input stubbed).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1860_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== v1.86.0 P1-P3 ==")

local pkm    = require('pkm')
local utils  = require('pkm.utils')
local yaml   = require('pkm.yaml')
local index  = require('pkm.index')
local tags   = require('pkm.tags')
local picker = require('pkm.picker')

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

local function write_note(stem, note_tags)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml({ title = 'Note ' .. stem, tags = note_tags }))
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

local function order(list, field)
  local out = {}
  for _, x in ipairs(list) do out[#out + 1] = x[field] end
  return table.concat(out, ',')
end

-- =============================================================================
-- P1 — utils.note_before: type order, then title; journals newest first
-- =============================================================================

do
  local list = {
    { note_type = 'journal', title = 'Journal A', filename = 'journal_2026-01-05_08-00-00' },
    { note_type = 'note',    title = 'beta',      filename = '0002_note_beta' },
    { note_type = 'journal', title = 'Journal Z', filename = 'journal_2026-10-21_09-30-00' },
    { note_type = 'journal', title = 'Journal M', filename = 'journal_2026-10-21' },
    { note_type = 'note',    title = 'Alpha',     filename = '0001_note_alpha' },
    { note_type = 'journal', title = 'Journal B', filename = 'journal_2025-12-31_23-59-59' },
  }
  table.sort(list, utils.note_before)
  check("notes first, by title; then journals, newest first",
    order(list, 'filename') == table.concat({
      '0001_note_alpha', '0002_note_beta',
      'journal_2026-10-21_09-30-00', 'journal_2026-10-21',
      'journal_2026-01-05_08-00-00', 'journal_2025-12-31_23-59-59' }, ','),
    order(list, 'filename'))
  check("strict order (an entry is not before itself)",
    not utils.note_before(list[3], list[3]))
end

do
  -- The fallback browser (ui.browse_paths) sorts with the same comparator.
  local jdir = utils.join(pkm.config.root_path, pkm.config.folders.journal)
  vim.fn.mkdir(jdir, 'p')
  local paths = {}
  for _, stamp in ipairs({ '2026-03-01_10-00-00', '2026-10-20_10-00-00', '2026-07-15_10-00-00' }) do
    local p = utils.join(jdir, 'journal_' .. stamp .. '.md')
    vim.fn.writefile({ '---', 'title: Journal ' .. stamp, '---', '', 'x' }, p)
    paths[#paths + 1] = p
  end
  index.rebuild()
  local shown
  local orig = vim.ui.select
  vim.ui.select = function(items) shown = items end
  require('pkm.ui').browse_paths('Journals', paths)
  vim.ui.select = orig
  local stems = {}
  for _, e in ipairs(shown or {}) do stems[#stems + 1] = e.filename end
  check("the browse list shows journal entries newest first",
    table.concat(stems, ',') == 'journal_2026-10-20_10-00-00,journal_2026-07-15_10-00-00,'
      .. 'journal_2026-03-01_10-00-00', table.concat(stems, ','))
end

-- =============================================================================
-- P3 — affinity: a broad tag on the note does not drown narrow companions
-- =============================================================================

-- 'broad' is on 12 notes; 'niche' on 3. 'companion' rides with 'niche' on 2 of
-- its 3 notes; 'noise' rides with 'broad' on 3 of its 12 (more raw co-occurrence
-- than 'companion', weaker association).
write_note('0801_note_n1', { 'niche', 'companion' })
write_note('0802_note_n2', { 'niche', 'companion' })
write_note('0803_note_n3', { 'niche' })
for i = 1, 12 do
  write_note(string.format('08%02d_note_b%d', 10 + i, i), i <= 3 and { 'broad', 'noise' } or { 'broad' })
end
index.rebuild()

do
  local rows = tags.suggest_tags_for({ 'niche', 'broad' })
  local pos = {}
  for i, r in ipairs(rows) do pos[r.tag] = i end
  check("a narrow tag's companion outranks a broad tag's more frequent one",
    pos.companion and pos.noise and pos.companion < pos.noise, order(rows, 'tag'))
  local comp
  for _, r in ipairs(rows) do if r.tag == 'companion' then comp = r end end
  check("the row still says how many notes it co-occurs on",
    comp and comp.note == 'co-occurs on 2 notes', comp and comp.note)
  check("rank_tags without affinity keeps the raw count (pure callers unchanged)",
    tags.rank_tags({ { tag = 'a', count = 1, paths = {} }, { tag = 'b', count = 1, paths = {} } },
      { selected_count = 1, on_selected = {}, cooccurrence = { a = 1, b = 3 } })[1].tag == 'b')
end

-- =============================================================================
-- P2 — keep_open: the panel re-lists after each pick, <Esc> ends it
-- =============================================================================

do
  local calls, chosen, closed = 0, {}, false
  local orig = vim.ui.select
  vim.ui.select = function(items, _, on_choice)
    calls = calls + 1
    if calls <= 2 then on_choice(items[calls], calls) else on_choice(nil) end
  end
  local n = 0
  picker.select_tag({ { tag = 'x', count = 1, paths = {} }, { tag = 'y', count = 1, paths = {} } }, {
    title = 'T', keep_open = true,
    refresh = function() n = n + 1; return { { tag = 'y', count = 1, paths = {} },
                                             { tag = 'x', count = 1, paths = {} } } end,
    on_close = function() closed = true end,
  }, function(tag) chosen[#chosen + 1] = tag end)
  vim.wait(1000, function() return closed end, 10)
  vim.ui.select = orig
  check("keep_open: two picks land, each followed by a re-list",
    table.concat(chosen, ',') == 'x,x' and n == 2 and calls == 3,
    table.concat(chosen, ',') .. ' refresh=' .. n .. ' calls=' .. calls)
  check("keep_open: cancelling ends the panel and runs on_close", closed)
end

do
  local calls, chosen = 0, {}
  local orig = vim.ui.select
  vim.ui.select = function(items, _, on_choice)
    calls = calls + 1
    on_choice(items[1], 1)
  end
  picker.select_tag({ { tag = 'x', count = 1, paths = {} } }, { title = 'T' },
    function(tag) chosen[#chosen + 1] = tag end)
  vim.wait(200, function() return #chosen > 0 end, 10)
  vim.wait(50)
  vim.ui.select = orig
  check("without keep_open the panel still closes after one pick (one-shot)",
    calls == 1 and #chosen == 1, 'calls=' .. calls)
end

do
  -- <leader>ta / :PKMTag add: add two tags in one session, then <Esc>.
  local target = write_note('0890_note_target', { 'niche' })
  index.rebuild()
  vim.cmd('edit ' .. vim.fn.fnameescape(target))
  local note_buf, note_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local function buf_tags()
    local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(note_buf, 0, -1, false))
    local out = {}
    for _, t in ipairs((fm and fm.tags) or {}) do out[#out + 1] = tostring(t) end
    return table.concat(out, ',')
  end

  local lists, orig = {}, vim.ui.select
  vim.ui.select = function(items, _, on_choice)
    lists[#lists + 1] = items
    if #lists == 1 then vim.cmd('new') end      -- a panel takes focus
    if #lists <= 2 then on_choice(items[2], 2) else on_choice(nil) end  -- [1] is "+ new tag…"
  end
  vim.cmd('PKMTag add')
  vim.wait(1000, function() return #lists >= 3 and vim.api.nvim_get_current_win() == note_win end, 10)
  vim.ui.select = orig

  check("add stays open: two tags added in one session",
    buf_tags() == 'niche,companion,broad', buf_tags())
  check("the second list is re-ranked for the note as it now stands",
    lists[2] and lists[2][2] and lists[2][2].tag ~= 'companion'
      and lists[2][#lists[2]].note == 'already on this note',
    lists[2] and order(vim.list_slice(lists[2], 2), 'tag'))
  check("<Esc> returns focus to the note's window", vim.api.nvim_get_current_win() == note_win)
  check("writes stay buffer-only", vim.bo[note_buf].modified)
  vim.cmd('only')

  -- Remove: picks until no tag is left, then the panel ends by itself.
  local rcalls = 0
  vim.ui.select = function(items, _, on_choice)
    rcalls = rcalls + 1
    on_choice(items[1], 1)
  end
  vim.cmd('PKMTag remove')
  vim.wait(1000, function() return buf_tags() == '' end, 10)
  vim.wait(50)
  vim.ui.select = orig
  check("remove stays open and ends by itself once no tag is left",
    buf_tags() == '' and rcalls == 3, 'tags=' .. buf_tags() .. ' calls=' .. rcalls)
  vim.cmd('bwipeout! ' .. note_buf)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
