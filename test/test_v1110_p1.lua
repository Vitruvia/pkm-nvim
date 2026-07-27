-- test/test_v1110_p1.lua
-- v1.11.0 Ph1 — the vault registry and identity.
--
-- A vault is a folder, so which vault a note belongs to is a fact about its
-- path. This file pins that fact and the three properties it rests on:
--
--   1. the registry is OPTIONAL — a bare root_path behaves exactly as before,
--      which is what every other test file and min_init depend on;
--   2. the folder name is DERIVED from number and name, and survives the round
--      trip back;
--   3. `of()` compares paths PLAINLY — never as a Lua pattern, where the `-` in
--      "00 - Alpha" is a quantifier and would also match the folder "00 Alpha".
--
-- Self-contained: it builds its own Note-Vault in a temp directory with the
-- real shape, so it proves the properties rather than the state of one machine.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1110_p1.lua" -c "qa!"

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

--- Compare two paths the way the filesystem would.
local function same(a, b)
  return (tostring(a):gsub('\\', '/')):lower() == (tostring(b):gsub('\\', '/')):lower()
end

-- A Note-Vault shaped like the real one, plus two folders that are not vaults.
local base   = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local alpha  = nvroot .. '/00 - Alpha'
local beta   = nvroot .. '/01 - Beta'
local decoy  = nvroot .. '/00 Alpha'          -- no hyphen: the pattern trap
local outside = base .. '/Elsewhere'

for _, d in ipairs({ alpha .. '/03-Consolidated', beta .. '/03-Consolidated',
                     decoy .. '/03-Consolidated', nvroot .. '/Unregistered', outside }) do
  vim.fn.mkdir(d, 'p')
end

pkm.setup({ root_path = alpha })

local registry = nvroot .. '/vaults.json'

print("== the registry is optional ==")

-- Everything below runs before vaults.json exists. This is the state of all 29
-- other test files and of min_init: a root_path and nothing else. If any of it
-- errors or answers something other than "nothing", the phase broke them.
check("vaults_root is derived from the root's parent",
  same(vault.vaults_root(), nvroot), vault.vaults_root())
check("registry_path names vaults.json beside the vaults",
  same(vault.registry_path(), registry), vault.registry_path())
