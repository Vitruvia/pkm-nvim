-- test/test_v1130_p4.lua
-- v1.13.0 Ph4 — the :PKMCite verb-context (command clearup).
--
-- The graph-mutating verbs (add, remove) and the default-verb form are
-- deterministic, so they run headless with both-sides assertions. The picker
-- and cursor verbs (insert, goto, link, follow, backlinks) are only checked to
-- exist — they need a UI or a cursor the headless suite cannot supply.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p4.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm  = require('pkm')
local yaml = require('pkm.yaml')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

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

print("== the context command is registered ==")

local cmds = vim.api.nvim_get_commands({})
check("the :PKMCite context exists", cmds.PKMCite ~= nil)

print("\n== two notes, created by command ==")

vim.cmd('PKMNote new note title=Target')
local target = vim.fn.expand('%:p')
vim.cmd('PKMNote new note title=Source')
local source = vim.fn.expand('%:p')
check("target is note 0001", target:gsub('\\', '/'):find('/0001_note_Target%.md$') ~= nil, target)
check("source is note 0002", source:gsub('\\', '/'):find('/0002_note_Source%.md$') ~= nil, source)

print("\n== :PKMCite add records both sides of the graph ==")

-- Current buffer is the source.
vim.cmd('PKMCite add note-0001')
check("source now cites the target", ids(source, 'cites')['note-0001'] == true,
  vim.inspect(ids(source, 'cites')))
check("and the target is cited_by the source", ids(target, 'cited_by')['note-0002'] == true,
  vim.inspect(ids(target, 'cited_by')))

print("\n== :PKMCite remove clears both sides ==")

vim.cmd('PKMCite remove note-0001')
check("source cites nothing now", next(ids(source, 'cites')) == nil,
  vim.inspect(ids(source, 'cites')))
check("the target is cited_by nothing now", next(ids(target, 'cited_by')) == nil,
  vim.inspect(ids(target, 'cited_by')))

print("\n== the default verb: a bare target still cites (add) ==")

vim.cmd('PKMCite note-0001')
check("`:PKMCite <target>` with no verb cites via the default add",
  ids(source, 'cites')['note-0001'] == true, vim.inspect(ids(source, 'cites')))

print("\n== :PKMCite update rebuilds without disturbing a correct graph ==")

vim.cmd('PKMCite update')
vim.cmd('silent write')   -- update_references stamps the buffer; persist it
check("the citation survives an update", ids(source, 'cites')['note-0001'] == true,
  vim.inspect(ids(source, 'cites')))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
