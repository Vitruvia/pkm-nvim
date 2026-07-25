-- test/test_v180_p7.lua
-- Tests for v1.8.0 Phase 7: the pattern engine and bulk title change.
--
-- The engine is pure and gets asserted directly, with weight on the names that
-- would misfire if patterns were passed to Lua unescaped — real note titles
-- carry '-', '(', '.' and '%'. Then the writing layer over a disposable corpus,
-- including the case the batched propagation exists for: one note citing two of
-- the renamed ones must be read and written once, with both titles updated.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p7.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== pattern engine + bulk titles (v1.8.0 Ph7) ==")

local pkm       = require('pkm')
local utils     = require('pkm.utils')
local yaml      = require('pkm.yaml')
local index     = require('pkm.index')
local rename    = require('pkm.rename')
local citations = require('pkm.citations')

---@param before string
---@param pattern table
---@return table  the single planned row
local function plan_one(before, pattern)
  return rename.plan_names({ { key = 'k', before = before } }, pattern)[1]
end

-- =============================================================================
-- plan_names(): the four literal operations
-- =============================================================================

do
  local row = plan_one('Kant', { op = 'prefix', text = '[wip] ' })
  check("prefix prepends", row.after == '[wip] Kant' and row.changed, row.after)

  row = plan_one('Kant', { op = 'suffix', text = ' (rascunho)' })
  check("suffix appends", row.after == 'Kant (rascunho)' and row.changed, row.after)

  row = plan_one('[wip] Kant', { op = 'remove', text = '[wip]' })
  check("remove drops the text and trims what it leaves behind",
    row.after == 'Kant' and row.changed, '"' .. row.after .. '"')

  row = plan_one('Draft — Kant', { op = 'replace', from = 'Draft', to = 'Notas' })
  check("replace swaps the text", row.after == 'Notas — Kant' and row.changed, row.after)
end

-- =============================================================================
-- The literal guarantee: names that are also Lua patterns
-- =============================================================================

do
  local row = plan_one('Notas (v2) sobre Kant', { op = 'remove', text = '(v2)' })
  check("parentheses are literal, not a capture group",
    row.after == 'Notas sobre Kant', '"' .. row.after .. '"')

  row = plan_one('Aula 03 - Kant', { op = 'replace', from = ' - ', to = ': ' })
  check("a hyphen is literal, not a quantifier",
    row.after == 'Aula 03: Kant', row.after)

  row = plan_one('100% teoria', { op = 'replace', from = '100%', to = 'toda a' })
  check("a percent sign on the left is literal",
    row.after == 'toda a teoria', row.after)

  row = plan_one('Kant', { op = 'replace', from = 'Kant', to = '100% Kant' })
  check("a percent sign on the right is not a capture reference",
    row.after == '100% Kant', row.after)

  row = plan_one('arquivo.md sobre Kant', { op = 'remove', text = 'o.md' })
  check("a dot matches only a dot",
    row.after == 'arquiv sobre Kant', '"' .. row.after .. '"')

  row = plan_one('Kant e Hume', { op = 'replace', from = '.', to = '!' })
  check("a lone dot replaces nothing when there is no literal dot",
    row.after == 'Kant e Hume' and not row.changed, row.after)
end

-- =============================================================================
-- capture: the one mode that honours a Lua pattern
-- =============================================================================

do
  local row = plan_one('Aula 03 - Kant',
    { op = 'capture', from = 'Aula (%d+) %- (.+)', to = '%2 (aula %1)' })
  check("capture rebuilds from its groups",
    row.after == 'Kant (aula 03)' and row.changed, row.after)

  row = plan_one('Kant', { op = 'capture', from = '[a-', to = 'x' })
  check("a malformed pattern is reported, not raised",
    row.error == 'invalid pattern' and not row.changed, tostring(row.error))
  check("and the name is left alone", row.after == 'Kant', row.after)

  row = plan_one('Kant', { op = 'capture', from = '(K)ant', to = '%2' })
  check("a replacement referring to a group that is not there is reported too",
    row.error == 'invalid pattern', tostring(row.error))
end

-- =============================================================================
-- Refusals and non-changes
-- =============================================================================

do
  local row = plan_one('Kant', { op = 'remove', text = 'Hume' })
  check("a pattern that matches nothing is not an error",
    not row.changed and row.error == nil, tostring(row.error))

  row = plan_one('[wip]', { op = 'remove', text = '[wip]' })
  check("emptying the title is refused",
    row.error == 'would leave it empty' and not row.changed, tostring(row.error))

  row = plan_one('Kant', { op = 'prefix', text = '' })
  check("an empty operand is refused", row.error == 'no text given', tostring(row.error))

  row = plan_one('Kant', { op = 'nonsense' })
  check("an unknown operation is refused",
    row.error == 'unknown operation', tostring(row.error))

  row = plan_one('Kant', { op = 'suffix', text = '' })
  check("and the name survives every refusal untouched", row.after == 'Kant')
