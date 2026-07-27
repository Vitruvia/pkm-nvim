-- test/test_v1110_p2.lua
-- v1.11.0 Ph2 — the vault lifecycle.
--
-- Creating, renaming, renumbering, unregistering and adopting. The route the
-- phase has to survive is the round trip:
--
--   create → rename → renumber → unregister → the folder is in Unregistered/
--   with its notes intact → adopt back
--
-- and the property underneath it is that folder and registry never disagree: a
-- refused operation leaves both exactly as they were, and a completed one moves
-- both. Deleting a note is not reachable from any of these.
--
-- Self-contained: its own Note-Vault in a temp directory.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1110_p2.lua" -c "qa!"

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
local vault = require('pkm.vault')

local function isdir(p)  return vim.fn.isdirectory(p) == 1 end
local function isfile(p) return vim.fn.filereadable(p) == 1 end

local base   = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local home   = nvroot .. '/00 - Home'          -- the active vault throughout
vim.fn.mkdir(home .. '/03-Consolidated', 'p')

pkm.setup({ root_path = home, vaults_path = nvroot })

-- Home is registered by hand, so the registry starts in a known state.
vault.save({ version = 1, history = {}, vaults = { { number = 0, name = 'Home' } } })
check("the fixture registered Home", (vault.active() or {}).name == 'Home')

local folders = pkm.config.folders

print("== create ==")

local ok, err = vault.create('LLM-Claude', { git = false })
check("create() succeeds", ok, err)

local claude = nvroot .. '/01 - LLM-Claude'
check("it took the next free number", isdir(claude), claude)
check("and the registry agrees", (vault.get('LLM-Claude') or {}).number == 1)

for _, key in ipairs({ 'scratchpad', 'journal', 'consolidated', 'templates' }) do
  check(string.format("the skeleton has %s", folders[key]),
    isdir(utils.join(claude, folders[key])))
end
check("views.json was created empty", isfile(utils.join(claude, 'views.json')))
check("and it is a JSON object, so views.load accepts it",
  table.concat(vim.fn.readfile(utils.join(claude, 'views.json'))) == '{}')
check(".gitignore was created", isfile(utils.join(claude, '.gitignore')))
check("and it keeps the trash out of history",
  table.concat(vim.fn.readfile(utils.join(claude, '.gitignore')), '\n')
    :find('.pkm-trash/', 1, true) ~= nil)
check("no git repository, because git = false", not isdir(utils.join(claude, '.git')))
check("history recorded the creation", #vault.history() == 1, #vault.history())

print("\n== create refuses rather than half-succeeds ==")

print("  (the errors below are expected — they are the refusals being asserted)")
local ok_dup, err_dup = vault.create('llm-claude', { git = false })
check("a name differing only in case is refused", ok_dup == false)
check("and the message names the holder",
  (err_dup or ''):find('01', 1, true) ~= nil, err_dup)

check("an invalid name is refused", vault.create('bad/name', { git = false }) == false)
check("and no folder was made for it", not isdir(nvroot .. '/02 - bad'))
check("the registry still holds two vaults", #vault.list() == 2, #vault.list())

-- A folder that is already there is never absorbed silently: adopt is the
-- command that takes contents as they stand, and it says so.
vim.fn.mkdir(nvroot .. '/02 - Squatter', 'p')
local ok_sq, err_sq = vault.create('Squatter', { git = false, number = 2 })
check("an existing folder is refused, not overwritten", ok_sq == false)
check("and the message points at adopt",
  (err_sq or ''):find('Adopt', 1, true) ~= nil, err_sq)

print("\n== notes ride along, and unsaved work blocks the move ==")

local note = claude .. '/' .. folders.consolidated .. '/0001_note_Marker.md'
vim.fn.writefile({ '---', 'title: Marker', 'tags: []', '---', '', 'conteudo original' }, note)

vim.cmd('edit ' .. vim.fn.fnameescape(note))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'uma linha nao salva' })
check("the note is open and modified", vim.bo[buf].modified)

local ok_mod, err_mod = vault.rename('LLM-Claude', 'Claude')
check("the rename is refused while a note in it is unsaved", ok_mod == false)
check("and the message says which note",
  (err_mod or ''):find('Marker', 1, true) ~= nil, err_mod)
check("the folder did not move", isdir(claude))
check("and the registry did not change", (vault.get('LLM-Claude') or {}).number == 1)

