-- test/test_v1160_api.lua
-- pkm.api — the programmatic surface, driven end-to-end with no screen.
--
-- The route the plan set as the proof: create (with authorship) → cite → audit
-- → bulk-retag → query → collect → and the deletion guard, every step through
-- `require('pkm.api')` only, asserting the returned data (never a buffer or a
-- picker). The point is exactly that none of it opens UI.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1160_api.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function has(list, value)
  for _, v in ipairs(list or {}) do if v == value then return true end end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local api = require('pkm.api')

print("== create is headless, schema-correct, and stamps authorship ==")

local alpha = api.create('note', { title = 'Alpha', by = 'claude', tags = { 'foo' } })
check("create returns ok", alpha.ok, vim.inspect(alpha))
check("it returns a path", type(alpha.path) == 'string' and alpha.path ~= '')
check("the filename carries the By<Author> marker",
  alpha.filename and alpha.filename:find('ByClaude', 1, true) ~= nil, alpha.filename)
check("the author is recorded", alpha.author == 'Claude', tostring(alpha.author))
check("the seeded tag survives", has(alpha.tags, 'foo'), vim.inspect(alpha.tags))
check("the by-claude authorship tag is added", has(alpha.tags, 'by-claude'),
  vim.inspect(alpha.tags))
check("no buffer was opened (the current buffer is not the new note)",
  vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= alpha.path)

local beta = api.create('note', { title = 'Beta' })
check("a second create succeeds", beta.ok, vim.inspect(beta))
check("a human-created note has no author", beta.author == nil, tostring(beta.author))

print("\n== an invalid type is refused, not prompted ==")
local bad = api.create('nope', { title = 'x' })
check("create('nope') is refused", not bad.ok and bad.error ~= nil, vim.inspect(bad))

print("\n== cite keeps both sides of the graph in step ==")
local cited = api.cite(alpha.path, beta.path)
check("cite returns ok", cited.ok, vim.inspect(cited))
local token = string.format('note[%04d]', beta.number)
local alpha_lines = vim.fn.readfile(alpha.path)
check("the citation token is written into the source", (function()
  for _, l in ipairs(alpha_lines) do if l:find(token, 1, true) then return true end end
  return false
end)(), token)
local recited = api.cite(alpha.path, beta.path)
check("citing again is idempotent (still ok)", recited.ok, vim.inspect(recited))

print("\n== audit is read-only data ==")
local findings = api.audit()
check("audit returns a list", type(findings) == 'table', type(findings))
check("the cited pair raises no symmetry error", (function()
  for _, f in ipairs(findings) do
    if f.severity == 'error' and tostring(f.kind):find('symmetr') then return false end
  end
  return true
end)(), vim.inspect(findings))

print("\n== bulk retag writes to disk and re-indexes ==")
local tagged = api.tag({ alpha.path }, { add = { 'bar' } })
check("tag reports one applied, no errors", tagged.ok and tagged.applied == 1, vim.inspect(tagged))
local entry = api.get(alpha.path)
check("the index reflects the new tag", entry and has(entry.tags, 'bar'),
  entry and vim.inspect(entry.tags))

print("\n== query filters the index ==")
local q = api.query('tag:bar')
check("query parses and returns ok", q.ok, vim.inspect(q))
check("Alpha is among the matches", (function()
  for _, e in ipairs(q.matches or {}) do
    if vim.fn.fnamemodify(e.path, ':p') == alpha.path then return true end
  end
  return false
end)(), vim.inspect(q.matches))

print("\n== collect returns the neighbourhood as paths ==")
local nbr = api.collect({ alpha.path }, { cites_depth = 1 })
check("collect returns a list", type(nbr) == 'table')
check("the neighbourhood includes both notes",
  has(nbr, alpha.path) and has(nbr, beta.path), vim.inspect(nbr))

print("\n== actions are enumerable and JSON-safe ==")
local acts = api.actions()
check("actions returns rows", type(acts) == 'table' and #acts > 0, tostring(#acts))
check("each row is { id, label } with no run closure", (function()
  for _, a in ipairs(acts) do
    if type(a.id) ~= 'string' or type(a.label) ~= 'string' or a.run ~= nil then return false end
  end
  return true
end)(), vim.inspect(acts))

print("\n== vault reads return data ==")
check("vaults() returns a table", type(api.vaults()) == 'table')

print("\n== create can populate the body, and body edits preserve frontmatter ==")
local function body_has(path, text)
  for _, l in ipairs(vim.fn.readfile(path)) do if l == text then return true end end
  return false
end
local function fm_title(path)
  local fm = require('pkm.yaml').parse_frontmatter(vim.fn.readfile(path))
  return fm and fm.title
end

local gamma = api.create('note', { title = 'Gamma', by = 'claude',
  body = 'first body line\nsecond body line' })
check("create with a body succeeds", gamma.ok, vim.inspect(gamma))
check("the body lines are written into the file",
  body_has(gamma.path, 'first body line') and body_has(gamma.path, 'second body line'),
  vim.inspect(vim.fn.readfile(gamma.path)))
check("the frontmatter is intact", fm_title(gamma.path) == 'Gamma', tostring(fm_title(gamma.path)))

check("set_body replaces the body", api.set_body(gamma.path, 'replacement body').ok)
check("the old body is gone and the new is present",
  body_has(gamma.path, 'replacement body') and not body_has(gamma.path, 'first body line'),
  vim.inspect(vim.fn.readfile(gamma.path)))
check("set_body preserved the frontmatter", fm_title(gamma.path) == 'Gamma')

check("append_body adds after the body", api.append_body(gamma.path, 'appended tail').ok)
check("append keeps the prior body and adds the new",
  body_has(gamma.path, 'replacement body') and body_has(gamma.path, 'appended tail'))

print("\n== a citation token in a created body is reconciled into the graph ==")
local delta = api.create('note', { title = 'Delta', by = 'claude',
  body = string.format('this cites beta [note[%04d]]', beta.number) })
check("create Delta with a body citation succeeds", delta.ok, vim.inspect(delta))
check("Beta gained the backlink to Delta (graph reconciled from the body)", (function()
  local key = string.format('%04d', delta.number)
  for _, l in ipairs(vim.fn.readfile(beta.path)) do if l:find(key, 1, true) then return true end end
  return false
end)(), 'expected ' .. string.format('%04d', delta.number) .. ' in Beta cited_by')

print("\n== the deletion guard protects human notes and trashes agent notes ==")
local del_human = api.delete(beta.path)
check("deleting a human note is refused", not del_human.ok and del_human.error ~= nil,
  vim.inspect(del_human))
check("the refusal names the missing marker",
  del_human.error and del_human.error:find('marker', 1, true) ~= nil, del_human.error)
local del_agent = api.delete(alpha.path)
check("deleting an agent note succeeds and trashes", del_agent.ok and del_agent.trashed,
  vim.inspect(del_agent))
check("it reports the author", del_agent.author == 'Claude', tostring(del_agent.author))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
