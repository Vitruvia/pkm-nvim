-- test/test_v1130_p2.lua
-- v1.13.0 Ph2 — the :PKMNote verb-context (command clearup).
--
-- Every note-lifecycle operation is now reachable as `:PKMNote <verb>`, driving
-- the same cores the old per-operation names drove. This test runs the verb
-- forms headlessly: a step that fell back to a prompt would block forever, so
-- reaching the end proves the typed path never prompts, and the assertions prove
-- each verb lands on the right core — including the safety slice, where
-- `:PKMNote new … by=<agent>` allocates the number, writes the frontmatter and
-- stamps the authorship marker.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p2.lua" -c "qa!"

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
local notes = require('pkm.notes')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local consolidated = utils.join(root, pkm.config.folders.consolidated)

local function disk_title(path)
  local fm = yaml.parse_frontmatter(vim.fn.readfile(path))
  return fm and fm.title
end

local function buffer_title()
  local fm = yaml.parse_frontmatter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
  return fm and fm.title
end

print("== both the context command and its aliases are registered ==")

local cmds = vim.api.nvim_get_commands({})
check("the :PKMNote context exists", cmds.PKMNote ~= nil)
check("the :PKMNewNote alias still exists", cmds.PKMNewNote ~= nil)
check("the :PKMRenameNote alias still exists", cmds.PKMRenameNote ~= nil)

print("\n== :PKMNote new creates without a prompt ==")

vim.cmd('PKMNote new note title=SmokeIdea')
local created = vim.fn.expand('%:p')
check("a note was created and opened",
  created ~= '' and vim.fn.filereadable(created) == 1, created)
check("its number, type and title are in the filename",
  created:gsub('\\', '/'):find('/0001_note_SmokeIdea%.md$') ~= nil,
  vim.fn.fnamemodify(created, ':t'))

print("\n== :PKMNote settitle writes the buffer title (verb → set_title) ==")

vim.cmd('PKMNote settitle Retitled Idea')
check("a spaced title reaches the buffer",
  buffer_title() == 'Retitled Idea', tostring(buffer_title()))
check("but not the disk yet — set_title is buffer-only",
  disk_title(created) == 'SmokeIdea', tostring(disk_title(created)))

-- A verb word appearing *after* the verb is text, not a second verb: only the
-- first token is matched against the verb list.
vim.cmd('PKMNote settitle new plan')
check("a verb word in the title is kept as text, not dispatched",
  buffer_title() == 'new plan', tostring(buffer_title()))

print("\n== :PKMNote rename moves the file, keeping number and type ==")

vim.cmd('silent write')
vim.cmd('PKMNote rename a whole new name')
local renamed = vim.fn.expand('%:p')
check("the file moved to the new name",
  renamed:gsub('\\', '/'):find('/0001_note_a_whole_new_name%.md$') ~= nil,
  vim.fn.fnamemodify(renamed, ':t'))
check("the old name is gone", vim.fn.filereadable(created) == 0)

print("\n== a bare type routes to the default verb (new) ==")

vim.cmd('PKMNote note title=Second')
local second = vim.fn.expand('%:p')
check("`:PKMNote note` (no verb) creates via the default new verb",
  second:gsub('\\', '/'):find('/0002_note_Second%.md$') ~= nil,
  vim.fn.fnamemodify(second, ':t'))

print("\n== the safety slice: :PKMNote new … by=<agent> marks authorship ==")

vim.cmd('PKMNote new bib title=Fonte by=Claude')
local agent_note = vim.fn.expand('%:p')
check("the number was allocated and the type is in the name",
  agent_note:gsub('\\', '/'):find('/0003_bib_ByClaude_Fonte%.md$') ~= nil,
  vim.fn.fnamemodify(agent_note, ':t'))
check("agent_authored reads the author back through the verb path",
  notes.agent_authored(agent_note) == 'Claude',
  tostring(notes.agent_authored(agent_note)))
local fm = yaml.parse_frontmatter(vim.fn.readfile(agent_note))
check("and the frontmatter records the author too", fm and fm.author == 'Claude',
  tostring(fm and fm.author))

print("\n== an unrecognised positional is reported, not guessed ==")

local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMNote new sideways title=X')
vim.notify = orig
check("a word that is neither type, place nor title= is refused",
  type(msg) == 'string' and msg:find('sideways', 1, true) ~= nil, tostring(msg))
check("and no stray note was created",
  vim.fn.filereadable(utils.join(consolidated, '0004_note_X.md')) == 0)

print("\n== the alias still drives the same core, unchanged ==")

vim.cmd('PKMNewNote note title=ViaAlias')
local via_alias = vim.fn.expand('%:p')
check("`:PKMNewNote` creates just as `:PKMNote new` does",
  via_alias:gsub('\\', '/'):find('/0004_note_ViaAlias%.md$') ~= nil,
  vim.fn.fnamemodify(via_alias, ':t'))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
