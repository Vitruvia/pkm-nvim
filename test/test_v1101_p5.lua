-- test/test_v1101_p5.lua
-- Tests for v1.10.1 Phase 5: emptying the trash no longer opens a file that,
-- by definition, is not there.
--
-- `cleanup_deleted_note()` took one path and used it for two different things:
-- the note's identity (read off the filename) and the place its text can be
-- read (to learn what it cited). For a note deleted in place those coincide.
-- For a *trashed* note they do not — it has already left its original path and
-- its content sits in `.pkm-trash/`. So `vim.fn.readfile()` threw E484 and took
-- the whole operation down, including step 2, the part that strips references
-- *to* the deleted note. `trash.empty()` aborted on its first entry with the
-- manifest and the trashed files untouched, and `purge_old()` — which runs by
-- itself five seconds after setup when max_age_days > 0 — failed in the
-- background the same way.
--
-- The assertion that separates "guarded so it stops erroring" from "fixed so
-- it works" is the backlink one: the cited note must actually lose its
-- backlink, which requires the frontmatter to have been *read*, from the copy.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1101_p5.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. detail) or ""))
    failures = failures + 1
  end
end

local pkm       = require('pkm')
local utils     = require('pkm.utils')
local trash     = require('pkm.trash')
local citations = require('pkm.citations')
local yaml      = require('pkm.yaml')

local dir = utils.join(pkm.config.root_path, pkm.config.folders.consolidated)
vim.fn.mkdir(dir, 'p')

---@param name string
---@param body string
---@return string path
local function make_note(name, body)
  local path = utils.join(dir, name)
  vim.fn.writefile({
    '---', 'title: ' .. name, 'author: ""', 'tags: []',
    'created_on: "2026-07-27T10:00:00"', 'last_updated_on: "2026-07-27T10:00:00"',
    'cites:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    'cited_by:', '  notes: []', '  bib: []', '  journal: []', '  scratch: []',
    '---', '', body,
  }, path)
  return path
end

---@param path string
---@return table|nil
local function frontmatter(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  return yaml.parse_frontmatter(lines)
end

---@param path string  note whose cited_by is inspected
---@return integer
local function cited_by_count(path)
  local fm = frontmatter(path)
  if not (fm and fm.cited_by and fm.cited_by.notes) then return 0 end
  return #fm.cited_by.notes
end

-- =============================================================================
-- Fixture: 8101 cites 8102, built by the plugin's own sync, not by hand
-- =============================================================================

print("== fixture ==")

local alvo   = make_note('8102_note_p5_alvo.md', 'sou citada')
local citada = make_note('8101_note_p5_citante.md', 'eu cito note[8102] aqui')

citations.update_references(citada)

check("control: the citing note records the citation",
  (function()
    local fm = frontmatter(citada)
    return fm and fm.cites and fm.cites.notes and #fm.cites.notes == 1
  end)(),
  'cites.notes = ' .. tostring((function()
    local fm = frontmatter(citada)
    return fm and fm.cites and fm.cites.notes and #fm.cites.notes or 'nil'
  end)()))

check("control: and the cited note carries the backlink",
  cited_by_count(alvo) == 1, 'cited_by.notes = ' .. cited_by_count(alvo))

-- =============================================================================
-- empty(): it completes, and the backlink is actually stripped
-- =============================================================================

print("\n== trash.empty() ==")

check("the citing note is trashed", trash.trash_note(citada))
check("and it really is gone from its original path",
  vim.fn.filereadable(citada) == 0)
check("the manifest holds it", #trash.list() >= 1)

local ok_empty, err = pcall(trash.empty)
check("empty() does not throw", ok_empty, tostring(err))
check("and it reports having emptied the manifest", #trash.list() == 0)

local trash_leftovers = vim.fn.glob(utils.join(trash.trash_dir(), '8101_*.md'))
check("the trashed file is gone from .pkm-trash", trash_leftovers == '',
  trash_leftovers)

-- The one that matters: this only happens if the frontmatter was read, and it
-- could only be read from the copy in the trash.
check("the cited note lost its backlink — the cleanup actually ran",
  cited_by_count(alvo) == 0, 'cited_by.notes = ' .. cited_by_count(alvo))

-- =============================================================================
-- The same for purge_old(), which runs unattended
-- =============================================================================

print("\n== trash.purge_old() ==")

local alvo2   = make_note('8202_note_p5_alvo.md', 'sou citada tambem')
local citada2 = make_note('8201_note_p5_citante.md', 'eu cito note[8202] aqui')
citations.update_references(citada2)
check("control: the second fixture has its backlink",
  cited_by_count(alvo2) == 1, 'cited_by.notes = ' .. cited_by_count(alvo2))

check("the second citing note is trashed", trash.trash_note(citada2))

-- Backdate the entry past any plausible max_age_days, and give purge_old one.
local manifest_file = utils.join(trash.trash_dir(), 'manifest.json')
local m = vim.fn.json_decode(table.concat(vim.fn.readfile(manifest_file), '\n'))
for _, e in ipairs(m) do
  e.deleted_timestamp = os.time() - (400 * 86400)
  e.deleted_at        = '2025-06-01T00:00:00Z'
end
vim.fn.writefile({ vim.fn.json_encode(m) }, manifest_file)

pkm.config.trash = pkm.config.trash or {}
local prev_age = pkm.config.trash.max_age_days
pkm.config.trash.max_age_days = 30

local ok_purge, perr = pcall(trash.purge_old)
check("purge_old() does not throw", ok_purge, tostring(perr))
check("and the aged entry is gone from the manifest", #trash.list() == 0)
check("the second cited note lost its backlink too",
  cited_by_count(alvo2) == 0, 'cited_by.notes = ' .. cited_by_count(alvo2))

pkm.config.trash.max_age_days = prev_age

-- =============================================================================
-- When the text cannot be read at all, step 2 must still run
-- =============================================================================

print("\n== an unreadable copy no longer aborts the whole operation ==")

local ok_missing = pcall(citations.cleanup_deleted_note,
  utils.join(dir, '8301_note_p5_inexistente.md'),
  utils.join(dir, '8301_note_p5_tambem_inexistente.md'))
check("cleanup_deleted_note survives an unreadable content path", ok_missing)

-- And the default still works for the in-place delete path, which passes one
-- argument and a file that does exist (pkm.init's permanent-delete branch).
local presente = make_note('8401_note_p5_presente.md', 'sem citacoes')
local ok_default = pcall(citations.cleanup_deleted_note, presente)
check("and a single readable argument still works", ok_default)

-- =============================================================================

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
