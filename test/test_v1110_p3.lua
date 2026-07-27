-- test/test_v1110_p3.lua
-- v1.11.0 Ph3 — choosing the active vault, and knowing which one it is.
--
-- The switch has three guards, and each is proved here on its own, with the
-- case that distinguishes it from the other two:
--
--   1. what the old root produced is discarded — the index lists the new
--      vault's notes, and a view saved in one vault does not exist in the other
--      (views.json lives *inside* the root, so a cache held across a switch
--      would resolve one vault's views against another's notes);
--   2. the switch is refused while the vault being left holds unsaved work;
--   3. the indicator changes, because after a switch the two vaults are
--      identical on screen and every destructive command acts on "the vault".
--
-- Plus the startup form: a vault named in the config, and $PKM_VAULT taking
-- precedence over it for one session.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1110_p3.lua" -c "qa!"

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
local views = require('pkm.views')
local index = require('pkm.index')

local base   = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local a_path = nvroot .. '/00 - Alpha'
local b_path = nvroot .. '/01 - Beta'

--- Write a note with one tag into a vault's consolidated folder.
local function make_note(root, filename, tag)
  local dir = root .. '/03-Consolidated'
  vim.fn.mkdir(dir, 'p')
  local path = dir .. '/' .. filename
  vim.fn.writefile({
    '---', 'title: ' .. filename, 'author: ""',
    'tags:', '  - ' .. tag,
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo',
  }, path)
  return path
end

vim.fn.mkdir(a_path, 'p')
vim.fn.mkdir(b_path, 'p')
local a_note = make_note(a_path, '9701_note_soh_no_alpha.md', 'alphatag')
local b_note = make_note(b_path, '9801_note_soh_no_beta.md',  'betatag')

-- Register both, starting on Alpha.
pkm.setup({ root_path = a_path, vaults_path = nvroot })
vault.save({ version = 1, history = {}, vaults = {
  { number = 0, name = 'Alpha' }, { number = 1, name = 'Beta' } } })

print("== the indicator says which vault this is ==")

check("indicator() names the active vault", vault.indicator() == '00 Alpha', vault.indicator())
check("and it is empty, not nil, for an unregistered root",
  type(vault.indicator()) == 'string')

print("\n== startup: a vault is chosen by name, not by path ==")

vim.env.PKM_VAULT = nil
pkm.setup({ vaults_path = nvroot, vault = 'Beta' })
check("config.vault resolved into the root",
  (pkm.config.root_path:gsub('\\', '/')) == (utils.normalize(b_path):gsub('\\', '/')),
  pkm.config.root_path)
check("active() agrees", (vault.active() or {}).name == 'Beta')
check("and vim.g.pkm_vault was published at startup", vim.g.pkm_vault == '01 Beta', vim.g.pkm_vault)

-- The reason the startup form exists: the real configuration reaching the test
-- vault for one session, without init.lua being edited.
vim.env.PKM_VAULT = 'Alpha'
pkm.setup({ vaults_path = nvroot, vault = 'Beta' })
check("$PKM_VAULT outranks config.vault", (vault.active() or {}).name == 'Alpha',
  pkm.config.root_path)
vim.env.PKM_VAULT = nil

print("  (the error below is expected — an unregistered name being refused)")
pkm.setup({ root_path = a_path, vaults_path = nvroot, vault = 'Gamma' })
check("an unknown vault name leaves the root where it was",
  (pkm.config.root_path:gsub('\\', '/')) == (utils.normalize(a_path):gsub('\\', '/')),
  pkm.config.root_path)

print("\n== guard 1: what the old root produced is discarded ==")

pkm.setup({ root_path = a_path, vaults_path = nvroot })

