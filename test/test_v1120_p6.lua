-- test/test_v1120_p6.lua
-- v1.12.0 Ph6 — :PKMCheck, the read-only vault audit.
--
-- The rule this module lives by is "no false positive", so the test proves that
-- first: a corpus the system itself produced — notes created and cited by
-- command — must report ZERO findings. Only then are specific corruptions
-- introduced, one per check, and each must surface. A checker that fires on a
-- clean vault is worse than none, so the clean pass is the load-bearing one.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p6.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm     = require('pkm')
local utils   = require('pkm.utils')
local vault   = require('pkm.vault')
local checker = require('pkm.check')

local base   = vim.fn.tempname() .. '/Note-Vault'
local root   = base .. '/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root, vaults_path = base })

local consolidated = utils.join(root, pkm.config.folders.consolidated)

--- Do any findings carry this kind?
local function has_kind(findings, kind)
  for _, f in ipairs(findings) do if f.kind == kind then return true end end
  return false
end

print("== a corpus the system produced is clean ==")

-- Five notes, two symmetric citation pairs, all created and linked by command.
vim.cmd('PKMNote new note title=Alpha')   -- 0001
vim.cmd('PKMNote new note title=Bravo')   -- 0002
vim.cmd('PKMNote new note title=Charlie') -- 0003
vim.cmd('PKMNote new note title=Delta')   -- 0004
local echo = vim.fn.expand('%:p')
vim.cmd('PKMNote new note title=Echo')    -- 0005
local alpha = consolidated .. '/0001_note_Alpha.md'

-- Alpha cites Bravo; Delta cites Echo. Both through the engine, so both sides
-- of the graph are written for us.
vim.cmd('edit ' .. vim.fn.fnameescape(alpha))
vim.cmd('PKMCite note-0002')
vim.cmd('edit ' .. vim.fn.fnameescape(echo))   -- reopen Delta? echo is 0005; cite from Delta
local delta = consolidated .. '/0004_note_Delta.md'
vim.cmd('edit ' .. vim.fn.fnameescape(delta))
vim.cmd('PKMCite note-0005')

local clean = checker.run()
check("a system-produced corpus reports nothing", #clean == 0,
  vim.inspect(vim.tbl_map(function(f) return f.kind .. ':' .. (f.message or '') end, clean)))

print("== now, one corruption per check ==")

--- Write a consolidated note from explicit lines.
local function write_note(name, lines)
  vim.fn.writefile(lines, consolidated .. '/' .. name)
end

local function empty_group()
  return {
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
  }
end

-- The parser reads a list-of-maps only with the dash on its own line and the
-- fields indented under it — the exact shape save_frontmatter writes.
local function entry(id, title)
  return { '    -', '        identifier: ' .. id, '        title: ' .. title,
    '        link: "[[x]]"' }
end

-- Dangling: cites a note that does not exist.
do
  local l = { '---', 'title: Dangler', 'cites:', '  notes:' }
  vim.list_extend(l, entry('note-9999', 'ghost'))
  vim.list_extend(l, { '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'body' })
  write_note('0007_note_Dangler.md', l)
end

-- Asymmetry: claims to be cited_by Alpha, but Alpha does not cite it.
do
  local l = { '---', 'title: Lonely',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes:' }
  vim.list_extend(l, entry('note-0001', 'Alpha'))
  vim.list_extend(l, { '  bib: []', '  journal: []', '  scratch: []', '---', '', 'body' })
  write_note('0006_note_Lonely.md', l)
end

-- Number collision: a second 0002.
write_note('0002_note_Twin.md',
  vim.list_extend({ '---', 'title: Twin' }, vim.list_extend(empty_group(), { '---', '', 'body' })))

-- Malformed: cites is a bare string, not the grouped shape.
write_note('0008_note_Broken.md',
  { '---', 'title: Broken', 'cites: oops', '---', '', 'body' })

-- Cross-vault references: one known, one unknown, one renamed.
vault.save({ version = 1, vaults = { { number = 0, name = 'Test' }, { number = 1, name = 'Vitruvia' } },
  history = { { at = '2026-01-01T00:00:00Z', event = 'rename', number = 1,
               from = 'Antiga', to = 'Vitruvia' } } })
write_note('0009_note_Refs.md', {
  '---', 'title: Refs',
  'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
  'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
  '---', '',
  'A known one [Vitruvia::note{0001}] is fine.',
  'An unknown one [Ghost::note{0001}] is not.',
  'A renamed one [Antiga::note{0001}] should say so.',
})

-- Unregistered notes waiting to be adopted.
vim.fn.mkdir(base .. '/Unregistered/Old/03-Consolidated', 'p')
vim.fn.writefile({ '---', 'title: Stranded', '---', '', 'x' },
  base .. '/Unregistered/Old/03-Consolidated/0001_note_Stranded.md')

local f = checker.run()

check("dangling citation is caught", has_kind(f, 'dangling-citation'))
check("asymmetric citation is caught", has_kind(f, 'asymmetric-citation'))
check("number collision is caught", has_kind(f, 'number-collision'))
check("malformed citations are caught", has_kind(f, 'malformed-citations'))
check("an unknown vault reference is caught", has_kind(f, 'unknown-vault-reference'))
check("a renamed vault reference is caught", has_kind(f, 'renamed-vault-reference'))
check("stranded Unregistered/ notes are caught", has_kind(f, 'unregistered-notes'))

print("\n== the known cross-vault reference did NOT fire ==")

-- Vitruvia is registered, so [Vitruvia::note{0001}] must not be reported as
-- unknown. Exactly one unknown-vault-reference is expected — Ghost — and its
-- message must name Ghost, not Vitruvia. (The renamed finding legitimately
-- mentions Vitruvia as the new name, so a bare text match would misfire.)
local unknown = {}
for _, fi in ipairs(f) do
  if fi.kind == 'unknown-vault-reference' then unknown[#unknown + 1] = fi.message end
end
check("only the unknown vault is flagged, not the registered one",
  #unknown == 1 and unknown[1]:find('Ghost', 1, true) ~= nil, vim.inspect(unknown))

print("\n== errors sort before warnings ==")

local last_error, first_warning
for i, fi in ipairs(f) do
  if fi.severity == 'error' then last_error = i end
  if fi.severity == 'warning' and not first_warning then first_warning = i end
end
check("every error comes before every warning",
  not last_error or not first_warning or last_error < first_warning,
  string.format('last_error=%s first_warning=%s', tostring(last_error), tostring(first_warning)))

print("\n== :PKMCheck runs end to end without prompting ==")

vim.cmd('PKMCheck')
check("the command produced a check buffer", vim.bo.filetype == 'pkm-check', vim.bo.filetype)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
