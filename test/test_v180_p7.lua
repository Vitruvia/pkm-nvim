-- test/test_v180_p7.lua
-- Tests for v1.8.0 Phase 7: substitution over titles, in one live panel.
--
-- The expression parser and the planner are exercised directly; the planner
-- calls Neovim's own regex engine (vim.fn.match / vim.fn.substitute), which is
-- available headlessly, so the semantics that matter — the same ones :%s has —
-- are asserted for real. The writing layer runs over a disposable corpus,
-- including the case the batched propagation exists for: one note citing two of
-- the retitled ones.
--
-- The live panel itself is Telescope, hence smoke-only; what it depends on
-- (compute → rows) is the pure part tested here.
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

print("== title substitution (v1.8.0 Ph7) ==")

local pkm       = require('pkm')
local utils     = require('pkm.utils')
local yaml      = require('pkm.yaml')
local index     = require('pkm.index')
local rename    = require('pkm.rename')
local citations = require('pkm.citations')

---@param before string
---@param input  string
---@return table  the single planned row
local function plan_one(before, input)
  local sub = rename.parse_substitution(input)
  return rename.plan_names({ { key = 'k', before = before } }, sub)[1]
end

-- =============================================================================
-- parse_substitution(): one field, the two halves of a :%s
-- =============================================================================

do
  local sub = rename.parse_substitution('Draft/Notas')
  check("the first slash separates pattern from replacement",
    sub.find == 'Draft' and sub.replace == 'Notas', vim.inspect(sub))

  sub = rename.parse_substitution('rascunho')
  check("with no slash there is a pattern and no replacement yet",
    sub.find == 'rascunho' and sub.replace == nil, vim.inspect(sub))

  sub = rename.parse_substitution('Draft/')
  check("a trailing slash means replace with nothing",
    sub.find == 'Draft' and sub.replace == '', vim.inspect(sub))

  sub = rename.parse_substitution('a/b/c')
  check("only the first slash separates; the rest belong to the replacement",
    sub.find == 'a' and sub.replace == 'b/c', vim.inspect(sub))

  sub = rename.parse_substitution('dados\\/teoria/dados e teoria')
  check("an escaped slash is literal, not a separator",
    sub.find == 'dados/teoria' and sub.replace == 'dados e teoria', vim.inspect(sub))

  check("empty input is nothing", rename.parse_substitution('') == nil)
  check("nil input is nothing", rename.parse_substitution(nil) == nil)
  check("a leading slash is not a pattern", rename.parse_substitution('/x') == nil)
end

-- =============================================================================
-- plan_names(): Neovim regex, the same one :%s uses
-- =============================================================================

do
  local row = plan_one('Draft — Kant', 'Draft/Notas')
  check("a literal match is replaced",
    row.after == 'Notas — Kant' and row.changed, row.after)

  row = plan_one('Aula 3 - Kant', 'Aula \\(\\d\\+\\)/Aula 0\\1')
  check("capture groups work as in :%s",
    row.after == 'Aula 03 - Kant' and row.changed, row.after)

  row = plan_one('Kant e Hume', '\\vKant|Hume/X')
  check("very magic (\\v) is honoured", row.after == 'X e X', row.after)

  row = plan_one('Kant, Kant, Kant', 'Kant/Hume')
  check("every occurrence is replaced, not just the first",
    row.after == 'Hume, Hume, Hume', row.after)

  row = plan_one('[wip] Kant', '\\[wip\\] /')
  check("replacing with nothing removes the match", row.after == 'Kant', row.after)

  row = plan_one('Kant', '^/Sobre ')
  check("an anchor prepends", row.after == 'Sobre Kant', row.after)

  row = plan_one('Kant', '$/ (rascunho)')
  check("and the other anchor appends", row.after == 'Kant (rascunho)', row.after)
end

-- =============================================================================
-- Matching is information, not a verdict
-- =============================================================================

do
  local row = plan_one('Kant', 'Hume/X')
  check("a name that does not match is reported, not errored",
    row.matched == false and row.error == nil and not row.changed)
  check("and keeps its name", row.after == 'Kant', row.after)

  row = plan_one('Kant', 'Kant')
  check("with no replacement yet, a match is shown unchanged",
    row.matched and not row.changed and row.after == 'Kant')

  row = plan_one('Kant', 'Kant/')
  check("a substitution that would empty the title is refused",
    row.error == 'would leave it empty' and not row.changed, tostring(row.error))

  row = plan_one('Kant', '\\(/X')
  check("an invalid pattern is reported, not raised",
    row.error == 'invalid pattern' and not row.changed, tostring(row.error))

  row = plan_one('Kant', 'Kant/\\9')
  check("an invalid backreference is reported too",
    row.error ~= nil and not row.changed, tostring(row.error))
end

