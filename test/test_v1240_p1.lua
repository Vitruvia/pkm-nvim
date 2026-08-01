-- test/test_v1240_p1.lua
-- pkm.api relevance ranking — find / find_all order notes best-first instead of
-- in the index's iteration order. Tiers, strongest first: exact title > title
-- prefix > word-boundary hit > substring-in-word > filename; a matching tag
-- boosts; recency breaks ties. Tags lead with the exact match. Verifies the tier
-- order, that a score rides each note and descends, and that find_all ranks too.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1240_p1.lua" -c "qa!"

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
pkm.setup({ root_path = root })

local api = require('pkm.api')

-- Four notes spanning the title tiers for the term "magic", plus tag variety.
api.create('note', { title = 'thaumagical lore', by = 'claude' })            -- substring in a word
api.create('note', { title = 'the magic of steel', by = 'claude', tags = { 'darkmagic' } }) -- word boundary
api.create('note', { title = 'magic system', by = 'claude', tags = { 'magical' } })         -- prefix
api.create('note', { title = 'magic', by = 'claude', tags = { 'magic' } })                  -- exact
-- A decoy that must not appear at all.
api.create('note', { title = 'a note about steel', by = 'claude' })

local function titles(notes)
  local t = {}
  for _, n in ipairs(notes) do t[#t + 1] = n.title end
  return t
end

print("== find ranks notes by relevance tier, best first ==")
local f = api.find('magic')
local got = titles(f.notes)
check("the exact title ranks first", got[1] == 'magic', vim.inspect(got))
check("the prefix title ranks second", got[2] == 'magic system', vim.inspect(got))
check("the word-boundary title ranks third", got[3] == 'the magic of steel', vim.inspect(got))
check("the substring-in-word title ranks last", got[4] == 'thaumagical lore', vim.inspect(got))
check("the unrelated note does not appear", #f.notes == 4, vim.inspect(got))

print("\n== each note carries a score, strictly non-increasing ==")
-- The exact-title note also carries the tag 'magic', so its score is 100 + the
-- exact-tag boost (15) = 115. Assert the floor and that it tops the list.
check("the exact-title note scores at least the exact-title 100", f.notes[1].score >= 100,
  vim.inspect(f.notes[1]))
check("scores never increase down the list", (function()
  for i = 2, #f.notes do
    if f.notes[i].score > f.notes[i - 1].score then return false end
  end
  return true
end)(), vim.inspect(f.notes))
check("the exact-title note outscores the prefix note",
  f.notes[1].score > f.notes[2].score)

print("\n== tags lead with the exact match ==")
check("the exact tag 'magic' is first", f.tags[1] == 'magic', vim.inspect(f.tags))
check("all three magic tags are present", #f.tags == 3, vim.inspect(f.tags))
check("the prefix tag 'magical' precedes the mid-word 'darkmagic'", (function()
  local pos = {}
  for i, t in ipairs(f.tags) do pos[t] = i end
  return pos['magical'] and pos['darkmagic'] and pos['magical'] < pos['darkmagic']
end)(), vim.inspect(f.tags))

print("\n== find_all ranks too (active vault, no registry) ==")
local fa = api.find_all('magic')
check("find_all returns a vault with matches", fa.ok and #fa.vaults == 1, vim.inspect(fa))
local v = fa.vaults[1]
check("its notes are ranked exact-first with a score", (function()
  return v and v.notes[1] and v.notes[1].title == 'magic' and v.notes[1].score >= 100
end)(), vim.inspect(v and v.notes))
check("find_all notes are non-increasing by score", (function()
  for i = 2, #v.notes do
    if v.notes[i].score > v.notes[i - 1].score then return false end
  end
  return true
end)(), vim.inspect(v and v.notes))

print("\n== a tag boost lifts within, never across, the title tiers ==")
-- 'magic' (exact title, 100) still tops 'magic system' (prefix 70 + tag boost).
check("exact title still beats prefix-plus-tag-boost", f.notes[1].title == 'magic')

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
