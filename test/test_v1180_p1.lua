-- test/test_v1180_p1.lua
-- pkm.api — the note-lifecycle writes (rename, changetype, transpose) plus the
-- adjacent gestor wraps (set_membership, save_subproject, rename_tag), driven
-- headless. These wrap the pure seams notes.rename_note_at / changetype_file /
-- convert_file, which prompt for nothing and open no buffer — the property the
-- interactive twins (:PKMNote rename/changetype/promote/transpose) cannot have.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1180_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function readable(path) return path and vim.fn.filereadable(path) == 1 end
local function has(list, value)
  for _, v in ipairs(list or {}) do if v == value then return true end end
  return false
end
local function file_has(path, needle)
  for _, l in ipairs(vim.fn.readfile(path)) do
    if l:find(needle, 1, true) then return true end
  end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
vim.fn.mkdir(root .. '/02-Journal', 'p')
vim.fn.mkdir(root .. '/01-Scratchpad', 'p')
pkm.setup({ root_path = root, projects = { ['Foos'] = 'tag:foo' } })

local api = require('pkm.api')

-- The current buffer must never become the note being operated on: that is the
-- headless guarantee under test.
local function no_buffer_of(path)
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= path
end

print("== rename keeps the number/type prefix and propagates citations ==")
local src = api.create('note', { title = 'Source', by = 'claude' })
local tgt = api.create('note', { title = 'Target', by = 'claude' })
check("two notes created", src.ok and tgt.ok, vim.inspect({ src, tgt }))
check("src cites tgt", api.cite(src.path, tgt.path).ok)
local token = string.format('note[%04d]', tgt.number)

local rn = api.rename(tgt.path, 'Renamed Target')
check("rename returns ok", rn.ok, vim.inspect(rn))
check("the file moved to the new stem", readable(rn.path) and not readable(tgt.path),
  vim.inspect(rn))
check("the number and type prefix are kept",
  rn.filename and rn.filename:find(string.format('%04d_note_', tgt.number), 1, true) ~= nil,
  rn.filename)
check("the human name is sanitised into the stem",
  rn.filename and rn.filename:find('Renamed_Target', 1, true) ~= nil, rn.filename)
check("the citation in src was rewritten to the new stem",
  file_has(src.path, string.format('%04d', tgt.number)), 'expected the new stem token in src')
check("rename opened no buffer", no_buffer_of(rn.path))
check("renaming a missing note is refused",
  not api.rename('/no/such/note.md', 'x').ok)

print("\n== changetype renames the type prefix and propagates ==")
local ct_src = api.create('note', { title = 'Citer', by = 'claude' })
local typed  = api.create('note', { title = 'Typed', by = 'claude' })
check("changetype base notes created", ct_src.ok and typed.ok)
check("citer cites typed", api.cite(ct_src.path, typed.path).ok)

local ct = api.changetype(typed.path, 'agg')
check("changetype returns ok", ct.ok, vim.inspect(ct))
check("the new file carries the agg prefix",
  ct.filename and ct.filename:find(string.format('%04d_agg_', typed.number), 1, true) ~= nil,
  ct.filename)
check("the old note-typed file is gone", not readable(typed.path))
check("the citation in citer followed the type change",
  file_has(ct_src.path, string.format('%04d_agg', typed.number)), 'expected agg stem in citer')
check("an invalid type is refused", not api.changetype(ct.path, 'zzz').ok)
check("changetype on a non-consolidated name is refused (no valid prefix)",
  not api.changetype('/tmp/not-a-note.md', 'agg').ok)

print("\n== transpose moves a note between folders, deleting the original ==")
local mover = api.create('note', { title = 'Mover', by = 'claude',
  body = 'body of the mover' })
check("mover created", mover.ok, vim.inspect(mover))
local tj = api.transpose(mover.path, 'journal')
check("transpose to journal returns ok", tj.ok, vim.inspect(tj))
check("the journal file exists and carries the body",
  readable(tj.path) and file_has(tj.path, 'body of the mover'), vim.inspect(tj))
check("the journal file lives in the journal folder",
  tj.path:find('02-Journal', 1, true) ~= nil, tj.path)
check("the original was deleted (a move, not a copy)",
  tj.original_deleted and not readable(mover.path), vim.inspect(tj))
check("transpose opened no buffer", no_buffer_of(tj.path))

print("\n== transpose can keep the original, and can name a consolidated target ==")
local keep = api.create('note', { title = 'Keep', by = 'claude' })
local kt = api.transpose(keep.path, 'journal', { keep_original = true })
check("keep_original leaves the source in place",
  kt.ok and not kt.original_deleted and readable(keep.path), vim.inspect(kt))

-- A consolidated → consolidated bib transpose, naming the target — the same
-- shape :PKMNote promote produces when it lands on a consolidated note.
local scratch = api.create('note', { title = 'ScratchSeed', by = 'claude' })
local promoted = api.transpose(scratch.path, 'note', { subtype = 'bib', title = 'Promoted Bib' })
check("promote-style transpose to a bib note returns ok", promoted.ok, vim.inspect(promoted))
check("the promoted file carries the bib prefix and the given title",
  promoted.filename and promoted.filename:find('_bib_', 1, true) ~= nil
  and promoted.filename:find('Promoted_Bib', 1, true) ~= nil, promoted.filename)
check("an unknown target type is refused", not api.transpose(keep.path, 'nope').ok)

print("\n== rename_tag renames vault-wide and merges onto an existing tag ==")
local a = api.create('note', { title = 'TagA', by = 'claude', tags = { 'alpha' } })
local b = api.create('note', { title = 'TagB', by = 'claude', tags = { 'beta' } })
check("tag notes created", a.ok and b.ok)
local rt = api.rename_tag('alpha', 'gamma')
check("rename_tag returns ok and reports applied", rt.ok and rt.applied >= 1, vim.inspect(rt))
check("the note now carries the renamed tag", (function()
  local e = api.get(a.path); return e and has(e.tags, 'gamma') and not has(e.tags, 'alpha')
end)(), vim.inspect(api.get(a.path)))
-- Merge: rename gamma onto beta; the two notes coalesce under beta.
local mg = api.rename_tag('gamma', 'beta')
check("merge (rename onto an existing tag) returns ok", mg.ok, vim.inspect(mg))
check("the merged note carries the destination tag", (function()
  local e = api.get(a.path); return e and has(e.tags, 'beta')
end)(), vim.inspect(api.get(a.path)))

print("\n== set_membership and save_subproject write through the view layer ==")
local mem = api.create('note', { title = 'Member', by = 'claude' })
local sm = api.set_membership(mem.path, 'Foos', 'add')
check("set_membership add returns ok (Foos = tag:foo)", sm.ok, vim.inspect(sm))
check("the note gained the defining tag", (function()
  local e = api.get(mem.path); return e and has(e.tags, 'foo')
end)(), vim.inspect(api.get(mem.path)))
local sp = api.save_subproject('FoosBar', 'Foos', 'tag:bar')
check("save_subproject under an existing parent returns ok", sp.ok, vim.inspect(sp))
check("save_subproject under a missing parent is refused",
  not api.save_subproject('Orphan', 'NoSuchParent', 'tag:x').ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
