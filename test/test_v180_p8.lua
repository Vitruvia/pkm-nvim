-- test/test_v180_p8.lua
-- Tests for v1.8.0 Phase 8: bulk file rename.
--
-- The widest write in the plugin: renaming rewrites [[links]] and identifiers in
-- every citing note. Everything here that can be exercised headlessly is —
-- the stem split, the skip list, collision refusal, the rename mechanics
-- (including a file open in a buffer), and a real batch whose citing note is
-- rewritten once for two renames. Only the Telescope panel is smoke-only.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v180_p8.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

print("== bulk file rename (v1.8.0 Ph8) ==")

local pkm       = require('pkm')
local utils     = require('pkm.utils')
local yaml      = require('pkm.yaml')
local index     = require('pkm.index')
local rename    = require('pkm.rename')
local notes     = require('pkm.notes')
local citations = require('pkm.citations')

-- =============================================================================
-- split_stem / stem_items: what may be renamed, and what may not
-- =============================================================================

do
  local prefix, name = rename.split_stem('0042_note_Kant_On_Duty')
  check("a consolidated stem splits into prefix and name",
    prefix == '0042_note_' and name == 'Kant_On_Duty',
    tostring(prefix) .. ' | ' .. tostring(name))

  check("a journal stem does not split",
    rename.split_stem('journal_2026-07-25_10-30') == nil)
  check("a scratch stem does not split",
    rename.split_stem('scratch_2026-07-25') == nil)
  check("an unnumbered name does not split", rename.split_stem('README') == nil)

  local _, bib = rename.split_stem('0005_bib_Seneca')
  check("bib notes split like any other consolidated note", bib == 'Seneca', tostring(bib))
end

-- =============================================================================
-- planned_stem / find_collisions
-- =============================================================================