vim.cmd('silent! edit!')   -- discard, the way the message asks
check("the buffer is clean again", not vim.bo[buf].modified)

print("\n== rename keeps the number ==")

local ok_ren, err_ren = vault.rename('LLM-Claude', 'Claude')
check("rename() succeeds once nothing is unsaved", ok_ren, err_ren)

local renamed = nvroot .. '/01 - Claude'
check("the folder moved",                isdir(renamed) and not isdir(claude))
check("the number was kept",             (vault.get('Claude') or {}).number == 1)
check("the old name means nothing now",  vault.get('LLM-Claude') == nil)
check("the note came with the folder",   isfile(renamed .. '/' .. folders.consolidated .. '/0001_note_Marker.md'))
check("with its text untouched",
  table.concat(vim.fn.readfile(renamed .. '/' .. folders.consolidated .. '/0001_note_Marker.md'), '\n')
    :find('conteudo original', 1, true) ~= nil)
check("the open buffer followed the move",
  (vim.api.nvim_buf_get_name(buf):gsub('\\', '/')):find('01 %- Claude') ~= nil,
  vim.api.nvim_buf_get_name(buf))
check("history recorded the rename", (vault.history()[2] or {}).event == 'rename')
check("and what it was named before", (vault.history()[2] or {}).from == 'LLM-Claude')

print("  (expected refusals follow)")
check("renaming a vault that does not exist is refused", vault.rename('Nobody', 'X') == false)
check("renaming onto a taken name is refused",           vault.rename('Claude', 'Home') == false)
local _, err_same = vault.rename('Claude', 'Claude')
check("renaming to its own name is refused", err_same ~= nil, err_same)

print("\n== renumber keeps the name ==")

local ok_num, err_num = vault.renumber('Claude', 7)
check("renumber() succeeds", ok_num, err_num)
check("the folder moved again",  isdir(nvroot .. '/07 - Claude'))
check("the name was kept",       (vault.get('Claude') or {}).number == 7)
check("the note is still there", isfile(nvroot .. '/07 - Claude/' .. folders.consolidated .. '/0001_note_Marker.md'))

print("  (expected refusals follow)")
check("renumbering onto a taken number is refused", vault.renumber('Claude', 0) == false)
check("a fractional number is refused",             vault.renumber('Claude', 1.5) == false)
check("and the vault is still 07",                  (vault.get('Claude') or {}).number == 7)

print("\n== the active vault follows its own folder ==")

-- The property that makes a rename safe while a vault is in use: the eight
-- modules that keep config hold the same table, so mutating root_path in place
-- is what reaches all of them.
check("the root is Home before", (vault.active() or {}).name == 'Home')
local ok_home = vault.rename('Home', 'Casa')
check("renaming the active vault succeeds", ok_home)
check("config.root_path followed it",
  (pkm.config.root_path:gsub('\\', '/')):find('00 %- Casa') ~= nil, pkm.config.root_path)
check("and active() answers with the new name", (vault.active() or {}).name == 'Casa')
check("the trash directory followed too, because it reads the root at call time",
  (require('pkm.trash').trash_dir():gsub('\\', '/')):find('00 %- Casa') ~= nil,
  require('pkm.trash').trash_dir())

print("\n== unregister moves, and never deletes ==")

print("  (expected refusal follows)")
local ok_act, err_act = vault.unregister('Casa')
check("the active vault refuses to be unregistered", ok_act == false)
check("and says why", (err_act or ''):find('active', 1, true) ~= nil, err_act)

local ok_un, err_un = vault.unregister('Claude')
check("unregister() succeeds for a vault that is not active", ok_un, err_un)

local parked = nvroot .. '/Unregistered/Claude'
check("the folder is in Unregistered/",   isdir(parked))
check("it is no longer where it was",     not isdir(nvroot .. '/07 - Claude'))
check("the registry dropped it",          vault.get('Claude') == nil)
check("the note is intact, not deleted",
  isfile(parked .. '/' .. folders.consolidated .. '/0001_note_Marker.md'))
check("with its text still there",
  table.concat(vim.fn.readfile(parked .. '/' .. folders.consolidated .. '/0001_note_Marker.md'), '\n')
    :find('conteudo original', 1, true) ~= nil)
check("and it now belongs to no vault at all",
  vault.of(parked .. '/' .. folders.consolidated .. '/0001_note_Marker.md') == nil)

print("\n== adopt is the way back ==")