-- A view that exists only in Alpha, because views.json lives inside Alpha.
check("a view saves into Alpha", views.save('__so_alpha', 'tag:alphatag'))
check("and it matches the Alpha note", #views.match_all('__so_alpha') == 1,
  #views.match_all('__so_alpha'))

index.rebuild()
check("the index holds Alpha's note", #index.get_all() == 1, #index.get_all())
check("and it is the Alpha one",
  (index.get_all()[1] or {}).path and
  (index.get_all()[1].path:gsub('\\', '/')):find('soh_no_alpha', 1, true) ~= nil)

local ok_sw, err_sw, entry_sw = vault.select('Beta')
check("select() succeeds", ok_sw, err_sw)
check("and reports the vault it moved to", (entry_sw or {}).name == 'Beta')

check("the index now holds Beta's note only", #index.get_all() == 1, #index.get_all())
check("and it is the Beta one",
  (index.get_all()[1].path:gsub('\\', '/')):find('soh_no_beta', 1, true) ~= nil)
check("Alpha's note is gone from the index",
  index.get(a_note) == nil)

-- The sharp one. Had the sidecar cache survived, this view would still be
-- listed, would still resolve, and would name files in a vault it was never
-- saved in.
local names = views.list()
local found = false
for _, n in ipairs(names) do if n == '__so_alpha' then found = true end end
check("the view saved in Alpha does not exist in Beta", not found,
  table.concat(names, ', '))
check("because the sidecar being read is Beta's own, and Beta has none",
  vim.fn.filereadable(utils.join(pkm.config.root_path, 'views.json')) == 0,
  utils.join(pkm.config.root_path, 'views.json'))
check("while Alpha's is still on disk, unharmed",
  vim.fn.filereadable(utils.join(utils.normalize(a_path), 'views.json')) == 1)

print("\n== guard 2: unsaved work in the vault being left ==")

vault.select('Alpha')
check("back on Alpha", (vault.active() or {}).name == 'Alpha')

vim.cmd('edit ' .. vim.fn.fnameescape(a_note))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'edicao nao salva' })
check("an Alpha note is open and modified", vim.bo[buf].modified)

print("  (the error below is expected — the refusal being asserted)")
local ok_dirty, err_dirty = vault.select('Beta')
check("the switch is refused", ok_dirty == false)
check("and the message names the note",
  (err_dirty or ''):find('soh_no_alpha', 1, true) ~= nil, err_dirty)
check("the root did not move",
  (pkm.config.root_path:gsub('\\', '/')) == (utils.normalize(a_path):gsub('\\', '/')),
  pkm.config.root_path)
check("and the indicator still says Alpha", vault.indicator() == '00 Alpha')

-- The refusal is a guard, not a wall: it exists so the switch is a decision.
check("force switches anyway", vault.select('Beta', { force = true }) == true)
check("and the root moved", (vault.active() or {}).name == 'Beta')

vim.cmd('silent! bdelete! ' .. buf)

print("\n== guard 3: the indicator follows the switch ==")

vault.select('Alpha')
check("indicator is Alpha", vault.indicator() == '00 Alpha', vault.indicator())
check("and vim.g.pkm_vault with it", vim.g.pkm_vault == '00 Alpha', vim.g.pkm_vault)

vault.select('Beta')
check("indicator is Beta", vault.indicator() == '01 Beta', vault.indicator())
check("and vim.g.pkm_vault with it", vim.g.pkm_vault == '01 Beta', vim.g.pkm_vault)

-- The sidebar title is where the indicator has to be seen, because that panel
-- is where the destructive commands are reached from.
check("the note Beta holds is the one the index has",
  (index.get_all()[1].path:gsub('\\', '/')):find('soh_no_beta', 1, true) ~= nil)
check("and b_note is indexed", index.get(b_note) ~= nil)

print("\n== switching to nowhere, and to where we already are ==")

print("  (the error below is expected)")
local ok_no, err_no = vault.select('Gamma')
check("an unregistered name is refused", ok_no == false)
check("and the message says so", (err_no or ''):find('Gamma', 1, true) ~= nil, err_no)
check("the vault did not change", (vault.active() or {}).name == 'Beta')

check("switching to the active vault succeeds without doing anything",
  vault.select('Beta') == true)
check("and it is still Beta", (vault.active() or {}).name == 'Beta')

print("\n== root_path alone still bypasses all of this ==")

local bare = vim.fn.tempname() .. '/Solo'
vim.fn.mkdir(bare .. '/03-Consolidated', 'p')
pkm.setup({ root_path = bare })
check("a bare root starts with no vault", vault.active() == nil)
check("the indicator is empty, not an error", vim.g.pkm_vault == '', vim.g.pkm_vault)
check("and the plugin still works over it", type(index.get_all()) == 'table')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
