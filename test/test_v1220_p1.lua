-- test/test_v1220_p1.lua
-- pkm.api.cite_source — find-or-create a bib note for a source, then cite it in
-- one call. It closes the § 10 gap where reference-recording defaulted to a
-- freetext prose block: a source becomes a citable, graph-linked bib note, with
-- the citation token placed under a `## References` heading (not dangling at the
-- body's end). Verifies: bib creation with bibtex at the top, authorship marking,
-- placement under the heading (created if absent), graph symmetry, idempotency,
-- reuse of an existing bib by title, and the end-of-body fallback.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1220_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function lines_of(path) return vim.fn.readfile(path) end
local function file_has(path, needle)
  for _, l in ipairs(lines_of(path)) do if l:find(needle, 1, true) then return true end end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api   = require('pkm.api')
local index = require('pkm.index')

print("== cite_source creates the bib note and cites it under References ==")
local citing = api.create('note', { title = 'Stein study', by = 'claude',
  body = 'A claim that leans on Stein.\n\n## Body\nthe argument.' })
check("the citing note was created", citing.ok, vim.inspect(citing))

local bibtex = '@book{stein2003,\n  author = {Stein, N.},\n  title = {On Method},\n  year = {2003}\n}'
local r1 = api.cite_source(citing.path, { title = 'Stein 2003 — On Method', bibtex = bibtex })
check("cite_source returns ok", r1.ok, vim.inspect(r1))
check("a bib note was created", r1.ok and r1.bib and r1.bib.created == true, vim.inspect(r1))
check("the created bib note carries the by-claude filename marker",
  r1.bib and r1.bib.path:find('ByClaude', 1, true) ~= nil, vim.inspect(r1.bib))
check("the note is indexed as a bib note", (function()
  local e = index.get(r1.bib.path)
  return e and e.note_type == 'bib'
end)(), vim.inspect(index.get(r1.bib.path)))
check("the bibtex sits in the bib note body", file_has(r1.bib.path, '@book{stein2003,'))
check("cite_source reports the token was placed", r1.cited == true and r1.token:match('^bib%[%d+%]$') ~= nil,
  vim.inspect(r1))
check("the token was placed under a References heading", (function()
  local ls, h, tok = lines_of(citing.path), nil, nil
  for i, l in ipairs(ls) do
    if l == '## References' then h = i end
    if l:find(r1.token, 1, true) then tok = i end
  end
  return h and tok and h < tok
end)(), vim.inspect(lines_of(citing.path)))
check("the citation graph is symmetric (citing → bib, bib ← citing)", (function()
  -- The graph lives in each note's frontmatter, reconciled by update_references:
  -- the citing note's `cites.bib` names the bib, and the bib's `cited_by.notes`
  -- names the citing note. Assert the cross-identifiers on disk.
  local bib_id  = string.format('bib-%04d', r1.bib.number)
  local note_id = string.format('note-%04d', citing.number)
  return file_has(citing.path, bib_id) and file_has(r1.bib.path, note_id)
end)(), vim.inspect({ citing = lines_of(citing.path), bib = lines_of(r1.bib.path) }))

print("\n== a second call is idempotent — no duplicate bib, no duplicate token ==")
local before_bibs = 0
for _, e in ipairs(index.get_all()) do if e.note_type == 'bib' then before_bibs = before_bibs + 1 end end
local r2 = api.cite_source(citing.path, { title = 'Stein 2003 — On Method', bibtex = bibtex })
check("the second call resolves the SAME bib (not a new one)",
  r2.ok and r2.bib.created == false and r2.bib.path == r1.bib.path, vim.inspect(r2))
check("nothing was newly cited (idempotent)", r2.cited == false, vim.inspect(r2))
local after_bibs = 0
for _, e in ipairs(index.get_all()) do if e.note_type == 'bib' then after_bibs = after_bibs + 1 end end
check("no second bib note was created", after_bibs == before_bibs,
  string.format('before=%d after=%d', before_bibs, after_bibs))
check("the token appears exactly once in the citing note", (function()
  local n = 0
  for _, l in ipairs(lines_of(citing.path)) do
    if l:find(r1.token, 1, true) then n = n + 1 end
  end
  return n == 1
end)(), vim.inspect(lines_of(citing.path)))

print("\n== an existing bib is reused by title from a different note ==")
local other = api.create('note', { title = 'Another note', by = 'claude', body = 'also leans on Stein.' })
local r3 = api.cite_source(other.path, { title = 'stein 2003 — on method' })  -- accent/case-fold, no bibtex
check("cite_source finds the existing bib by title (no creation)",
  r3.ok and r3.bib.created == false and r3.bib.path == r1.bib.path, vim.inspect(r3))
check("the second note now cites the shared bib", r3.cited == true and file_has(other.path, r3.token),
  vim.inspect(lines_of(other.path)))

print("\n== heading = false appends the token at the body's end ==")
local end_note = api.create('note', { title = 'End placement', by = 'claude', body = 'text only.' })
local r4 = api.cite_source(end_note.path, { title = 'Stein 2003 — On Method' }, { heading = false })
check("cite_source with heading=false returns ok and reports no heading",
  r4.ok and r4.heading == nil and r4.cited == true, vim.inspect(r4))
check("the note has no References heading but does carry the token",
  not file_has(end_note.path, '## References') and file_has(end_note.path, r4.token),
  vim.inspect(lines_of(end_note.path)))

print("\n== guards ==")
check("a source with neither title nor ref is refused",
  not api.cite_source(citing.path, {}).ok)
check("a missing citing note is refused",
  not api.cite_source('/no/such/note.md', { title = 'x' }).ok)
check("create=false with no match is refused",
  not api.cite_source(citing.path, { title = 'never-seen source', create = false }).ok)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
