-- test/test_vault_paths.lua
-- The root may contain spaces, hyphens and digits.
--
-- The vaults moved under `P:\Note-Vault\` on 27/7/2026 and are named
-- `00 - NotesTeste` and `01 - Vitruvia` — so every path the plugin builds now
-- carries two spaces and a hyphen. That is not cosmetic: a space breaks an
-- unquoted shell argument, a hyphen is a Lua pattern metacharacter, and a
-- leading digit is nothing at all until someone writes `%d` where they meant a
-- literal. This file pins the property so a later refactor cannot quietly
-- reintroduce a pattern match where a plain find belongs.
--
-- Self-contained: it builds its own root in a temp directory with the same
-- shape, so it proves the property rather than the state of one machine.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_vault_paths.lua" -c "qa!"

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

-- A root shaped like the real ones: a parent folder, then "NN - Name".
local parent = vim.fn.tempname()
local root   = parent .. '/Note-Vault/00 - Test Vault'
vim.fn.mkdir(root, 'p')

-- Re-point the plugin at it. This is also the shape a vault switch will take,
-- so anything that breaks here breaks v1.11.0 Ph1.
pkm.setup({ root_path = root })

local consolidated = pkm.config.folders.consolidated
local dir          = utils.join(pkm.config.root_path, consolidated)
vim.fn.mkdir(dir, 'p')

print("== the root survives resolution ==")

check("root_path kept the spaces",
  pkm.config.root_path:find(' - Test Vault', 1, true) ~= nil, pkm.config.root_path)
check("and vim.fn.expand did not mangle it",
  vim.fn.isdirectory(pkm.config.root_path) == 1, pkm.config.root_path)

---@param name string
---@param tags string[]
---@return string
local function make_note(name, tags)
  local lines = { '---', 'title: ' .. name, 'author: ""' }
  if #tags == 0 then
    lines[#lines + 1] = 'tags: []'
  else
    lines[#lines + 1] = 'tags:'
    for _, t in ipairs(tags) do lines[#lines + 1] = '  - ' .. t end
  end
  vim.list_extend(lines, {
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo de ' .. name,
  })
  local path = utils.join(dir, name)
  vim.fn.writefile(lines, path)
  return path
end

local n1 = make_note('9501_note_espaco_um.md',  { 'espacotag' })
local n2 = make_note('9502_note_espaco_dois.md', {})

print("\n== glob and libuv agree on a path with spaces ==")

-- The two spellings that appear in the codebase, plus an independent count
-- that goes through no pattern at all. A glob that silently returned nothing
-- would leave note numbering to restart at 1 and overwrite existing notes.
local g_sep = vim.fn.glob(dir .. utils.sep .. '*.md', false, true)
local g_sla = vim.fn.glob(dir .. '/*.md', false, true)

local uv, n_uv = (vim.uv or vim.loop), 0
local req = uv.fs_scandir(dir)
if req then
  while true do
    local nm = uv.fs_scandir_next(req)
    if not nm then break end
    if nm:match('%.md$') then n_uv = n_uv + 1 end
  end
end

check("glob with the native separator finds both notes", #g_sep == 2, '#=' .. #g_sep)
check("glob with '/' finds both notes",                  #g_sla == 2, '#=' .. #g_sla)
check("and libuv, which uses no pattern, agrees",        n_uv == 2,   '#=' .. n_uv)

print("\n== the index and the membership tests ==")

local index = require('pkm.index')
index.rebuild()
local entries = index.get_all()
check("the index found the notes under the spaced root", #entries == 2, '#=' .. #entries)

-- in_root is a plain find, not a pattern: a hyphen in the root would be a
-- character-class range if anyone reached for `match`.
vim.cmd('edit ' .. vim.fn.fnameescape(n1))
check("in_root recognises the spaced root (modeline guard fired)",
  vim.bo.modeline == false, tostring(vim.bo.modeline))

print("\n== views: the sidecar lives inside the spaced root ==")

local views = require('pkm.views')
check("a view saves into the spaced root", views.save('__spaced_view', 'tag:espacotag'))
check("views.json was written where the root is",
  vim.fn.filereadable(utils.join(pkm.config.root_path, 'views.json')) == 1)
local matched = views.match_all('__spaced_view')
check("match_all resolves it", #matched == 1, '#=' .. #matched)
check("and the matched path is the right note",
  utils.normalize(matched[1] or ''):lower() == utils.normalize(n1):lower(), matched[1])

print("\n== trash: round trip through a spaced root ==")

local trash = require('pkm.trash')
check("trash_dir sits inside the spaced root",
  trash.trash_dir():find(' - Test Vault', 1, true) ~= nil, trash.trash_dir())
check("trash_note succeeds", trash.trash_note(n2))

local entry
for _, e in ipairs(trash.list()) do
  if e.filename == '9502_note_espaco_dois.md' then entry = e end
end
check("the entry exists", entry ~= nil)
if entry then
  check("its stored location is relative, so the spaces never reach the manifest",
    entry.original_path == consolidated .. '/9502_note_espaco_dois.md',
    entry.original_path)
  check("resolve_original rebuilds the spaced absolute path",
    utils.normalize(trash.resolve_original(entry)):lower() == utils.normalize(n2):lower(),
    trash.resolve_original(entry))
  check("restore_note puts it back", trash.restore_note(entry))
  check("and the file is there again", vim.fn.filereadable(n2) == 1)
end

-- An entry from the pre-move layout, which is what every real manifest still
-- holds: it must re-root into the spaced vault, not the vault it names.
local legacy = {
  filename      = 'x.md',
  original_path = 'P:\\NotesTeste\\' .. consolidated .. '\\9503_note_legado.md',
}
local re = trash.resolve_original(legacy)
check("a pre-move absolute entry re-roots into the spaced vault",
  re:find(' - Test Vault', 1, true) ~= nil, re)
check("and no longer names the old vault",
  re:gsub('\\', '/'):lower():find('/notesteste/', 1, true) == nil, re)

print("\n== citations scan the spaced folders ==")

local citations = require('pkm.citations')
local items, n_items = citations.get_citable_items_map(), 0
for _ in pairs(items) do n_items = n_items + 1 end
check("get_citable_items_map found the notes", n_items >= 2, 'n=' .. n_items)

views.delete('__spaced_view')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
