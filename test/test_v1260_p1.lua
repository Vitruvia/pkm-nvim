-- test/test_v1260_p1.lua
-- pkm.api.context — the one-call RAG assembly (AGENT_PROTOCOL § 11.6: retrieve
-- before working). It composes find (locate the subject, relevance-ranked) with
-- neighborhood (pull in the citation-connected cluster), then merges, de-dupes,
-- and annotates: relation = 'seed' for a search hit, 'linked' for a graph pull-in.
--
-- Graph built:  "magic" (exact hit) → "Steel reference" (a non-matching source)
--               "magic system" (prefix hit), unlinked
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1260_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function by_title(notes, title)
  for _, n in ipairs(notes or {}) do if n.title == title then return n end end
  return nil
end
local function titles(notes)
  local t = {}
  for _, n in ipairs(notes or {}) do t[#t + 1] = n.title end
  return table.concat(t, ' | ')
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local steel = api.create('note', { title = 'Steel reference', by = 'claude' })
local m1    = api.create('note', { title = 'magic', by = 'claude', body = 'on magic' })
local m2    = api.create('note', { title = 'magic system', by = 'claude' })
local decoy = api.create('note', { title = 'unrelated topic', by = 'claude' })
assert(steel.ok and m1.ok and m2.ok and decoy.ok, 'setup failed')
assert(api.cite(m1.path, steel.path).ok, 'magic → steel')

print("== context returns the ranked search seeds ==")
local ctx = api.context('magic', { seeds = 2 })
check("context returns ok with the query echoed", ctx.ok and ctx.query == 'magic', vim.inspect(ctx))
check("the two seeds are the ranked magic hits", (function()
  return #ctx.seeds == 2 and ctx.seeds[1].title == 'magic' and ctx.seeds[2].title == 'magic system'
end)(), vim.inspect(ctx.seeds))
check("seeds carry their relevance score, exact-title first", (function()
  return ctx.seeds[1].score and ctx.seeds[2].score and ctx.seeds[1].score > ctx.seeds[2].score
end)(), vim.inspect(ctx.seeds))

print("== the cluster merges seeds with graph-linked notes, annotated ==")
check("both seeds appear in notes, marked relation='seed'", (function()
  local a, b = by_title(ctx.notes, 'magic'), by_title(ctx.notes, 'magic system')
  return a and b and a.relation == 'seed' and b.relation == 'seed'
end)(), titles(ctx.notes))
check("the cited source is pulled in, marked relation='linked'", (function()
  local s = by_title(ctx.notes, 'Steel reference')
  return s and s.relation == 'linked'
end)(), titles(ctx.notes))
check("the unrelated note is absent (neither hit nor linked)",
  by_title(ctx.notes, 'unrelated topic') == nil, titles(ctx.notes))
check("seeds sort ahead of linked notes", (function()
  -- every 'seed' index is before every 'linked' index
  local last_seed, first_linked = 0, math.huge
  for i, n in ipairs(ctx.notes) do
    if n.relation == 'seed' then last_seed = i
    elseif n.relation == 'linked' then first_linked = math.min(first_linked, i) end
  end
  return last_seed < first_linked
end)(), titles(ctx.notes))

print("== a note reached both as a hit and via the graph stays a seed ==")
-- 'magic' is a seed; make 'magic system' cite 'magic' so it is also a graph
-- neighbour of the other seed — it must remain relation='seed', not downgrade.
assert(api.cite(m2.path, m1.path).ok, 'magic system → magic')
local ctx2 = api.context('magic', { seeds = 2 })
check("the overlapping note keeps relation='seed'", (function()
  local a = by_title(ctx2.notes, 'magic')
  return a and a.relation == 'seed'
end)(), vim.inspect(ctx2.notes))
check("no duplicate rows for the overlapping note", (function()
  local n = 0
  for _, e in ipairs(ctx2.notes) do if e.title == 'magic' then n = n + 1 end end
  return n == 1
end)(), vim.inspect(ctx2.notes))

print("== guards ==")
check("an empty term is refused", not api.context('').ok)
check("a term matching nothing yields empty seeds and notes", (function()
  local r = api.context('zzz-nothing')
  return r.ok and #r.seeds == 0 and #r.notes == 0
end)())

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
