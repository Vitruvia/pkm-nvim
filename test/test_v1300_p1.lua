-- test/test_v1300_p1.lua
-- pkm.api.stale — the review queue for §10 (a vault is provisional knowledge). The
-- strong signal is a PROVENANCE GAP: a substantive note with no references (no bib
-- citation and no ## References section) [weight 3], or no date [weight 1]. AGE is a
-- weak secondary signal that only ranks among flagged notes, never flags alone —
-- unless opts.min_age_days is set. Scoped to note/agg with real bodies.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1300_p1.lua" -c "qa!"

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
  for _, x in ipairs(notes or {}) do if x.title == title then return x end end
  return nil
end
local function titles(notes)
  local t = {}
  for _, x in ipairs(notes or {}) do t[#t + 1] = x.title .. '(' .. x.score .. ')' end
  return table.concat(t, ' | ')
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
local consolidated = root .. '/03-Consolidated'
vim.fn.mkdir(consolidated, 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

local body = 'This note makes a substantive claim about the subject at hand, well over forty characters.'

-- A bib note to serve as a real reference, and a well-sourced note that cites it.
local bib  = api.create('bib', { title = 'Stein 2003', by = 'claude' })
local well = api.create('note', { title = 'Well sourced', by = 'claude', body = body })
assert(bib.ok and well.ok, 'setup')
assert(api.cite(well.path, bib.path).ok, 'well cites the bib')

-- A provenance gap: substantive, no bib citation, no References section.
local gap = api.create('note', { title = 'Unsourced claim', by = 'claude', body = body })
-- Provenance via a prose References section (no bib citation) — should NOT be flagged.
local refs = api.create('note', { title = 'Has references section', by = 'claude',
  body = body .. '\n\n## References\n- Stein, N. (2003). On Method.' })
-- Too short to carry a claim — not substantive, must be skipped.
local short = api.create('note', { title = 'Stub', by = 'claude', body = 'tiny' })
assert(gap.ok and refs.ok and short.ok, 'setup2')

-- Raw notes for date control (api.create always stamps today's date).
--  nodate: no frontmatter dates, no references → no_references + no_date.
vim.fn.writefile({
  '---', 'title: "No date at all"', 'tags: []', '---', '', body,
}, consolidated .. '/9001_note_no-date.md')
--  old_sourced: an old date AND a References section → well-sourced but aged.
vim.fn.writefile({
  '---', 'title: "Old but sourced"', 'last_updated_on: "2019-01-01T10:00:00"',
  'tags: []', '---', '', body, '', '## Sources', '- Stein, N. (2003).',
}, consolidated .. '/9002_note_old-sourced.md')

require('pkm.index').rebuild()

print("== default: provenance gaps are flagged, well-sourced notes are not ==")
local r = api.stale()
check("returns ok", r.ok, vim.inspect(r))
check("the unsourced note is flagged for no_references (score 3)", (function()
  local g = by_title(r.notes, 'Unsourced claim')
  return g and g.reasons.no_references and g.score == 3
end)(), vim.inspect(by_title(r.notes, 'Unsourced claim')))
check("the no-date raw note is flagged for both (score 4, ranks above)", (function()
  local nd = by_title(r.notes, 'No date at all')
  return nd and nd.reasons.no_references and nd.reasons.no_date and nd.score == 4
end)(), vim.inspect(by_title(r.notes, 'No date at all')))
check("it ranks above the plain gap (higher score first)", (function()
  local ind, ig
  for i, x in ipairs(r.notes) do
    if x.title == 'No date at all' then ind = i end
    if x.title == 'Unsourced claim' then ig = i end
  end
  return ind and ig and ind < ig
end)(), titles(r.notes))

print("== not flagged ==")
check("the bib-cited note is not flagged", by_title(r.notes, 'Well sourced') == nil, titles(r.notes))
check("the note with a References section is not flagged", by_title(r.notes, 'Has references section') == nil,
  titles(r.notes))
check("the short stub (not substantive) is skipped", by_title(r.notes, 'Stub') == nil, titles(r.notes))
check("the bib note itself is out of scope (sources, not claims)",
  by_title(r.notes, 'Stein 2003') == nil, titles(r.notes))
check("the old-but-sourced note is NOT flagged by age alone",
  by_title(r.notes, 'Old but sourced') == nil, titles(r.notes))

print("== min_age_days brings in aged, well-sourced notes ==")
local aged = api.stale({ min_age_days = 365 })
check("the old-but-sourced note now appears, flagged by age", (function()
  local o = by_title(aged.notes, 'Old but sourced')
  return o and o.reasons.age_days and o.reasons.age_days > 365
    and not o.reasons.no_references
end)(), vim.inspect(by_title(aged.notes, 'Old but sourced')))

print("== guards / knobs ==")
check("limit caps the result", #api.stale({ limit = 1 }).notes == 1)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