end

do
  local items = { { key = 'a', before = 'Kant' }, { key = 'b', before = 'Hume' } }
  local plan  = rename.plan_names(items, { op = 'prefix', text = 'X ' })

  check("every item is planned", #plan == 2 and plan[2].after == 'X Hume', plan[2].after)
  check("the input is not mutated",
    items[1].before == 'Kant' and items[1].after == nil)
  check("keys are carried through", plan[1].key == 'a' and plan[2].key == 'b')
end

-- =============================================================================
-- describe() and format_change(): the wording shown before a write
-- =============================================================================

do
  check("describe names a prefix",
    rename.describe({ op = 'prefix', text = 'X ' }) == "Prefix with 'X '",
    rename.describe({ op = 'prefix', text = 'X ' }))
  check("describe names a replacement",
    rename.describe({ op = 'replace', from = 'a', to = 'b' }) == "Replace 'a' with 'b'",
    rename.describe({ op = 'replace', from = 'a', to = 'b' }))

  local line = rename.format_change(
    { key = '/x/0042_note_Kant.md', before = 'Kant', after = 'X Kant' })
  check("a row shows the stem and before → after",
    line:find('0042_note_Kant', 1, true) and line:find('Kant  →  X Kant', 1, true) ~= nil,
    line)

  local bad = rename.format_change(
    { key = '/x/0042_note_Kant.md', before = 'Kant', after = 'Kant',
      error = 'would leave it empty' })
  check("and an errored row says why instead",
    bad:find('✗  would leave it empty', 1, true) ~= nil, bad)
end

-- =============================================================================
-- apply_titles(): writes, index, and one propagation pass
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(notes_dir, 'p')

---@param stem string
---@param fm table
---@return string path
local function write_note(stem, fm)
  local fm_lines = yaml.generate_yaml(fm)
  local lines = { '---' }
  vim.list_extend(lines, fm_lines)
  vim.list_extend(lines, { '---', '', 'Body of ' .. stem })
  local path = utils.join(notes_dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

-- Two notes to retitle, and one citing BOTH of them — the case the batched
-- propagation exists for.
local p1 = write_note('0801_note_Kant', { title = 'Kant', tags = {} })
local p2 = write_note('0802_note_Hume', { title = 'Hume', tags = {} })
local citing = write_note('0803_note_Citante', {
  title = 'Citante',
  tags  = {},
  cites = {
    notes = {
      { identifier = 'note-0801', title = 'Kant', link = '[[0801_note_Kant]]' },
      { identifier = 'note-0802', title = 'Hume', link = '[[0802_note_Hume]]' },
    },
  },
})
index.rebuild()

do
  local items = rename.title_items({ p1, p2 })
  check("titles are read from the files", #items == 2 and items[1].before == 'Kant',
    items[1] and items[1].before or 'none')

  local plan = rename.plan_names(items, { op = 'prefix', text = 'Sobre ' })
  local applied, errors = rename.apply_titles(plan)
  check("both notes were written", applied == 2 and errors == 0,
    string.format('%d applied, %d errors', applied, errors))

  local _, title = rename.read_title(p1)
  check("the new title is on disk", title == 'Sobre Kant', title)

  local entry = index.get(p2)
  check("and the index saw it without a rebuild",
    entry and entry.title == 'Sobre Hume', entry and entry.title or 'no entry')
end

do
  -- The citing note must carry BOTH new titles after a single pass.
  local fm = yaml.parse_frontmatter(vim.fn.readfile(citing))
  local by_id = {}
  for _, e in ipairs(fm.cites.notes) do by_id[e.identifier] = e end

  check("the citing note's first entry was updated",
    by_id['note-0801'].title == 'Sobre Kant', by_id['note-0801'].title)
  check("and so was its second, in the same pass",
    by_id['note-0802'].title == 'Sobre Hume', by_id['note-0802'].title)
  check("the link field is untouched — it holds the filename, not the title",
    by_id['note-0801'].link == '[[0801_note_Kant]]', by_id['note-0801'].link)
end

do
  -- Re-propagating the same titles changes nothing: the pass is idempotent.
  check("propagating unchanged titles rewrites no file",
    citations.propagate_titles({ ['note-0801'] = 'Sobre Kant' }) == 0)

  check("an empty batch is a no-op", citations.propagate_titles({}) == 0)
  check("a nil batch is a no-op", citations.propagate_titles(nil) == 0)
end

do
  -- Entries that would not change, or that errored, are never written.
  local items = rename.title_items({ p1 })
  local plan  = rename.plan_names(items, { op = 'remove', text = 'inexistente' })
  local applied = rename.apply_titles(plan)
  check("an unchanged plan writes nothing", applied == 0, tostring(applied))

  local _, title = rename.read_title(p1)
  check("and the title is intact", title == 'Sobre Kant', title)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
