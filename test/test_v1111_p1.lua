-- test/test_v1111_p1.lua
-- v1.11.1 — the indicator, finished: the buffer panel and the statusline.
--
-- After a switch two vaults are identical on screen, and a buffer left over
-- from the previous one is the state where the screen and the truth disagree:
-- it sits outside the root, so `in_root` answers false and saving it stops
-- stamping the timestamp, syncing citations and touching the index. It still
-- looks like a note and has stopped being treated as one.
--
-- Both surfaces here exist to say so, and both are deliberately quiet when
-- there is nothing to confuse — one vault, or none.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1111_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local vault = require('pkm.vault')
local ui    = require('pkm.ui')

local base   = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local a_path = nvroot .. '/00 - Alpha'
local b_path = nvroot .. '/01 - Beta'

local function make_note(root, filename)
  local dir = root .. '/03-Consolidated'
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/' .. filename
  vim.fn.writefile({
    '---', 'title: ' .. filename, 'tags: []',
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo',
  }, path)
  return path
end

vim.fn.mkdir(a_path, 'p')
vim.fn.mkdir(b_path, 'p')
local a_note = make_note(a_path, '9901_note_do_alpha.md')
local b_note = make_note(b_path, '9902_note_do_beta.md')
local plain  = base .. '/solto.md'
vim.fn.writefile({ '# fora de qualquer vault' }, plain)

pkm.setup({ root_path = a_path, vaults_path = nvroot })

--- The buffer panel's real lines: opened, refreshed, and read back from the
--- buffer it renders into. Going through the panel rather than the builder is
--- the point — it is the render path the user actually sees.
local function panel_lines()
  if not ui.is_bufpanel_open() then ui.toggle_bufpanel() end
  ui.refresh_bufpanel()

  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].filetype == 'pkm-bufpanel' then
      return vim.api.nvim_buf_get_lines(b, 0, -1, false)
    end
  end
  return {}
end

local function joined()
  return table.concat(panel_lines(), '\n')
end

print("== with one vault registered, neither surface says anything ==")

vault.save({ version = 1, history = {}, vaults = { { number = 0, name = 'Alpha' } } })

vim.cmd('edit ' .. vim.fn.fnameescape(a_note))
check("the panel shows the note", joined():find('9901_note_do_alpha', 1, true)
  or joined():find('do_alpha', 1, true), joined())
check("but no vault column, because there is nothing to confuse",
  joined():find('V00', 1, true) == nil, joined())
check("and no vault in the header either", joined():find('· 00', 1, true) == nil, joined())

check("the statusline still names the active vault",
  vault.statusline() == 'V00 Alpha', vault.statusline())

print("\n== with two, the column appears ==")

vault.save({ version = 1, history = {}, vaults = {
  { number = 0, name = 'Alpha' }, { number = 1, name = 'Beta' } } })

vim.cmd('edit ' .. vim.fn.fnameescape(b_note))
vim.cmd('edit ' .. vim.fn.fnameescape(plain))
vim.cmd('edit ' .. vim.fn.fnameescape(a_note))

local text = joined()
check("the header says which vault you are in",
  text:find('· 00 Alpha', 1, true) ~= nil, text)
check("the Alpha note is tagged V00", text:find('V00', 1, true) ~= nil, text)
check("the Beta note is tagged V01",  text:find('V01', 1, true) ~= nil, text)

-- The file in no vault keeps the column blank rather than borrowing a number,
-- so the type prefixes stay in one column.
local plain_line
for _, l in ipairs(panel_lines()) do
  if l:find('solto', 1, true) then plain_line = l end
end
check("the file outside every vault has a line", plain_line ~= nil, text)
check("and no vault number on it",
  plain_line and plain_line:find('V%d') == nil, plain_line)
check("but it stays aligned with the rest",
  plain_line and plain_line:find('%[f%]') ~= nil, plain_line)

print("\n== the statusline warns when the buffer is not from the active vault ==")

vim.cmd('edit ' .. vim.fn.fnameescape(a_note))
check("in the active vault, it is just the vault",
  vault.statusline() == 'V00 Alpha', vault.statusline())

vim.cmd('edit ' .. vim.fn.fnameescape(b_note))
check("a buffer from another vault is called out",
  vault.statusline() == 'V00 Alpha [buf V01]', vault.statusline())

vim.cmd('edit ' .. vim.fn.fnameescape(plain))
check("a file in no vault is not called out — it was never a note",
  vault.statusline() == 'V00 Alpha', vault.statusline())

print("\n== and with no registry at all, both go quiet ==")

local bare = vim.fn.tempname() .. '/Solo'
vim.fn.mkdir(bare .. '/03-Consolidated', 'p')
pkm.setup({ root_path = bare })

check("the statusline is empty, not an error", vault.statusline() == '', vault.statusline())
check("and it is a string, so a statusline can concatenate it",
  type(vault.statusline()) == 'string')
check("the panel has no vault column", joined():find('V%d%d') == nil, joined())
check("and still builds", #panel_lines() >= 1)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
