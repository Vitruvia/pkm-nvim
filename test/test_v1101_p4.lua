-- test/test_v1101_p4.lua
-- Tests for v1.10.1 Phase 4: the trash remembers a place in the vault, not a
-- place on the disk.
--
-- A manifest entry used to record an absolute path, which tied the trash to
-- one directory. Copy a vault and the copy's manifest still points at the
-- original, so restoring from the copy writes into the vault it was copied
-- from. `NotesTeste` was in exactly that state: entries reading
-- `P:\Notes\03-Consolidated\…` with the files sitting in its own `.pkm-trash/`.
--
-- The assertion that matters is the third block. The first two would pass with
-- the bug still in place — a path stored and read back in the same session
-- round-trips fine either way — so they are checks that the fix broke nothing,
-- not evidence that it works. Only a path recorded under a *different* root
-- tells the two behaviours apart.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1101_p4.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local utils = require('pkm.utils')
local trash = require('pkm.trash')

local root         = pkm.config.root_path
local consolidated = pkm.config.folders.consolidated
local dir          = utils.join(root, consolidated)
vim.fn.mkdir(dir, 'p')

---@param name string
---@return string path
local function make_note(name)
  local path = utils.join(dir, name)
  vim.fn.writefile({
    '---', 'title: ' .. name, 'author: ""', 'tags: []',
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', 'corpo de ' .. name,
  }, path)
  return path
end

local function slashed(p) return (p:gsub('\\', '/')) end

-- =============================================================================
-- What gets written: a place in the vault, not a place on the disk
-- =============================================================================

print("== the stored form ==")

local p1 = make_note('7001_note_p4_guardada.md')
check("control: the note exists before trashing", vim.fn.filereadable(p1) == 1)
check("trash_note succeeds", trash.trash_note(p1))

local entry
for _, e in ipairs(trash.list()) do
  if e.filename == '7001_note_p4_guardada.md' then entry = e end
end

check("the entry is in the manifest", entry ~= nil)
if entry then
  check("the recorded location is relative — no drive letter, no leading slash",
    entry.original_path:match('^%a:') == nil and entry.original_path:sub(1, 1) ~= '/',
    entry.original_path)
  check("it is stored with forward slashes, so a manifest travels",
    entry.original_path:find('\\', 1, true) == nil, entry.original_path)
  check("and it still names the folder and the file",
    entry.original_path == consolidated .. '/7001_note_p4_guardada.md',
    entry.original_path)
  check("resolve_original puts it back where it was",
    slashed(trash.resolve_original(entry)):lower() == slashed(p1):lower(),
    tostring(trash.resolve_original(entry)))
end

-- =============================================================================
-- The round trip still works (this would pass with the bug, too)
-- =============================================================================

print("\n== restore, same session ==")

check("restore_note succeeds", entry ~= nil and trash.restore_note(entry))
check("the note is back at its original path", vim.fn.filereadable(p1) == 1)
check("and it left the manifest", (function()
  for _, e in ipairs(trash.list()) do
    if e.filename == '7001_note_p4_guardada.md' then return false end
  end
  return true
end)())

-- =============================================================================
-- The one that tells the behaviours apart: an entry from another vault
-- =============================================================================

print("\n== a legacy entry recorded under a different root ==")

-- Exactly the shape found in NotesTeste's manifest: an absolute path into a
-- vault this session is not using. Under the old code this *is* the restore
-- target, and the note lands outside the current root.
local foreign = {
  filename      = '7002_note_p4_estrangeira.md',
  original_path = 'P:\\OutroVault\\' .. consolidated .. '\\7002_note_p4_estrangeira.md',
  title         = 'estrangeira',
}

local resolved = trash.resolve_original(foreign)
check("it resolves to somewhere inside the current root",
  slashed(resolved):lower():sub(1, #slashed(root)) == slashed(root):lower(),
  tostring(resolved))
check("it does NOT resolve into the vault the entry names",
  slashed(resolved):lower():find('/outrovault/', 1, true) == nil, tostring(resolved))
check("the folder and filename survive the re-rooting",
  slashed(resolved) == slashed(utils.join(utils.join(root, consolidated),
    '7002_note_p4_estrangeira.md')),
  tostring(resolved))

-- A path with no folder this vault recognises still lands inside the root,
-- because writing outside it is the one thing restore must never do.
local rootless = {
  filename      = '7003_note_p4_sem_pasta.md',
  original_path = 'P:\\OutroVault\\7003_note_p4_sem_pasta.md',
}
local r2 = trash.resolve_original(rootless)
check("an unrecognised layout still resolves inside the root",
  slashed(r2):lower():sub(1, #slashed(root)) == slashed(root):lower(), tostring(r2))
check("and it falls back to the consolidated folder",
  slashed(r2) == slashed(utils.join(utils.join(root, consolidated),
    '7003_note_p4_sem_pasta.md')), tostring(r2))

-- An absolute path that is already under this root is left alone.
local native = {
  filename      = '7004_note_p4_nativa.md',
  original_path = utils.join(dir, '7004_note_p4_nativa.md'),
}
check("an absolute path already under the root is taken as it stands",
  slashed(trash.resolve_original(native)):lower()
    == slashed(native.original_path):lower(),
  tostring(trash.resolve_original(native)))

check("an entry recording nothing resolves to nil",
  trash.resolve_original({ filename = 'x' }) == nil)

-- =============================================================================
-- Restoring a foreign entry writes inside this vault, not the named one
-- =============================================================================

print("\n== restoring a foreign entry ==")

local trash_dir = trash.trash_dir()
vim.fn.mkdir(trash_dir, 'p')
vim.fn.writefile({ '---', 'title: estrangeira', '---', '', 'corpo' },
  utils.join(trash_dir, '7002_note_p4_estrangeira.md'))

-- Put the foreign entry in the manifest the way an older version would have.
local manifest_file = utils.join(trash_dir, 'manifest.json')
local current = vim.fn.filereadable(manifest_file) == 1
  and vim.fn.json_decode(table.concat(vim.fn.readfile(manifest_file), '\n')) or {}
if type(current) ~= 'table' then current = {} end
current[#current + 1] = {
  filename          = foreign.filename,
  original_path     = foreign.original_path,
  title             = foreign.title,
  deleted_at        = '2026-07-27T10:00:00Z',
  deleted_timestamp = os.time(),
}
vim.fn.writefile({ vim.fn.json_encode(current) }, manifest_file)

local reloaded
for _, e in ipairs(trash.list()) do
  if e.filename == foreign.filename then reloaded = e end
end
check("the foreign entry reloads from disk", reloaded ~= nil,
  reloaded and reloaded.original_path or 'not found')

if reloaded then
  check("restore_note succeeds on it", trash.restore_note(reloaded))
  local landed = utils.join(dir, '7002_note_p4_estrangeira.md')
  check("the file landed inside the current root",
    vim.fn.filereadable(landed) == 1, landed)
  check("and nothing was written to the vault the entry named",
    vim.fn.filereadable('P:\\OutroVault\\' .. consolidated
      .. '\\7002_note_p4_estrangeira.md') == 0)
end

-- =============================================================================

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
