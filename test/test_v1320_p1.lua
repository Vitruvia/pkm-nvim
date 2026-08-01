-- test/test_v1320_p1.lua
-- pkm.api.duplicates — the near-duplicate detector (v1.32.0), and its pairing with
-- api.merge. Similarity is a weighted Jaccard blend: body words (0.5), title terms
-- (0.3), tags (0.2). Where unlinked_pairs finds RELATED notes, this finds notes
-- that are nearly the SAME — the candidates to merge.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1320_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function find_pair(prs, t1, t2)
  for _, p in ipairs(prs or {}) do
    if (p.a.title == t1 and p.b.title == t2) or (p.a.title == t2 and p.b.title == t1) then return p end
  end
  return nil
end
local function describe(prs)
  local t = {}
  for _, p in ipairs(prs or {}) do t[#t + 1] = p.a.title .. '~' .. p.b.title .. '(' .. p.similarity .. ')' end
  return table.concat(t, ' | ')
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local fire = 'Fire spells channel intense heat to burn enemies and ignite the battlefield with roaring flame.'
local d1 = api.create('note', { title = 'Fire spells', by = 'claude', tags = { 'magic', 'fire' }, body = fire })
local d2 = api.create('note', { title = 'Fire spells', by = 'claude', tags = { 'magic', 'fire' }, body = fire })  -- near-identical
local diff = api.create('note', { title = 'Ice barriers', by = 'claude', tags = { 'magic', 'ice' },
  body = 'Ice barriers form protective walls of frozen water to block incoming attacks.' })  -- shares magic tag only
local unrel = api.create('note', { title = 'Cooking pasta', by = 'claude', tags = { 'food' },
  body = 'Boil water, salt generously, add pasta, stir occasionally until tender.' })
assert(d1.ok and d2.ok and diff.ok and unrel.ok, 'setup')

print("== duplicates finds near-identical notes, ranked by similarity ==")
local r = api.duplicates()
check("returns ok", r.ok, vim.inspect(r))
check("the two identical 'Fire spells' notes are found", find_pair(r.pairs, 'Fire spells', 'Fire spells') ~= nil,
  describe(r.pairs))
check("their similarity is very high with a high body_sim", (function()
  local p = find_pair(r.pairs, 'Fire spells', 'Fire spells')
  return p and p.similarity >= 0.9 and p.body_sim >= 0.9
end)(), vim.inspect(find_pair(r.pairs, 'Fire spells', 'Fire spells')))
check("the merely-same-tag note (Ice barriers) is NOT a duplicate of Fire spells",
  find_pair(r.pairs, 'Fire spells', 'Ice barriers') == nil, describe(r.pairs))
check("the unrelated note (Cooking pasta) is in no duplicate pair", (function()
  for _, p in ipairs(r.pairs) do
    if p.a.title == 'Cooking pasta' or p.b.title == 'Cooking pasta' then return false end
  end
  return true
end)(), describe(r.pairs))

print("== threshold is tunable ==")
check("a very high threshold keeps only the near-identical pair",
  #api.duplicates({ threshold = 0.95 }).pairs >= 1)
check("a low threshold admits more pairs",
  #api.duplicates({ threshold = 0.05 }).pairs >= #r.pairs)

print("== detect → merge → the duplicate is gone ==")
local dup = find_pair(r.pairs, 'Fire spells', 'Fire spells')
local m = api.merge(dup.a.path, dup.b.path)
check("merging the duplicate pair succeeds", m.ok, vim.inspect(m))
check("after the merge, that duplicate pair is no longer reported", (function()
  local again = api.duplicates()
  -- only one 'Fire spells' remains, so no Fire spells ~ Fire spells pair
  return find_pair(again.pairs, 'Fire spells', 'Fire spells') == nil
end)(), 'the merged-away duplicate should be gone')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
