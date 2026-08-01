-- test/test_v1270_p1.lua
-- pkm.api.related_unlinked — the first revision/evolution aid (AGENT_PROTOCOL
-- §§7, 11.6: a vault is a graph, not a pile). For a focus note, surface notes it
-- shares tags/title-terms with but is NOT linked to, so the assistant can decide
-- whether to `cite` them. Scoring: shared tag = 2, shared title term = 1;
-- already-linked notes are excluded; ranked best-first.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1270_p1.lua" -c "qa!"

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

-- focus shares: tag 'magic' with A/C/D; title terms fire/magic/basics.
local focus = api.create('note', { title = 'Fire magic basics', by = 'claude', tags = { 'magic', 'fire' } })
local a = api.create('note', { title = 'Ice magic basics', by = 'claude', tags = { 'magic', 'ice' } })   -- tag+2 terms
local b = api.create('note', { title = 'Steel forging', by = 'claude', tags = { 'metallurgy' } })          -- unrelated
local c = api.create('note', { title = 'Advanced fire magic', by = 'claude', tags = { 'magic', 'fire' } }) -- strong, but LINKED
local d = api.create('note', { title = 'magic theory', by = 'claude', tags = { 'magic' } })                -- tag+1 term
local e = api.create('note', { title = 'basics of cooking', by = 'claude', tags = { 'cooking' } })         -- 1 term only
assert(focus.ok and a.ok and b.ok and c.ok and d.ok and e.ok, 'setup failed')

-- Link focus → C, so C must be excluded (already related in the graph).
assert(api.cite(focus.path, c.path).ok, 'focus → c')

print("== related_unlinked surfaces related, unlinked notes, ranked ==")
local r = api.related_unlinked(focus.path)
check("returns ok with the focus note echoed", r.ok and r.note.title == 'Fire magic basics', vim.inspect(r))
check("the top candidate is 'Ice magic basics' (tag + two terms)",
  r.candidates[1] and r.candidates[1].title == 'Ice magic basics', titles(r.candidates))
check("'magic theory' is present but ranks below it", (function()
  local ia, id
  for i, cnd in ipairs(r.candidates) do
    if cnd.title == 'Ice magic basics' then ia = i end
    if cnd.title == 'magic theory' then id = i end
  end
  return ia and id and ia < id
end)(), titles(r.candidates))
check("the shared signals are reported", (function()
  local ca = by_title(r.candidates, 'Ice magic basics')
  return ca and #ca.shared_tags == 1 and ca.shared_tags[1] == 'magic' and #ca.shared_terms == 2
end)(), vim.inspect(by_title(r.candidates, 'Ice magic basics')))
check("scores are non-increasing", (function()
  for i = 2, #r.candidates do
    if r.candidates[i].score > r.candidates[i - 1].score then return false end
  end
  return true
end)(), vim.inspect(r.candidates))

print("== exclusions ==")
check("the already-linked note ('Advanced fire magic') is excluded",
  by_title(r.candidates, 'Advanced fire magic') == nil, titles(r.candidates))
check("the unrelated note ('Steel forging') is absent",
  by_title(r.candidates, 'Steel forging') == nil, titles(r.candidates))
check("a single shared term (below min_score) is excluded by default",
  by_title(r.candidates, 'basics of cooking') == nil, titles(r.candidates))

print("== min_score is tunable ==")
local loose = api.related_unlinked(focus.path, { min_score = 1 })
check("min_score=1 now includes the single-term match", by_title(loose.candidates, 'basics of cooking') ~= nil,
  titles(loose.candidates))

print("== limit is honoured ==")
local capped = api.related_unlinked(focus.path, { limit = 1 })
check("limit=1 returns a single candidate (the strongest)",
  #capped.candidates == 1 and capped.candidates[1].title == 'Ice magic basics', titles(capped.candidates))

print("== guards ==")
check("a missing note is refused", not api.related_unlinked('/no/such/note.md').ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
