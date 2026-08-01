-- test/test_v1250_p1.lua
-- pkm.api.read and pkm.api.neighborhood — the RAG/OKF navigation surface
-- (AGENT_PROTOCOL § 11.6: retrieve before working). read returns one note in
-- full — body plus its RESOLVED citation edges (who it cites, who cites it).
-- neighborhood walks the citation graph out to a depth and returns the connected
-- notes as readable entries. Both are single-vault, built on the existing graph.
--
-- Graph built:  Referrer → Hub → { Source One, Source Two }
--   (Hub cites the two sources; Referrer cites Hub.)
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1250_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function titles(list)
  local t = {}
  for _, e in ipairs(list or {}) do t[#t + 1] = e.title end
  table.sort(t)
  return table.concat(t, ', ')
end
local function has_title(list, title)
  for _, e in ipairs(list or {}) do if e.title == title then return true end end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local s1 = api.create('note', { title = 'Source One', by = 'claude' })
local s2 = api.create('note', { title = 'Source Two', by = 'claude' })
local hub = api.create('note', { title = 'Hub', by = 'claude', body = 'hub body text here' })
local ref = api.create('note', { title = 'Referrer', by = 'claude' })
assert(s1.ok and s2.ok and hub.ok and ref.ok, 'setup failed')

assert(api.cite(hub.path, s1.path).ok, 'hub→s1')
assert(api.cite(hub.path, s2.path).ok, 'hub→s2')
assert(api.cite(ref.path, hub.path).ok, 'ref→hub')

print("== read returns a note's body and its resolved edges ==")
local r = api.read(hub.path)
check("read returns ok with the note's body", r.ok and r.body:find('hub body text here', 1, true) ~= nil,
  vim.inspect(r))
check("note_type and author are reported", r.note_type == 'note' and r.author == 'Claude', vim.inspect(r))
check("cites are resolved to the two sources", (function()
  return #r.cites == 2 and has_title(r.cites, 'Source One') and has_title(r.cites, 'Source Two')
end)(), titles(r.cites))
check("each resolved edge carries ref/path/title", (function()
  local e = r.cites[1]
  return e and e.ref and e.path and e.title and e.note_type
end)(), vim.inspect(r.cites[1]))
check("cited_by is resolved to the referrer", #r.cited_by == 1 and has_title(r.cited_by, 'Referrer'),
  titles(r.cited_by))

print("\n== read accepts a citation reference, not only a path ==")
local by_ref = api.read(string.format('note-%04d', hub.number))
check("read('note-NNNN') resolves the same note", by_ref.ok and by_ref.path == hub.path, vim.inspect(by_ref))

print("\n== neighborhood walks the graph and excludes the seed ==")
local nb = api.neighborhood(hub.path)   -- default 1 hop each way
check("seed is the hub, reported separately", nb.ok and nb.seed.title == 'Hub', vim.inspect(nb.seed))
check("1-hop neighbourhood is the two sources and the referrer", (function()
  return #nb.notes == 3 and has_title(nb.notes, 'Source One')
    and has_title(nb.notes, 'Source Two') and has_title(nb.notes, 'Referrer')
end)(), titles(nb.notes))
check("the seed is not in its own neighbourhood", not has_title(nb.notes, 'Hub'), titles(nb.notes))

print("\n== depth is honoured: two cites-hops from the referrer reach the sources ==")
local deep = api.neighborhood(ref.path, { cites_depth = 2, cited_by_depth = 0 })
check("cites_depth=2 from Referrer reaches Hub and both sources", (function()
  return #deep.notes == 3 and has_title(deep.notes, 'Hub')
    and has_title(deep.notes, 'Source One') and has_title(deep.notes, 'Source Two')
end)(), titles(deep.notes))
check("cited_by_depth=0 keeps it one-directional (no back-edges pulled in)",
  not has_title(deep.notes, 'Referrer'), titles(deep.notes))

print("\n== guards ==")
check("read of a missing note is refused", not api.read('/no/such/note.md').ok)
check("neighborhood of a missing note is refused", not api.neighborhood('/no/such/note.md').ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
