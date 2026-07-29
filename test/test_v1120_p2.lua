-- test/test_v1120_p2.lua
-- v1.12.0 Ph2 — the note lifecycle, typed.
--
-- Creating, titling and renaming a note without a prompt. The whole test is the
-- assertion: every step runs a real :PKM command with its argument, and a
-- command that fell back to a prompt would block headless forever. Reaching the
-- end is the proof that the typed path never prompts.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p2.lua" -c "qa!"

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
local utils = require('pkm.utils')
local yaml  = require('pkm.yaml')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local consolidated = utils.join(root, pkm.config.folders.consolidated)

--- The frontmatter title of a note read from disk.
local function disk_title(path)
  local fm = yaml.parse_frontmatter(vim.fn.readfile(path))
  return fm and fm.title
end

--- The frontmatter title of the note in the current buffer (may differ from
--- disk before a save).
local function buffer_title()
  local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  return fm and fm.title
end

print("== :PKMNewNote note title=... creates without a prompt ==")

vim.cmd('PKMNewNote note title=SmokeIdea')
local created = vim.fn.expand('%:p')
check("a note was created and opened",
  created ~= '' and vim.fn.filereadable(created) == 1, created)
check("its number, type and title are in the filename",
  created:gsub('\\', '/'):find('/0001_note_SmokeIdea%.md$') ~= nil,
  vim.fn.fnamemodify(created, ':t'))
check("and the frontmatter carries the title", disk_title(created) == 'SmokeIdea',
  tostring(disk_title(created)))

print("\n== :PKMSetTitle writes the buffer's title, still no prompt ==")

vim.cmd('PKMSetTitle Retitled Idea')
check("a spaced title needs no quoting, and reaches the buffer",
  buffer_title() == 'Retitled Idea', tostring(buffer_title()))
check("but not the disk yet — set_title is buffer-only",
  disk_title(created) == 'SmokeIdea', tostring(disk_title(created)))

-- Persist it, the ordinary way, so the rename below reads a saved note.
vim.cmd('silent write')
check("after a save the title is on disk", disk_title(created) == 'Retitled Idea',
  tostring(disk_title(created)))

print("\n== :PKMRenameNote renames the file, keeping number and type ==")

vim.cmd('PKMRenameNote a whole new name')
local renamed = vim.fn.expand('%:p')
check("the file moved to the new name",
  renamed:gsub('\\', '/'):find('/0001_note_a_whole_new_name%.md$') ~= nil,
  vim.fn.fnamemodify(renamed, ':t'))
check("the number and type prefix were kept",
  vim.fn.fnamemodify(renamed, ':t'):find('^0001_note_') == 1)
check("the new file is on disk", vim.fn.filereadable(renamed) == 1)
check("and the old name is gone", vim.fn.filereadable(created) == 0)
check("the rename left the frontmatter title untouched",
  disk_title(renamed) == 'Retitled Idea', tostring(disk_title(renamed)))

print("\n== an explicit empty title is 'supplied', so it is unnamed, not prompted ==")

vim.cmd('PKMNewNote note title=')
local unnamed = vim.fn.expand('%:p')
check("a second note took the next number, no prompt",
  unnamed:gsub('\\', '/'):find('/0002_note_unnamed%.md$') ~= nil,
  vim.fn.fnamemodify(unnamed, ':t'))
check("and its title is the unnamed placeholder",
  disk_title(unnamed) == 'Unnamed Note', tostring(disk_title(unnamed)))

print("\n== the type is still honoured, and placement still parses ==")

vim.cmd('PKMNewNote bib title=Fonte')
local bib = vim.fn.expand('%:p')
check("a bib note carries its type in the filename",
  bib:gsub('\\', '/'):find('/0003_bib_Fonte%.md$') ~= nil,
  vim.fn.fnamemodify(bib, ':t'))

print("\n== an unrecognised positional is reported, not guessed ==")

local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMNewNote sideways title=X')
vim.notify = orig
check("a word that is neither type, place nor title= is refused",
  type(msg) == 'string' and msg:find('sideways', 1, true) ~= nil, tostring(msg))
check("and no stray note was created",
  vim.fn.filereadable(utils.join(consolidated, '0004_note_X.md')) == 0)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
