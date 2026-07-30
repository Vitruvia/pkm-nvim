-- test/test_v1130_p3.lua
-- v1.13.0 Ph3 — the :PKMTag verb-context (command clearup).
--
-- Tag CRUD as `:PKMTag <verb>`, driving the same cores the old per-operation
-- names drove. The note= writes are deterministic (they touch disk), so the
-- test runs them headlessly and checks each verb lands on the right core, that
-- the alias still works, and that only the first token is read as a verb.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm  = require('pkm')
local yaml = require('pkm.yaml')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local function disk_tags(path)
  local fm = yaml.parse_frontmatter(vim.fn.readfile(path))
  local set = {}
  for _, t in ipairs((fm and fm.tags) or {}) do set[t] = true end
  return set
end

print("== both the context command and its aliases are registered ==")

local cmds = vim.api.nvim_get_commands({})
check("the :PKMTag context exists", cmds.PKMTag ~= nil)
check("the :PKMAddTag alias still exists", cmds.PKMAddTag ~= nil)
check("the :PKMMergeTags alias still exists", cmds.PKMMergeTags ~= nil)

vim.cmd('PKMNote new note title=Subject')
local note = vim.fn.expand('%:p')
check("a note exists to act on", vim.fn.filereadable(note) == 1)

print("\n== :PKMTag add note= writes the tag to disk ==")

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

print("\n== only the first token is a verb: a tag may be named like one ==")

vim.cmd('PKMTag add merge note=note-0001')
check("`:PKMTag add merge` adds the tag 'merge', it does not run the merge verb",
  disk_tags(note)['merge'] == true, vim.inspect(disk_tags(note)))

print("\n== the alias drives the same core, unchanged ==")

vim.cmd('PKMAddTag aliaswrite note=note-0001')
check("`:PKMAddTag note=` still writes to disk", disk_tags(note)['aliaswrite'] == true,
  vim.inspect(disk_tags(note)))

print("\n== a bad note reference is refused ==")

local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMTag add draft note=note-9999')
vim.notify = orig
check("note=<nonexistent> is reported", type(msg) == 'string' and msg:find('9999', 1, true),
  tostring(msg))

print("\n== a bare :PKMTag with no verb shows usage, writes nothing ==")

local umsg
vim.notify = function(m) umsg = m end
vim.cmd('PKMTag')
vim.notify = orig
check("bare :PKMTag reports usage", type(umsg) == 'string' and umsg:find('add', 1, true),
  tostring(umsg))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