do
  check("the prefix is rebuilt around the new name",
    rename.planned_stem({ prefix = '0042_note_', after = 'Kant On Duty' })
      == '0042_note_Kant_On_Duty',
    rename.planned_stem({ prefix = '0042_note_', after = 'Kant On Duty' }))

  check("characters a filesystem refuses are dropped",
    rename.planned_stem({ prefix = '0001_note_', after = 'A/B:C?D' }) == '0001_note_ABCD',
    rename.planned_stem({ prefix = '0001_note_', after = 'A/B:C?D' }))

  local plan = {
    { key = 'a.md', prefix = '0001_note_', after = 'Mesmo', changed = true },
    { key = 'b.md', prefix = '0002_note_', after = 'Outro', changed = true },
  }
  check("different numbers cannot collide, even with the same name",
    #rename.find_collisions(plan, rename.planned_stem) == 0)

  plan = {
    { key = 'a.md', prefix = '0001_note_', after = 'Mesmo', changed = true },
    { key = 'b.md', prefix = '0001_note_', after = 'Mesmo', changed = true },
  }
  local collisions = rename.find_collisions(plan, rename.planned_stem)
  check("two rows producing one name is a collision",
    #collisions == 1 and collisions[1].stem == '0001_note_Mesmo',
    tostring(#collisions))

  plan = {
    { key = 'a.md', prefix = '0001_note_', after = 'X', error = 'invalid pattern' },
    { key = 'b.md', prefix = '0001_note_', after = 'X', changed = true },
  }
  check("an errored row cannot collide with anything",
    #rename.find_collisions(plan, rename.planned_stem) == 0)
end

-- =============================================================================
-- The corpus
-- =============================================================================

local notes_dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
local journal_dir = utils.join(pkm.config.root_path, pkm.config.folders.journal)
vim.fn.mkdir(notes_dir, 'p')
vim.fn.mkdir(journal_dir, 'p')

---@param dir string
---@param stem string
---@param fm table
---@param body string[]|nil
---@return string path
local function write_note(dir, stem, fm, body)
  local lines = { '---' }
  vim.list_extend(lines, yaml.generate_yaml(fm))
  vim.list_extend(lines, { '---', '' })
  vim.list_extend(lines, body or { 'corpo' })
  local path = utils.join(dir, stem .. '.md')
  vim.fn.writefile(lines, path)
  return path
end

local p1 = write_note(notes_dir, '1001_note_Rascunho_Kant', { title = 'Kant', tags = {} })
local p2 = write_note(notes_dir, '1002_note_Rascunho_Hume', { title = 'Hume', tags = {} })
local jr = write_note(journal_dir, 'journal_2026-07-25_09-00', { title = 'Diário', tags = {} })

-- One note citing BOTH, in frontmatter and in its body.
local citing = write_note(notes_dir, '1003_note_Citante', {
  title = 'Citante',
  tags  = {},
  cites = {
    notes = {
      { identifier = 'note-1001', title = 'Kant', link = '[[1001_note_Rascunho_Kant]]' },
      { identifier = 'note-1002', title = 'Hume', link = '[[1002_note_Rascunho_Hume]]' },
    },
  },
}, { 'Ver [[1001_note_Rascunho_Kant]] e também [[1002_note_Rascunho_Hume]].' })
index.rebuild()

do
  local items, skipped = rename.stem_items({ p1, p2, jr })
  check("only consolidated notes are renameable", #items == 2, tostring(#items))
  check("the journal is skipped, with a reason",
    #skipped == 1 and skipped[1].reason:find('timestamp', 1, true) ~= nil,
    skipped[1] and skipped[1].reason or 'none')
  check("the editable part excludes the prefix",
    items[1].before == 'Rascunho_Kant' and items[1].prefix == '1001_note_',
    items[1].before)
end

-- =============================================================================
-- rename_file: the mechanics, including an open buffer
-- =============================================================================

do
  local solo = write_note(notes_dir, '1010_note_Solo', { title = 'Solo', tags = {} })
  vim.cmd('edit ' .. vim.fn.fnameescape(solo))
  local bufnr = vim.api.nvim_get_current_buf()

  local ok, new_path = notes.rename_file(solo, '1010_note_Renomeada')
  check("the rename reports success", ok and new_path ~= nil, tostring(new_path))
  check("the new file exists", vim.fn.filereadable(new_path) == 1)
  check("the old one is gone", vim.fn.filereadable(solo) == 0)
  check("the open buffer followed the file",
    vim.api.nvim_buf_get_name(bufnr):find('1010_note_Renomeada', 1, true) ~= nil,
    vim.api.nvim_buf_get_name(bufnr))
  check("and is not left dirty", vim.bo[bufnr].modified == false)
  check("the index dropped the old path and knows the new one",
    index.get(solo) == nil and index.get(new_path) ~= nil)

  local again, _, err = notes.rename_file(new_path, '1010_note_Renomeada')
  check("renaming to the same name is a no-op, not an error", again and err == nil)

  vim.cmd('silent! bwipeout!')
  vim.fn.delete(new_path)
  index.invalidate(new_path)
end

do
  local a = write_note(notes_dir, '1020_note_A', { title = 'A', tags = {} })
  local b = write_note(notes_dir, '1021_note_B', { title = 'B', tags = {} })

  local ok, _, err = notes.rename_file(a, '1021_note_B')
  check("renaming onto an existing file is refused",
    ok == false and err ~= nil and err:find('already exists', 1, true) ~= nil,
    tostring(err))
  check("and neither file was touched",
    vim.fn.filereadable(a) == 1 and vim.fn.filereadable(b) == 1)

  vim.fn.delete(a); vim.fn.delete(b)
  index.invalidate(a); index.invalidate(b)
end

-- =============================================================================
-- apply_filenames: the batch, and the citing note rewritten once
-- =============================================================================

do
  local items = rename.stem_items({ p1, p2 })
  local plan  = rename.plan_names(items, rename.parse_substitution('^Rascunho_/'))

  check("the substitution sees only the editable part",
    plan[1].after == 'Kant' and plan[1].changed, plan[1].after)

  local applied, errors, refusal = rename.apply_filenames(plan)
  check("both files were renamed",
    applied == 2 and errors == 0 and refusal == nil,
    string.format('%d applied, %d errors, %s', applied, errors, tostring(refusal)))

  check("the new files exist",
    vim.fn.filereadable(utils.join(notes_dir, '1001_note_Kant.md')) == 1
    and vim.fn.filereadable(utils.join(notes_dir, '1002_note_Hume.md')) == 1)
  check("the old ones are gone",
    vim.fn.filereadable(p1) == 0 and vim.fn.filereadable(p2) == 0)
end

do
  local content = table.concat(vim.fn.readfile(citing), '\n')

  check("the citing note's body links were rewritten",
    content:find('[[1001_note_Kant]]', 1, true) ~= nil
    and content:find('[[1002_note_Hume]]', 1, true) ~= nil, content)
  check("and no old link survives",
    content:find('Rascunho_Kant', 1, true) == nil
    and content:find('Rascunho_Hume', 1, true) == nil, content)

  local fm = yaml.parse_frontmatter(vim.fn.readfile(citing))
  local by_id = {}
  for _, e in ipairs(fm.cites.notes) do by_id[e.identifier] = e end
  check("both frontmatter links were rewritten in the same pass",
    by_id['note-1001'].link == '[[1001_note_Kant]]'
    and by_id['note-1002'].link == '[[1002_note_Hume]]',
    by_id['note-1001'].link .. ' / ' .. by_id['note-1002'].link)
  check("the identifiers are unchanged — the number did not move",
    by_id['note-1001'] ~= nil and by_id['note-1002'] ~= nil)
end

do
  -- A batch that would produce one name twice is refused whole.
  local a = write_note(notes_dir, '1030_note_Alfa_X', { title = 'A', tags = {} })
  local b = write_note(notes_dir, '1030_note_Beta_X', { title = 'B', tags = {} })
  index.rebuild()

  local items = rename.stem_items({ a, b })
  local plan  = rename.plan_names(items, rename.parse_substitution('^\\(Alfa\\|Beta\\)_/Mesmo_'))

  local applied, _, refusal = rename.apply_filenames(plan)
  check("a colliding batch is refused", applied == 0 and refusal ~= nil, tostring(refusal))
  check("and nothing was renamed",
    vim.fn.filereadable(a) == 1 and vim.fn.filereadable(b) == 1)

  vim.fn.delete(a); vim.fn.delete(b)
end

do
  -- Deletion still works through the shared pass.
  local victim = write_note(notes_dir, '1040_note_Vitima', { title = 'V', tags = {} })
  local citer  = write_note(notes_dir, '1041_note_Citer', { title = 'C', tags = {} },
    { 'Ver [[1040_note_Vitima]].' })
  index.rebuild()

  citations.update_references_on_rename('1040_note_Vitima', '__DELETED__', nil)
  local content = table.concat(vim.fn.readfile(citer), '\n')
  check("a deleted note's links are struck through, not rewritten",
    content:find('~~1040_note_Vitima~~ (deleted)', 1, true) ~= nil, content)

  vim.fn.delete(victim); vim.fn.delete(citer)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