check("the file does not exist yet", vim.fn.filereadable(registry) == 0)
check("list() is empty rather than an error", #vault.list() == 0, #vault.list())
check("of() answers nil for a note in a real folder", vault.of(alpha .. '/03-Consolidated/x.md') == nil)
check("active() answers nil", vault.active() == nil)
check("get() answers nil", vault.get('Alpha') == nil)
check("history() is an empty list", #vault.history() == 0)

print("\n== a name is validated before it can become a folder ==")

local good = { 'Alpha', 'LLM-Claude', 'NotesTeste', 'Vitruvia', 'Notas de Aula', '01 - Nested' }
for _, n in ipairs(good) do
  local ok, err = vault.validate_name(n)
  check(string.format("%q is accepted", n), ok, err)
end

local bad = {
  [''] = 'empty',
  [' Alpha'] = 'leading space',
  ['Alpha '] = 'trailing space',
  ['a/b'] = 'path separator',
  ['a\\b'] = 'path separator',
  ['Vitruvia::note'] = 'the cross-vault separator',
  ['a?b'] = 'a wildcard',
  ['..'] = 'not a name',
  ['Unregistered'] = 'the reserved folder',
}
for n, why in pairs(bad) do
  local ok = vault.validate_name(n)
  check(string.format("%q is refused (%s)", n, why), ok == false)
end

check("a number must be a non-negative integer", vault.validate_number(0) == true)
check("and 1.5 is not one", vault.validate_number(1.5) == false)
check("and -1 is not one",  vault.validate_number(-1) == false)

print("\n== the folder is derived, and reads back ==")

check("folder_of pads the number",
  vault.folder_of({ number = 0, name = 'Alpha' }) == '00 - Alpha',
  vault.folder_of({ number = 0, name = 'Alpha' }))
check("and does not truncate a wide one",
  vault.folder_of({ number = 100, name = 'Alpha' }) == '100 - Alpha')

local n, nm = vault.parse_folder('01 - Beta')
check("parse_folder inverts it", n == 1 and nm == 'Beta', tostring(n) .. '/' .. tostring(nm))
check("a folder with no number is not a vault folder", vault.parse_folder('Unregistered') == nil)
check("nor is one with no separator",                  vault.parse_folder('00 Alpha') == nil)
check("nor is templates",                              vault.parse_folder('templates') == nil)

print("\n== the registry round-trips through disk ==")

local ok_save, err_save = vault.save({
  version = 1,
  vaults  = { { number = 1, name = 'Beta' }, { number = 0, name = 'Alpha' } },
  history = { { at = '2026-07-27T13:19:00Z', event = 'rename',
                number = 1, from = 'Old', to = 'Beta' } },
})
check("save() succeeds", ok_save, err_save)
check("vaults.json now exists", vim.fn.filereadable(registry) == 1)
check("and no temp file was left behind", vim.fn.filereadable(registry .. '.tmp') == 0)

local written = vim.fn.readfile(registry)
check("it is written one vault per line, for a human to read",
  #written >= 8, '#lines=' .. #written)

local listed = vault.list()
check("list() returns both vaults", #listed == 2, '#=' .. #listed)
check("ordered by number", listed[1] and listed[1].number == 0 and listed[2].number == 1)
check("get() is case-insensitive", (vault.get('alpha') or {}).number == 0)
check("by_number() finds Beta",    (vault.by_number(1) or {}).name == 'Beta')
check("path_of builds the folder path",
  same(vault.path_of(vault.get('Beta')), beta), vault.path_of(vault.get('Beta')))
check("history() survived the write", #vault.history() == 1, #vault.history())
check("and kept its fields", (vault.history()[1] or {}).from == 'Old')

-- The entries are copies: a caller that mutates one must not corrupt the cache.
listed[1].name = 'Mutated'
check("a mutated result does not reach the registry", vault.get('Alpha') ~= nil)

print("\n== of(): a path belongs to a vault by prefix, compared plainly ==")

check("a note inside Alpha",
  (vault.of(alpha .. '/03-Consolidated/9601_note_a.md') or {}).name == 'Alpha')
check("a note inside Beta",
  (vault.of(beta .. '/03-Consolidated/x.md') or {}).name == 'Beta')
check("the vault folder itself", (vault.of(alpha) or {}).name == 'Alpha')
check("a native-separator path is answered too",
  (vault.of(utils.normalize(alpha .. '/03-Consolidated/x.md')) or {}).name == 'Alpha')

-- The decisive one, verified against the interpreter rather than assumed:
-- "00 - Alpha" used as a Lua pattern reads as "00", then any number of spaces,
-- then " Alpha". It matches the folder "00 Alpha" — a different directory no
-- vault claims — and fails to match "00 - Alpha" itself. Both answers wrong.
check("the folder '00 Alpha' belongs to no vault (the hyphen is not a quantifier)",
  vault.of(decoy .. '/03-Consolidated/x.md') == nil,
  vim.inspect(vault.of(decoy .. '/03-Consolidated/x.md')))
check("a sibling prefix does not count either",
  vault.of(nvroot .. '/00 - AlphaOther/x.md') == nil)
check("a path outside the Note-Vault belongs to nothing",
  vault.of(outside .. '/x.md') == nil)
check("and Unregistered is not a vault", vault.of(nvroot .. '/Unregistered/Old/x.md') == nil)

check("active() is the vault the root sits in", (vault.active() or {}).name == 'Alpha')

print("\n== the write is careful with the one file nothing can rebuild ==")

vault.save({ version = 1, vaults = { { number = 0, name = 'Alpha' } }, history = {} })
check("the previous registry was kept as .bak", vim.fn.filereadable(registry .. '.bak') == 1)
check("the .bak still holds the vault that was dropped",
  table.concat(vim.fn.readfile(registry .. '.bak'), '\n'):find('Beta', 1, true) ~= nil)
check("and the live registry no longer does",
  table.concat(vim.fn.readfile(registry), '\n'):find('Beta', 1, true) == nil)

print("  (the two errors below are expected — they are the refusals being asserted)")
local before = table.concat(vim.fn.readfile(registry), '\n')

local ok_dup = vault.save({ version = 1, history = {},
  vaults = { { number = 0, name = 'Alpha' }, { number = 0, name = 'Beta' } } })
check("a duplicate number is refused", ok_dup == false)

local ok_case = vault.save({ version = 1, history = {},
  vaults = { { number = 0, name = 'Alpha' }, { number = 1, name = 'alpha' } } })
check("a name differing only in case is refused", ok_case == false)

check("and neither refusal touched the file",
  table.concat(vim.fn.readfile(registry), '\n') == before)

print("\n== a registry edited outside Neovim is noticed ==")

check("the cache is warm", #vault.list() == 1, #vault.list())
vim.fn.writefile({
  '{', '  "version": 1,', '  "vaults": [',
  '    { "number": 0, "name": "Alpha" },',
  '    { "number": 7, "name": "GammaWrittenByHand" }',
  '  ],', '  "history": []', '}',
}, registry)
local after = vault.list()
check("a hand edit is picked up without an explicit invalidate", #after == 2, '#=' .. #after)
check("and the new vault resolves", (vault.by_number(7) or {}).name == 'GammaWrittenByHand')

print("\n== vaults_path names the directory outright ==")

-- A root that is nobody's sibling, pointed at the registry explicitly. This is
-- the shape the startup selection in Ph3 needs: the registry is reachable
-- without the root having to sit next to it.
pkm.setup({ root_path = outside, vaults_path = nvroot })
check("the configured directory wins over the derivation",
  same(vault.vaults_root(), nvroot), vault.vaults_root())
check("the registry is still found", #vault.list() == 2, '#=' .. #vault.list())
check("but the root is in no vault, and active() says so", vault.active() == nil)

print("\n== a root with no registry anywhere behaves as it always has ==")

-- The regression this phase most has to avoid: 29 test files and min_init pass
-- root_path alone, and none of them may start requiring a registry.
local bare = vim.fn.tempname() .. '/Solo'
vim.fn.mkdir(bare .. '/03-Consolidated', 'p')
pkm.setup({ root_path = bare })

check("vaults_root still answers something",     vault.vaults_root() ~= nil)
check("list() is empty",                         #vault.list() == 0, #vault.list())
check("of() answers nil for a note in the root", vault.of(bare .. '/03-Consolidated/x.md') == nil)
check("active() answers nil",                    vault.active() == nil)
check("history() is empty",                      #vault.history() == 0)

local index = require('pkm.index')
index.rebuild()
check("and the index still builds over that root", type(index.get_all()) == 'table')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
