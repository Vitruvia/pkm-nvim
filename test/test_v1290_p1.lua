-- test/test_v1290_p1.lua
-- pkm.api.unlinked_pairs — the vault-wide relatedness sweep (v1.29.0). Every pair
-- of notes related (shared tags / title terms / co-citations) but with no citation
-- edge between them, ranked, so the assistant can review and `cite`. Same signals
-- and exclusions as related_unlinked, applied over all pairs.
--
-- Setup:
--   p1 "Fire magic" {magic,fire}, p2 "Ice magic" {magic,water},
--   p3 "Deep magic" {magic}  (p1 → p3, a DIRECT link),
--   p4 "Steel forging" {metal}  (truly unrelated — cited by no one),
--   src "Reference source"; c1 "Common melody" {alpha} and c2 "Common rhythm"
--     {beta}, both citing src — related by one co-citation plus the "common" term.
--
-- (Co-citation is symmetric: were two sources both cited by c1 AND c2 they would
-- themselves form a valid co-citation pair, which is why the unrelated note here
-- is cited by no one.)
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1290_p1.lua" -c "qa!"

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
  for _, p in ipairs(prs or {}) do t[#t + 1] = p.a.title .. '~' .. p.b.title .. '(' .. p.score .. ')' end
  return table.concat(t, ' | ')
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local p1  = api.create('note', { title = 'Fire magic', by = 'claude', tags = { 'magic', 'fire' } })
local p2  = api.create('note', { title = 'Ice magic', by = 'claude', tags = { 'magic', 'water' } })
local p3  = api.create('note', { title = 'Deep magic', by = 'claude', tags = { 'magic' } })
local p4  = api.create('note', { title = 'Steel forging', by = 'claude', tags = { 'metal' } })
local src = api.create('note', { title = 'Reference source', by = 'claude', tags = { 'ref' } })
local c1  = api.create('note', { title = 'Common melody', by = 'claude', tags = { 'alpha' } })
local c2  = api.create('note', { title = 'Common rhythm', by = 'claude', tags = { 'beta' } })
assert(p1.ok and p2.ok and p3.ok and p4.ok and src.ok and c1.ok and c2.ok, 'setup failed')

assert(api.cite(p1.path, p3.path).ok, 'p1 → p3 (direct)')
assert(api.cite(c1.path, src.path).ok, 'c1 cites src')
assert(api.cite(c2.path, src.path).ok, 'c2 cites src')

print("== the sweep surfaces related, unlinked pairs, ranked ==")
local r = api.unlinked_pairs()
check("returns ok", r.ok, vim.inspect(r))
check("Fire magic ~ Ice magic is present (shared tag + 'magic' term)", (function()
  local p = find_pair(r.pairs, 'Fire magic', 'Ice magic')
  return p and p.score == 3
end)(), describe(r.pairs))
check("Ice magic ~ Deep magic is present (shared tag + term, unlinked)",
  find_pair(r.pairs, 'Ice magic', 'Deep magic') ~= nil, describe(r.pairs))
check("the co-citation pair (Common melody ~ Common rhythm) is present", (function()
  local p = find_pair(r.pairs, 'Common melody', 'Common rhythm')
  return p and p.shared.co_citations == 1 and p.score == 3   -- 2 (one shared source) + 1 ('common' term)
end)(), vim.inspect(find_pair(r.pairs, 'Common melody', 'Common rhythm')))

print("== exclusions ==")
check("the directly-linked pair (Fire magic ~ Deep magic) is excluded",
  find_pair(r.pairs, 'Fire magic', 'Deep magic') == nil, describe(r.pairs))
check("the unrelated note (Steel forging), cited by no one, is in no pair", (function()
  for _, p in ipairs(r.pairs) do
    if p.a.title == 'Steel forging' or p.b.title == 'Steel forging' then return false end
  end
  return true
end)(), describe(r.pairs))
check("scores are non-increasing", (function()
  for i = 2, #r.pairs do if r.pairs[i].score > r.pairs[i - 1].score then return false end end
  return true
end)(), describe(r.pairs))

print("== graph=false drops the pair that only co-citation lifted over threshold ==")
local cheap = api.unlinked_pairs({ graph = false })
check("Common melody ~ Common rhythm gone (term alone scores 1 < min_score)",
  find_pair(cheap.pairs, 'Common melody', 'Common rhythm') == nil, describe(cheap.pairs))
check("the tag/term pairs remain", find_pair(cheap.pairs, 'Fire magic', 'Ice magic') ~= nil, describe(cheap.pairs))

print("== knobs ==")
check("limit caps the result", #api.unlinked_pairs({ limit = 1 }).pairs == 1)
check("min_score=2 admits single-tag pairs (more results)",
  #api.unlinked_pairs({ min_score = 2 }).pairs >= #r.pairs)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
