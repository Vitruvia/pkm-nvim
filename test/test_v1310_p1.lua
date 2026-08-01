-- test/test_v1310_p1.lua
-- pkm.api.merge — the note-merge lifecycle write (v1.31.0). Folds `absorbed` into
-- `survivor`: appends its body, REDIRECTS its citation graph onto the survivor
-- (inbound citers re-pointed; survivor gains the absorbed note's outbound cites via
-- the copied body), unions topical tags, and trashes it. The graph is redirected
-- BEFORE the trash so nothing dangles. Both notes must be assistant-authored.
--
-- Graph:  Survivor → X ;  Absorbed → Y ;  Citer → Absorbed.
-- After merge(Survivor, Absorbed): Survivor → {X, Y}, Citer → Survivor, Absorbed gone.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1310_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function edges(path) return require('pkm.export').read_citation_edges(path) end
local function has(list, id)
  for _, x in ipairs(list or {}) do if x == id then return true end end
  return false
end
local function id_of(n) return string.format('note-%04d', n) end
local function file_has(path, needle)
  if vim.fn.filereadable(path) == 0 then return false end
  for _, l in ipairs(vim.fn.readfile(path)) do if l:find(needle, 1, true) then return true end end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local x = api.create('note', { title = 'Target X', by = 'claude', body = 'x body' })
local y = api.create('note', { title = 'Target Y', by = 'claude', body = 'y body' })
local s = api.create('note', { title = 'Survivor', by = 'claude', body = 'Survivor content.', tags = { 'keep' } })
local a = api.create('note', { title = 'Absorbed', by = 'claude',
  body = 'A distinctive absorbed sentence worth keeping.', tags = { 'extra' } })
local c = api.create('note', { title = 'Citer', by = 'claude', body = 'refers onward.' })
assert(x.ok and y.ok and s.ok and a.ok and c.ok, 'setup')

assert(api.cite(s.path, x.path).ok, 'S → X')
assert(api.cite(a.path, y.path).ok, 'A → Y')
assert(api.cite(c.path, a.path).ok, 'C → A')

print("== merge folds body and graph into the survivor, then trashes the absorbed ==")
local r = api.merge(s.path, a.path)
check("merge returns ok", r.ok, vim.inspect(r))
check("one inbound citer was redirected", r.redirected == 1, vim.inspect(r))
check("the absorbed note is gone from the index", api.get(a.path) == nil)
check("the absorbed note's body was appended to the survivor",
  file_has(s.path, 'A distinctive absorbed sentence'), 'survivor body missing the absorbed content')
check("the absorbed note's tag was unioned into the survivor", (function()
  local e = require('pkm.index').get(s.path)
  local tags = e and e.tags or {}
  local seen = {}
  for _, t in ipairs(tags) do seen[t] = true end
  return seen['keep'] and seen['extra']
end)(), vim.inspect(require('pkm.index').get(s.path)))

print("== the citation graph was redirected, not left dangling ==")
check("the survivor now cites Y (the absorbed note's outbound target)",
  has(edges(s.path).cites, id_of(y.number)), vim.inspect(edges(s.path)))
check("the survivor still cites X", has(edges(s.path).cites, id_of(x.number)))
check("Y is cited_by the survivor, and NOT by the absorbed note", (function()
  local ey = edges(y.path)
  return has(ey.cited_by, id_of(s.number)) and not has(ey.cited_by, id_of(a.number))
end)(), vim.inspect(edges(y.path)))
check("the citer now cites the survivor, and NOT the absorbed note", (function()
  local ec = edges(c.path)
  return has(ec.cites, id_of(s.number)) and not has(ec.cites, id_of(a.number))
end)(), vim.inspect(edges(c.path)))
check("the survivor is cited_by the citer", has(edges(s.path).cited_by, id_of(c.number)))

print("== self-citation from the absorbed note is not carried in ==")
local s2 = api.create('note', { title = 'Keeper', by = 'claude', body = 'keeper body.' })
local a2 = api.create('note', { title = 'Dup two', by = 'claude', body = 'dup two body.' })
assert(api.cite(a2.path, s2.path).ok, 'A2 → S2 (absorbed cites survivor)')
local r2 = api.merge(s2.path, a2.path)
check("merge with a survivor-pointing absorbed note succeeds", r2.ok, vim.inspect(r2))
check("the survivor does not end up citing itself",
  not has(edges(s2.path).cites, id_of(s2.number)), vim.inspect(edges(s2.path)))

print("== guards ==")
local user = api.create('note', { title = 'User note', body = 'human wrote this, no by.' })  -- no by → human
local claude_note = api.create('note', { title = 'Claude note', by = 'claude', body = 'mine.' })
check("refuses to absorb a human-authored note",
  not api.merge(claude_note.path, user.path).ok, 'should refuse absorbing a non-agent note')
check("refuses to merge into a human-authored note",
  not api.merge(user.path, claude_note.path).ok, 'should refuse merging into a non-agent note')
check("refuses to merge a note into itself", not api.merge(s.path, s.path).ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
