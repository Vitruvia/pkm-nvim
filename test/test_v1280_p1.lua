-- test/test_v1280_p1.lua
-- pkm.api.related_unlinked — the co-citation signal (v1.28.0). Beyond shared tags
-- and title terms, two notes that cite the SAME source(s) are related even with no
-- shared tag/term. Co-citation counts a candidate's edges that land on a note the
-- focus also links to (weight 2 each). It reads candidate edges, so it is behind
-- opts.graph (default on); graph=false is the cheap index-only pass.
--
-- Graph:  focus cites {S1, S2};  Beta cites {S1};  Gamma cites {S1, S2};
--         Delta cites nothing. Tags/titles are all disjoint, so ONLY co-citation
--         can relate Beta/Gamma to focus.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1280_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function by_title(cands, title)
  for _, c in ipairs(cands or {}) do if c.title == title then return c end end
  return nil
end
local function titles(cands)
  local t = {}
  for _, c in ipairs(cands or {}) do t[#t + 1] = c.title end
  return table.concat(t, ' | ')
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local s1    = api.create('note', { title = 'Source One', by = 'claude' })
local s2    = api.create('note', { title = 'Source Two', by = 'claude' })
local focus = api.create('note', { title = 'Alpha analysis', by = 'claude', tags = { 'alpha' } })
local beta  = api.create('note', { title = 'Beta study', by = 'claude', tags = { 'beta' } })
local gamma = api.create('note', { title = 'Gamma review', by = 'claude', tags = { 'gamma' } })
local delta = api.create('note', { title = 'Delta note', by = 'claude', tags = { 'delta' } })
assert(s1.ok and s2.ok and focus.ok and beta.ok and gamma.ok and delta.ok, 'setup failed')

assert(api.cite(focus.path, s1.path).ok and api.cite(focus.path, s2.path).ok, 'focus cites')
assert(api.cite(beta.path, s1.path).ok, 'beta cites S1')
assert(api.cite(gamma.path, s1.path).ok and api.cite(gamma.path, s2.path).ok, 'gamma cites S1+S2')

print("== co-citation relates notes that share sources (graph on, default) ==")
local r = api.related_unlinked(focus.path)
check("returns ok", r.ok, vim.inspect(r))
check("Gamma (two shared sources) ranks first", r.candidates[1] and r.candidates[1].title == 'Gamma review',
  titles(r.candidates))
check("Gamma reports co_citations = 2", (function()
  local g = by_title(r.candidates, 'Gamma review'); return g and g.co_citations == 2 and g.score == 4
end)(), vim.inspect(by_title(r.candidates, 'Gamma review')))
check("Beta (one shared source) is present, co_citations = 1", (function()
  local b = by_title(r.candidates, 'Beta study'); return b and b.co_citations == 1 and b.score == 2
end)(), vim.inspect(by_title(r.candidates, 'Beta study')))
check("Gamma outranks Beta", (function()
  local ig, ib
  for i, c in ipairs(r.candidates) do
    if c.title == 'Gamma review' then ig = i end
    if c.title == 'Beta study' then ib = i end
  end
  return ig and ib and ig < ib
end)(), titles(r.candidates))
check("the shared sources themselves are excluded (focus links them)",
  by_title(r.candidates, 'Source One') == nil and by_title(r.candidates, 'Source Two') == nil, titles(r.candidates))
check("the unrelated note (Delta) is absent", by_title(r.candidates, 'Delta note') == nil, titles(r.candidates))

print("== graph=false falls back to index-only: no tag/term overlap, no candidates ==")
local cheap = api.related_unlinked(focus.path, { graph = false })
check("with graph off, Beta/Gamma are gone (only co-citation related them)",
  by_title(cheap.candidates, 'Beta study') == nil and by_title(cheap.candidates, 'Gamma review') == nil,
  titles(cheap.candidates))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
