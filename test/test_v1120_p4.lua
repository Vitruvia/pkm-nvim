-- test/test_v1120_p4.lua
-- v1.12.0 Ph4 — tags and views acting on a *named* note, on disk.
--
-- :PKMTag add/:PKMTag remove stay buffer-only by default; with note=<ref> they
-- write to the named note. :PKMView add|remove <view> note=<ref> makes that note
-- a member of the view by applying its tag condition — refusing, rather than
-- guessing, when the view can be satisfied several ways. All headless, by
-- command, no prompt.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p4.lua" -c "qa!"

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
local yaml  = require('pkm.yaml')
local views = require('pkm.views')
local tags  = require('pkm.tags')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

--- The tag set of a note read from disk.
local function disk_tags(path)
  local fm = yaml.parse_frontmatter(vim.fn.readfile(path))
  local set = {}
  for _, t in ipairs((fm and fm.tags) or {}) do set[t] = true end
  return set
end

vim.cmd('PKMNote new note title=Subject')
local note = vim.fn.expand('%:p')
check("a note exists to act on", vim.fn.filereadable(note) == 1)

print("== :PKMTag add note= writes the tag to disk ==")

vim.cmd('PKMTag add draft note=note-0001')
check("the tag reached the note on disk", disk_tags(note)['draft'] == true,
  vim.inspect(disk_tags(note)))

vim.cmd('PKMTag add ring forge note=note-0001')
check("a spaced tag needs no quoting", disk_tags(note)['ring forge'] == true,
  vim.inspect(disk_tags(note)))

print("\n== :PKMTag remove note= removes it ==")

vim.cmd('PKMTag remove draft note=note-0001')
check("the tag is gone from disk", disk_tags(note)['draft'] == nil, vim.inspect(disk_tags(note)))
check("but the other tag stayed", disk_tags(note)['ring forge'] == true)

print("\n== the buffer-only path is unchanged (no note=) ==")

-- The note is open in a buffer. Tag it without note=: buffer only, no disk.
vim.cmd('edit ' .. vim.fn.fnameescape(note))
vim.cmd('PKMTag add bufonly')
local buf_fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
local in_buf = false
for _, t in ipairs((buf_fm and buf_fm.tags) or {}) do if t == 'bufonly' then in_buf = true end end
check("the tag is in the buffer", in_buf)
check("but not yet on disk", disk_tags(note)['bufonly'] == nil)

print("\n== a named write refuses behind an unsaved buffer ==")

-- The buffer now has an unsaved 'bufonly' edit. A named write to the same note
-- must refuse rather than clobber it.
local ok_dirty, err_dirty = tags.write_note_tags(note, { add = { 'x' } })
check("the named write is refused", ok_dirty == false)
check("and says why", (err_dirty or ''):find('unsaved', 1, true) ~= nil, err_dirty)
vim.cmd('silent write')   -- settle it for the rest of the test

print("\n== :PKMView add|remove note= applies a view's tag condition ==")

check("a simple view saves", views.save('leituras', 'tag:leitura'))
vim.cmd('PKMView add leituras note=note-0001')
check("the note gained the view's tag", disk_tags(note)['leitura'] == true,
  vim.inspect(disk_tags(note)))
check("and match_all now finds it in the view", (function()
  for _, p in ipairs(views.match_all('leituras')) do
    if (p:gsub('\\', '/')):find('0001_note_Subject', 1, true) then return true end
  end
  return false
end)())

vim.cmd('PKMView remove leituras note=note-0001')
check("removing takes the tag back out", disk_tags(note)['leitura'] == nil,
  vim.inspect(disk_tags(note)))

print("\n== an ambiguous view refuses, it does not guess a tag ==")

check("an OR view saves", views.save('ou', 'tag:a OR tag:b'))
local ok_amb, err_amb = views.set_membership(note, 'ou', 'add')
check("adding to an either/or view is refused", ok_amb == false)
check("and points at the interactive form",
  (err_amb or ''):find('several ways', 1, true) ~= nil, err_amb)
check("and no stray tag was written",
  disk_tags(note)['a'] == nil and disk_tags(note)['b'] == nil, vim.inspect(disk_tags(note)))

print("\n== a bad note reference is refused ==")

local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMTag add draft note=note-9999')
vim.notify = orig
check("note=<nonexistent> is reported", type(msg) == 'string' and msg:find('9999', 1, true))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
