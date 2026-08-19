-- test/test_v1800_p1.lua
-- v1.80.0 — the view-lifecycle API (rename / reparent / delete) plus the
-- silent-empty composition guard (finding D1) and the tree-shaped structure()
-- read (D6). All headless: the writes prompt for nothing and open no buffer.
--
-- The load-bearing case is D1: a subview AND-composes its parent, so a child
-- whose own filter matches notes can resolve to an EMPTY set under a parent that
-- excludes them. save_subproject / reparent must catch that and return a
-- non-blocking warning — the footgun that silently emptied `Guias de Estudo`
-- (21 → 0) during the 2026-08-19 gestor reorg of vault 01.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1800_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
vim.fn.mkdir(root .. '/02-Journal', 'p')
vim.fn.mkdir(root .. '/01-Scratchpad', 'p')
pkm.setup({ root_path = root })

local api   = require('pkm.api')
local views = require('pkm.views')

local function tree_entry(name)
  for _, e in ipairs(views.tree()) do
    if e.name == name then return e end
  end
  return nil
end

-- Disjoint tags, no note carries two of them — so an AND across two of them is
-- always empty (the composition trap), while each on its own is non-empty.
local n_guia = api.create('note', { title = 'Guia one',  by = 'claude', tags = { 'guia' } })
local n_meta = api.create('note', { title = 'Meta one',  by = 'claude', tags = { 'meta' } })
local n_afo  = api.create('note', { title = 'AFO one',   by = 'claude', tags = { 'afo' } })
check("three tagged notes created", n_guia.ok and n_meta.ok and n_afo.ok,
  vim.inspect({ n_guia, n_meta, n_afo }))

print("\n== D1: save_subproject warns when the parent empties the child ==")
check("top-level parent Meta saved", api.save_view('Meta', 'tag:meta').ok)
local sp_empty = api.save_subproject('Guias', 'Meta', 'tag:guia')
check("save_subproject still succeeds (warning never blocks)", sp_empty.ok, vim.inspect(sp_empty))
check("save_subproject WARNS: child matches alone but 0 under the parent",
  type(sp_empty.warning) == 'string' and sp_empty.warning:find('0 under parent', 1, true) ~= nil,
  vim.inspect(sp_empty))
check("and the subview really does resolve to nothing",
  #views.match_all('Guias') == 0, vim.inspect(views.match_all('Guias')))

print("\n== D1: a superset parent composes cleanly, no warning ==")
check("superset parent MetaU saved", api.save_view('MetaU', 'tag:meta OR tag:guia').ok)
local sp_ok = api.save_subproject('GuiasU', 'MetaU', 'tag:guia')
check("save_subproject under a superset parent returns no warning",
  sp_ok.ok and sp_ok.warning == nil, vim.inspect(sp_ok))
check("the subview keeps its one member", #views.match_all('GuiasU') == 1,
  vim.inspect(views.match_all('GuiasU')))

print("\n== reparent: explicit move, cycle guard, and the same empty warning ==")
check("Disc (afo superset) saved", api.save_view('Disc', 'tag:afo OR tag:guia').ok)
check("AFO subview under Disc saved (non-empty)",
  api.save_subproject('AFO', 'Disc', 'tag:afo').ok)
check("AFO resolves to its one note under Disc", #views.match_all('AFO') == 1)

local rp = api.reparent_view('AFO', 'Meta')          -- Meta = tag:meta, excludes afo
check("reparent_view moves and returns ok", rp.ok, vim.inspect(rp))
check("reparent_view surfaces the empty-composition warning",
  type(rp.warning) == 'string' and rp.warning:find('0 under parent', 1, true) ~= nil,
  vim.inspect(rp))
check("AFO's parent field actually changed to Meta",
  (tree_entry('AFO') or {}).parent == 'Meta', vim.inspect(tree_entry('AFO')))

-- Cycle guard over a chain P > C > G: moving C under its own descendant G fails.
check("chain P saved",              api.save_view('P', 'tag:afo').ok)
check("chain C under P saved",      api.save_subproject('C', 'P', 'tag:afo').ok)
check("chain G under C saved",      api.save_subproject('G', 'C', 'tag:afo').ok)
local cyc = api.reparent_view('C', 'G')
check("reparent onto a descendant is refused (cycle)",
  not cyc.ok and tostring(cyc.error):find('cycle', 1, true) ~= nil, vim.inspect(cyc))
check("reparent onto a missing parent is refused",
  not api.reparent_view('C', 'NoSuchView').ok)
check("reparent of a non-subproject (top-level P) is refused",
  not api.reparent_view('P', 'Meta').ok)

print("\n== rename_view re-points children (never orphans a subtree) ==")
local rnv = api.rename_view('P', 'P-renamed')
check("rename_view returns ok", rnv.ok, vim.inspect(rnv))
check("the child C now names the new parent (re-pointed, not orphaned)",
  (tree_entry('C') or {}).parent == 'P-renamed', vim.inspect(tree_entry('C')))
check("renaming onto an existing name is refused",
  not api.rename_view('C', 'Meta').ok)

print("\n== tree() shape and structure() carrying it ==")
local g = tree_entry('G')
check("tree() gives G depth 2 under C, leaf", g and g.depth == 2 and g.parent == 'C'
  and g.has_children == false, vim.inspect(g))
check("tree() marks C as having children", (tree_entry('C') or {}).has_children == true)
local st = api.structure()
check("structure() returns ok with a note total", st.ok and st.total_notes >= 3, vim.inspect(st.total_notes))
check("structure() view rows carry depth and parent", (function()
  for _, v in ipairs(st.views) do
    if v.name == 'G' then return v.depth == 2 and v.parent == 'C' end
  end
  return false
end)(), vim.inspect(st.views))

print("\n== delete_view: leaf ok, unknown refused ==")
check("delete_view removes a leaf", api.delete_view('G').ok)
check("the deleted view is gone", tree_entry('G') == nil)
check("delete_view on an unknown name is refused", not api.delete_view('NoSuchView').ok)

print("\n== D5: save_subproject validates a mixed field+any filter (still saves) ==")
local mix = api.save_subproject('Mixed', 'Meta', 'tag:meta OR "loose"')
check("a mixed field+free-text subview still saves (warned, not blocked)", mix.ok, vim.inspect(mix))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
