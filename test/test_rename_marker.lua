-- test/test_rename_marker.lua
-- Gestor request #1 — rename must preserve the By<Author>_ authorship marker.
--
-- notes.rename_note_at (the headless twin behind pkm.api.rename) rebuilt a
-- consolidated stem as NNNN_type_<sanitize(new_name)>, replacing EVERYTHING
-- after the type prefix — so renaming 0009_bib_ByClaude_Foo to "Bar" produced
-- 0009_bib_Bar and dropped ByClaude. That silently broke agent_authored()
-- (the note then reads as human-written) and the agent delete guard. The fix
-- treats the marker as identity carried in the name, like the number/type
-- prefix: new_name is the bare human name and the marker is re-attached.
--
-- This proves, headlessly: a marked note keeps its marker across api.rename;
-- authored_by still reports the agent afterwards; and an UNmarked (human) note
-- never gains a spurious marker.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_rename_marker.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function stem_of(path) return vim.fn.fnamemodify(path, ':t:r') end

local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

print("== a marked (agent-authored) note keeps its marker across rename ==")
local marked = api.create('note', { title = 'Foo', by = 'claude' })
check("marked note created", marked.ok, vim.inspect(marked))
check("the created stem carries the ByClaude_ marker",
  stem_of(marked.path):match('^%d+_note_ByClaude_'), stem_of(marked.path))
check("authored_by reports the agent before rename",
  api.authored_by(marked.path) == 'Claude', tostring(api.authored_by(marked.path)))

local r = api.rename(marked.path, 'Bar Baz')
check("api.rename returned ok", r.ok, vim.inspect(r))
check("the new stem STILL carries the ByClaude_ marker",
  r.path and stem_of(r.path):match('^%d+_note_ByClaude_'), r.path and stem_of(r.path))
check("the new stem carries the new bare name after the marker",
  r.path and stem_of(r.path):match('ByClaude_Bar_Baz$'), r.path and stem_of(r.path))
check("authored_by STILL reports the agent after rename",
  r.path and api.authored_by(r.path) == 'Claude',
  r.path and tostring(api.authored_by(r.path)))

print("\n== the caller must NOT restate the marker (no double marker) ==")
local marked2 = api.create('note', { title = 'One', by = 'claude' })
-- The old workaround was to include the marker in new_name; the fix makes that
-- unnecessary, and a bare name must not stack a second marker.
local r2 = api.rename(marked2.path, 'Two')
check("bare rename produces exactly one marker",
  r2.path and stem_of(r2.path):match('^%d+_note_ByClaude_Two$'),
  r2.path and stem_of(r2.path))

print("\n== an unmarked (human) note never gains a spurious marker ==")
local human = api.create('note', { title = 'Plain' })
check("human note created without a marker",
  human.ok and not stem_of(human.path):match('_By%u'), stem_of(human.path))
check("authored_by is nil before rename", api.authored_by(human.path) == nil)

local r3 = api.rename(human.path, 'Renamed Plain')
check("api.rename returned ok (human note)", r3.ok, vim.inspect(r3))
check("the renamed human stem has NO marker",
  r3.path and not stem_of(r3.path):match('_By%u'), r3.path and stem_of(r3.path))
check("the renamed human stem is the plain new name",
  r3.path and stem_of(r3.path):match('^%d+_note_Renamed_Plain$'),
  r3.path and stem_of(r3.path))
check("authored_by is still nil after rename", r3.path and api.authored_by(r3.path) == nil)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