local ok_ad, err_ad, entry = vault.adopt('Claude')
check("adopt() succeeds", ok_ad, err_ad)
check("it reports the vault it became", entry ~= nil and entry.name == 'Claude')
check("a plain folder name takes the next free number",
  (vault.get('Claude') or {}).number == 1, vim.inspect(vault.get('Claude')))
check("the folder is back beside the vaults", isdir(nvroot .. '/01 - Claude'))
check("Unregistered/ no longer holds it",     not isdir(parked))
check("the note survived the round trip",
  isfile(nvroot .. '/01 - Claude/' .. folders.consolidated .. '/0001_note_Marker.md'))
check("and belongs to a vault again",
  (vault.of(nvroot .. '/01 - Claude/' .. folders.consolidated .. '/0001_note_Marker.md') or {}).name
    == 'Claude')
-- A folder that already says what it is proposes its own number and name.
-- It is also a folder that never went through create(), so it arrives with
-- only the one subfolder it was built with — which is what proves adopt takes
-- contents as they stand instead of imposing the skeleton.
vim.fn.mkdir(nvroot .. '/Unregistered/03 - Antiga/' .. folders.consolidated, 'p')
local ok_sh, _, entry_sh = vault.adopt('03 - Antiga')
check("a folder shaped 'NN - Name' keeps both", ok_sh and entry_sh.number == 3
  and entry_sh.name == 'Antiga', vim.inspect(entry_sh))
check("and lands at that number", isdir(nvroot .. '/03 - Antiga'))
check("adopt imposed no skeleton the folder did not have",
  not isdir(nvroot .. '/03 - Antiga/' .. folders.journal))
check("and kept the one it did", isdir(nvroot .. '/03 - Antiga/' .. folders.consolidated))

-- A folder beside the vaults that no vault claims is adopted where it stands.
-- This is how a Note-Vault that predates the registry acquires one: the vaults
-- are already in their folders and must not move to be registered.
vim.fn.mkdir(nvroot .. '/05 - Preexistente/' .. folders.consolidated, 'p')
local ok_pre, err_pre, entry_pre = vault.adopt('05 - Preexistente')
check("a folder beside the vaults is adopted in place", ok_pre, err_pre)
check("keeping the number and name it already had",
  entry_pre and entry_pre.number == 5 and entry_pre.name == 'Preexistente',
  vim.inspect(entry_pre))
check("it did not move to get registered", isdir(nvroot .. '/05 - Preexistente'))
check("and Unregistered/ was never involved",
  not isdir(nvroot .. '/Unregistered/05 - Preexistente'))

print("  (expected refusals follow)")
check("adopting a folder that is not there is refused", vault.adopt('Ghost') == false)
vim.fn.mkdir(nvroot .. '/Unregistered/Casa', 'p')
local ok_col, err_col = vault.adopt('Casa')
check("adopting onto a taken name is refused", ok_col == false)
check("and the message names the holder", (err_col or ''):find('00', 1, true) ~= nil, err_col)
check("the refused folder stayed in Unregistered/", isdir(nvroot .. '/Unregistered/Casa'))

print("\n== folder and registry never disagree ==")

-- Everything above ran through save(), which validates before writing. If any
-- refusal had written a half-state, this is where it shows.
local ok_valid, err_valid = vault.validate({ version = 1, vaults = vault.list(), history = {} })
check("the registry as it stands is valid", ok_valid, err_valid)

local seen = 0
for _, v in ipairs(vault.list()) do
  if isdir(vault.path_of(v)) then seen = seen + 1 end
end
check("every registered vault has its folder on disk", seen == #vault.list(),
  string.format('%d of %d', seen, #vault.list()))

-- Every folder beside the vaults is either a registered vault, `Unregistered/`,
-- or one the test deliberately left unclaimed: `02 - Squatter`, planted to prove
-- create() refuses an occupied folder rather than absorbing it. Anything else
-- appearing here would be a vault the registry lost track of.
local unclaimed = {}
for _, dir in ipairs(vim.fn.glob(nvroot .. '/*', false, true)) do
  local leaf = vim.fn.fnamemodify(dir, ':t')
  if vim.fn.isdirectory(dir) == 1 and leaf ~= 'Unregistered' and vault.of(dir) == nil then
    unclaimed[#unclaimed + 1] = leaf
  end
end
check("the only unclaimed folder is the squatter the test planted",
  #unclaimed == 1 and unclaimed[1] == '02 - Squatter', table.concat(unclaimed, ', '))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
