-- test/test_v1800_p1.lua
-- v1.81.0 — the CONTAINMENT model for nested views, plus the view-lifecycle API
-- (rename / reparent / delete) and the tree-shaped structure() read.
--
-- v1.80.0 briefly shipped an AND-composition model where nesting a view under a
-- parent that excluded its notes emptied it (and warned). v1.81.0 REPLACES that:
-- a subview keeps its OWN filter as its membership, and a parent matches its own
-- filter OR the union of its children — so a parent CONTAINS its children and
-- nesting never narrows or empties a view. The empty-composition warning is gone
-- by construction; this test proves the new invariant (and that the warning field
-- no longer appears).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1800_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
vim.fn.mkdir(root .. '/02-Journal', 'p')
vim.fn.mkdir(root .. '/01-Scratchpad', 'p')
pkm.setup({ root_path = root })

local api   = require('pkm.api')
local views = require('pkm.views')

local function count(name) return #api.view_members(name) end
local function tree_entry(name)
  for _, e in ipairs(views.tree()) do if e.name == name then return e end end
  return nil
end

-- Disjoint tags: no note carries two of them, so a parent that "excludes" a
-- child under the OLD model is exactly where the NEW model must NOT empty it.
for i = 1, 3 do api.create('note', { title = 'Guia ' .. i, by = 'claude', tags = { 'guia' } }) end
api.create('note', { title = 'Meta one', by = 'claude', tags = { 'meta' } })
api.create('note', { title = 'AFO one',  by = 'claude', tags = { 'afo' } })

print("\n== nesting a view under an EXCLUDING parent no longer empties it ==")
check("Meta (tag:meta) matches its one note", api.save_view('Meta', 'tag:meta').ok and count('Meta') == 1)
local sp = api.save_subproject('Guias', 'Meta', 'tag:guia')
check("save_subproject returns ok with NO warning field", sp.ok and sp.warning == nil, vim.inspect(sp))
check("the subview keeps ALL its own members (3), not narrowed to 0", count('Guias') == 3,
  vim.inspect(api.view_members('Guias')))
check("the parent now CONTAINS the child: Meta = meta OR guia = 4", count('Meta') == 4,
  string.format("got %d", count('Meta')))

print("\n== reparent is a pure move: child keeps members, parents roll up correctly ==")
check("Other (tag:afo) has its one note", api.save_view('Other', 'tag:afo').ok and count('Other') == 1)
local rp = api.reparent_view('Guias', 'Other')
check("reparent_view returns ok with NO warning field", rp.ok and rp.warning == nil, vim.inspect(rp))
check("Guias STILL has its 3 members after the move", count('Guias') == 3)
check("new parent Other now rolls up Guias: afo OR guia = 4", count('Other') == 4, string.format("got %d", count('Other')))
check("old parent Meta no longer contains Guias: back to 1", count('Meta') == 1, string.format("got %d", count('Meta')))
check("Guias' parent field moved to Other", (tree_entry('Guias') or {}).parent == 'Other')

print("\n== reparent guards: cycle, missing parent, non-subproject ==")
check("chain P/C/G saved", api.save_view('P', 'tag:afo').ok
  and api.save_subproject('C', 'P', 'tag:afo').ok
  and api.save_subproject('G', 'C', 'tag:afo').ok)
local cyc = api.reparent_view('C', 'G')
check("reparent onto a descendant is refused (cycle)",
  not cyc.ok and tostring(cyc.error):find('cycle', 1, true) ~= nil, vim.inspect(cyc))
check("reparent onto a missing parent is refused", not api.reparent_view('C', 'NoSuchView').ok)
check("reparent of a top-level (non-subproject) view is refused", not api.reparent_view('P', 'Meta').ok)

print("\n== rename_view re-points children (never orphans a subtree) ==")
local rnv = api.rename_view('P', 'P-renamed')
check("rename_view returns ok", rnv.ok, vim.inspect(rnv))
check("the child C now names the new parent", (tree_entry('C') or {}).parent == 'P-renamed', vim.inspect(tree_entry('C')))
check("renaming onto an existing name is refused", not api.rename_view('C', 'Meta').ok)

print("\n== tree() / structure() carry the hierarchy ==")
local g = tree_entry('G')
check("tree() gives G depth 2 under C, leaf", g and g.depth == 2 and g.parent == 'C' and g.has_children == false, vim.inspect(g))
check("tree() marks C as having children", (tree_entry('C') or {}).has_children == true)
local st = api.structure()
check("structure() ok with a note total", st.ok and st.total_notes >= 5)
check("structure() view rows carry depth and parent", (function()
  for _, v in ipairs(st.views) do if v.name == 'G' then return v.depth == 2 and v.parent == 'C' end end
  return false
end)(), vim.inspect(st.views))

print("\n== delete_view: leaf ok, unknown refused ==")
check("delete_view removes a leaf", api.delete_view('G').ok)
check("the deleted view is gone", tree_entry('G') == nil)
check("delete_view on an unknown name is refused", not api.delete_view('NoSuchView').ok)

print("\n== D5: save_subproject still validates a mixed field+any filter (saves) ==")
check("a mixed field+free-text subview still saves (warned, not blocked)",
  api.save_subproject('Mixed', 'Meta', 'tag:meta OR "loose"').ok)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
