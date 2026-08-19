-- test/test_v1800_p2.lua
-- v1.80.0 — agent-assisted smoke of the INTERACTIVE reparent path. edit_view →
-- "Change parent" → reparent_view_prompt now delegates to the pure views.reparent
-- (v1.80.0). This drives the real prompt headlessly by stubbing vim.ui.select and
-- capturing vim.notify, so the candidate build, the delegation, and the
-- empty-composition warning surfacing through the picker are verified without a
-- human — the part the pure test (p1) cannot see. (The visual rendering of the
-- real vim.ui.select / Telescope float is all that is left to the manual route.)
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1800_p2.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
vim.fn.mkdir(root .. '/02-Journal', 'p')
vim.fn.mkdir(root .. '/01-Scratchpad', 'p')
pkm.setup({ root_path = root })

local api   = require('pkm.api')
local views = require('pkm.views')

local function parent_of(name)
  for _, e in ipairs(views.tree()) do if e.name == name then return e.parent end end
  return nil
end

-- Drive edit_view(name) with scripted prompt answers, capturing every notify.
-- `answers` maps a substring of a prompt to the choice returned for it; the
-- rename input answer is unused here (only the reparent path is driven).
local notifies
local function drive(name, answers)
  notifies = {}
  local o_select, o_notify = vim.ui.select, vim.notify
  vim.ui.select = function(items, opts, on_choice)
    local prompt, ans = (opts and opts.prompt) or '', nil
    for pat, choice in pairs(answers) do
      if prompt:find(pat, 1, true) then ans = choice break end
    end
    on_choice(ans)
  end
  vim.notify = function(msg) notifies[#notifies + 1] = tostring(msg) end
  local ok, err = pcall(views.edit_view, name)
  vim.ui.select, vim.notify = o_select, o_notify
  if not ok then error(err) end
end
local function notified(needle)
  for _, m in ipairs(notifies) do if m:find(needle, 1, true) then return true end end
  return false
end

-- Fixtures: disjoint tags, so an AND across two of them is always empty.
api.create('note', { title = 'Guia one', by = 'claude', tags = { 'guia' } })
api.create('note', { title = 'AFO one',  by = 'claude', tags = { 'afo' } })
assert(api.save_view('Meta',  'tag:meta').ok)                    -- excludes guia
assert(api.save_view('MetaU', 'tag:meta OR tag:guia').ok)        -- superset of guia
assert(api.save_subproject('Guias', 'MetaU', 'tag:guia').ok)     -- starts non-empty
check("fixture: Guias starts with its one member under MetaU", #views.match_all('Guias') == 1)

print("\n== the picker reparents Guias under an excluding parent → warns ==")
drive('Guias', { ['update'] = 'Change parent', ['New parent'] = 'Meta' })
check("parent field moved to Meta via the picker", parent_of('Guias') == 'Meta', parent_of('Guias'))
check("the empty-composition warning surfaced through the picker",
  notified('0 under parent'), table.concat(notifies, ' | '))
check("and the view really is empty now", #views.match_all('Guias') == 0)

print("\n== the picker reparents Guias back to the superset → no warning ==")
drive('Guias', { ['update'] = 'Change parent', ['New parent'] = 'MetaU' })
check("parent field moved back to MetaU", parent_of('Guias') == 'MetaU', parent_of('Guias'))
check("the reparent success notify fired", notified('reparented'), table.concat(notifies, ' | '))
check("no empty-composition warning this time", not notified('0 under parent'))
check("the one member is restored", #views.match_all('Guias') == 1)

print("\n== the picker refuses a cycle, and reports 'parent unchanged' ==")
assert(api.save_view('P', 'tag:afo').ok)
assert(api.save_subproject('C', 'P', 'tag:afo').ok)
assert(api.save_subproject('G', 'C', 'tag:afo').ok)
drive('C', { ['update'] = 'Change parent', ['New parent'] = 'G' })   -- G is C's descendant
check("cycle refused through the picker", notified('cycle'), table.concat(notifies, ' | '))
check("C's parent is unchanged after the refused cycle", parent_of('C') == 'P', parent_of('C'))
drive('C', { ['update'] = 'Change parent', ['New parent'] = 'P' })   -- already the parent
check("'parent unchanged' reported when re-picking the current parent",
  notified('unchanged'), table.concat(notifies, ' | '))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
