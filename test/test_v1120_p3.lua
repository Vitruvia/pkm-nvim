-- test/test_v1120_p3.lua
-- v1.12.0 Ph3 — citations in both directions, by reference.
--
-- The route the plan asks for, entirely headless and by command: create two
-- named notes, cite one from the other, check BOTH sides of the graph (cites
-- here, cited_by there), uncite, and check both sides again. The body text is
-- the source of truth, so this also proves the token reaches the body and the
-- engine rebuilds the frontmatter from it.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p3.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm       = require('pkm')
local yaml      = require('pkm.yaml')
local citations = require('pkm.citations')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

--- The set of identifiers in a note's `cites` or `cited_by`, across groups.
---@param path string
---@param field string  'cites' | 'cited_by'
---@return table<string, boolean>
local function ids(path, field)
  local fm  = yaml.parse_frontmatter(vim.fn.readfile(path))
  local out = {}
  for _, group in ipairs({ 'notes', 'bib', 'journal', 'scratch' }) do
    for _, e in ipairs((fm and fm[field] and fm[field][group]) or {}) do
      if e.identifier then out[e.identifier] = true end
    end
  end
  return out
end

print("== two notes, created by command ==")

vim.cmd('PKMNewNote note title=Target')
local target = vim.fn.expand('%:p')
vim.cmd('PKMNewNote note title=Source')
local source = vim.fn.expand('%:p')

check("target is note 0001", target:gsub('\\', '/'):find('/0001_note_Target%.md$') ~= nil, target)
check("source is note 0002", source:gsub('\\', '/'):find('/0002_note_Source%.md$') ~= nil, source)

print("\n== :PKMCite records both sides of the graph ==")

-- Current buffer is the source. Cite the target by its identifier.
vim.cmd('PKMCite note-0001')

check("the token landed in the source body",
  table.concat(vim.fn.readfile(source), '\n'):find('note[0001]', 1, true) ~= nil,
  table.concat(vim.fn.readfile(source), '\n'))
check("source now cites the target", ids(source, 'cites')['note-0001'] == true,
  vim.inspect(ids(source, 'cites')))
check("and the target is cited_by the source", ids(target, 'cited_by')['note-0002'] == true,
  vim.inspect(ids(target, 'cited_by')))

print("\n== citing is idempotent ==")

vim.cmd('PKMCite note-0001')
local fm = yaml.parse_frontmatter(vim.fn.readfile(source))
local n_notes = #(fm.cites.notes or {})
check("a second cite adds no duplicate entry", n_notes == 1, 'n=' .. n_notes)
local body = table.concat(vim.fn.readfile(source), '\n')
local _, occurrences = body:gsub('note%[0001%]', '')
check("and no duplicate token in the body", occurrences == 1, 'occurrences=' .. occurrences)

print("\n== a note cannot cite itself ==")

local ok_self, err_self = citations.cite(source, 'note-0002')
check("self-citation is refused", ok_self == false)
check("and named as such", (err_self or ''):find('itself', 1, true) ~= nil, err_self)

print("\n== :PKMUncite clears both sides ==")

vim.cmd('PKMUncite note-0001')

check("source cites nothing now", next(ids(source, 'cites')) == nil,
  vim.inspect(ids(source, 'cites')))
check("the target is cited_by nothing now", next(ids(target, 'cited_by')) == nil,
  vim.inspect(ids(target, 'cited_by')))
check("and the token is gone from the body",
  table.concat(vim.fn.readfile(source), '\n'):find('note[0001]', 1, true) == nil)

print("\n== the core resolves a path and a token too, not only an id ==")

-- By raw token.
local ok_tok = citations.cite(source, 'note[0001]')
check("cite by token works", ok_tok == true)
check("and it recorded the citation", ids(source, 'cites')['note-0001'] == true)

-- Uncite by absolute path.
local ok_path, removed = citations.uncite(source, target)
check("uncite by path works", ok_path == true and removed == 1, 'removed=' .. tostring(removed))
check("leaving the graph clean", next(ids(source, 'cites')) == nil)

print("\n== a bad reference is refused, not guessed ==")

local ok_bad, err_bad = citations.cite(source, 'note-9999')
check("citing a note that does not exist is refused", ok_bad == false)
check("with a message naming the reference",
  (err_bad or ''):find('9999', 1, true) ~= nil, err_bad)

print("\n== uncite of an uncited target is a quiet no-op ==")

local ok_noop, n_noop = citations.uncite(source, 'note-0001')
check("it succeeds and removes nothing", ok_noop == true and n_noop == 0, 'n=' .. tostring(n_noop))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