do
  local items = { { key = 'a', before = 'Kant' }, { key = 'b', before = 'Hume' } }
  local plan  = rename.plan_names(items, rename.parse_substitution('^/X '))

  check("every item is planned", #plan == 2 and plan[2].after == 'X Hume', plan[2].after)
  check("the input is not mutated",
    items[1].before == 'Kant' and items[1].after == nil)
  check("keys are carried through", plan[1].key == 'a' and plan[2].key == 'b')

  local all = rename.plan_names(items, nil)
  check("with nothing typed, everything is in play and unchanged",
    #all == 2 and all[1].matched and not all[1].changed)
end

-- =============================================================================
-- The rows the panel draws
-- =============================================================================

do
  local key = '/x/0042_note_Kant.md'

  local line = rename.format_change(
    { key = key, before = 'Kant', after = 'X Kant', matched = true, changed = true })
  check("a changed row shows before → after",
    line:find('0042_note_Kant', 1, true) and line:find('Kant  →  X Kant', 1, true) ~= nil,
    line)

  line = rename.format_change(
    { key = key, before = 'Kant', after = 'Kant', matched = true, changed = false })
  check("a matched row with no replacement yet shows just the title",
    line:find('→', 1, true) == nil and line:find('Kant', 1, true) ~= nil, line)

  line = rename.format_change(
    { key = key, before = 'Kant', after = 'Kant', error = 'invalid pattern' })
  check("an errored row says why instead",
    line:find('✗  invalid pattern', 1, true) ~= nil, line)

  check("describe reports a half-written expression",
    rename.describe({ find = 'Kant' }) == "matching 'Kant'",
    rename.describe({ find = 'Kant' }))
  check("and a complete one",
    rename.describe({ find = 'a', replace = 'b' }) == "'a' → 'b'",
    rename.describe({ find = 'a', replace = 'b' }))
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

  local plan = rename.plan_names(items, rename.parse_substitution('^/Sobre '))
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
  check("propagating unchanged titles rewrites no file",
    citations.propagate_titles({ ['note-0801'] = 'Sobre Kant' }) == 0)
  check("an empty batch is a no-op", citations.propagate_titles({}) == 0)
  check("a nil batch is a no-op", citations.propagate_titles(nil) == 0)
end

do
  local items = rename.title_items({ p1 })
  local plan  = rename.plan_names(items, rename.parse_substitution('inexistente/x'))
  local applied = rename.apply_titles(plan)
  check("a plan that changes nothing writes nothing", applied == 0, tostring(applied))

  local _, title = rename.read_title(p1)
  check("and the title is intact", title == 'Sobre Kant', title)
end

-- =============================================================================
-- bufsync: open buffers agree with what the batch wrote
-- =============================================================================

local bufsync = require('pkm.bufsync')

do
  check("a note with no buffer is not found", bufsync.buffer_for(p2) == nil)
  check("and contributes nothing to the unsaved set", #bufsync.unsaved({ p1, p2 }) == 0)
end

do
  vim.cmd('edit ' .. vim.fn.fnameescape(p1))
  local bufnr = vim.api.nvim_get_current_buf()

  check("an open note is found", bufsync.buffer_for(p1) == bufnr,
    tostring(bufsync.buffer_for(p1)))
  check("a path spelled the other way round still finds it",
    bufsync.buffer_for((p1:gsub('\\', '/'))) == bufnr)
  check("an untouched buffer is not reported as unsaved",
    #bufsync.unsaved({ p1 }) == 0)

  -- Write to the file behind the buffer's back, as a batch does.
  local fm = select(1, rename.read_title(p1))
  fm.title = 'Alterado fora do buffer'
  yaml.save_frontmatter(fm, nil, p1)

  local before = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  check("the buffer still shows the old text",
    before:find('Alterado fora', 1, true) == nil)

  check("reload re-reads it", bufsync.reload({ p1 }) == 1)
  local after = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  check("and the new title is on screen",
    after:find('Alterado fora do buffer', 1, true) ~= nil, after:sub(1, 80))
end

do
  -- A modified buffer must never be reloaded from under the user.
  vim.cmd('edit ' .. vim.fn.fnameescape(p1))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { 'edição não salva' })

  local dirty, bufs = bufsync.unsaved({ p1, p2 })
  check("an edited buffer is reported as unsaved",
    #dirty == 1 and bufs[1] == bufnr, tostring(#dirty))

  check("reload leaves it alone", bufsync.reload({ p1 }) == 0)
  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
  check("so the unsaved edit survives",
    text:find('edição não salva', 1, true) ~= nil)

  check("save writes it", bufsync.save({ p1 }) == 1)
  check("after which it is no longer unsaved", #bufsync.unsaved({ p1 }) == 0)
  check("and the edit reached the file",
    table.concat(utils.read_lines(p1), '\n'):find('edição não salva', 1, true) ~= nil)

  vim.cmd('silent! bwipeout!')
end

do
  -- The gate does not interrupt when there is nothing to ask about.
  local reached = false
  bufsync.guard({ p2 }, function() reached = true end)
  check("guard passes straight through when nothing is unsaved", reached)
end

-- =============================================================================

print(string.format("== %s (%d failure%s) ==",
  failures == 0 and "PASS" or "FAIL", failures, failures == 1 and "" or "s"))
