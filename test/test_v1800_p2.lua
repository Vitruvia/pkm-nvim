-- test/test_v1800_p2.lua
-- v1.81.0 — agent-assisted smoke of the INTERACTIVE reparent picker. edit_view →
-- "Change parent" → reparent_view_prompt, which in v1.81.0 (a) uses the Telescope
-- pick_list UI (vim.ui.select only as the no-Telescope fallback) and (b) delegates
-- to the pure views.reparent under the CONTAINMENT model — a reparent never
-- empties the view; the new parent just rolls it up.
--
-- Driven headlessly by stubbing vim.ui.select (which backs the pick_list fallback
-- in headless, where Telescope is absent) and capturing vim.notify, so the
-- delegation, the containment behaviour, the cycle refusal and the
-- "parent unchanged" branch are verified without a human — leaving only the
-- visual render of the real Telescope picker to the manual route (percurso 0305).
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

local function count(name) return #api.view_members(name) end
local function parent_of(name)
  for _, e in ipairs(views.tree()) do if e.name == name then return e.parent end end
  return nil
end

-- Drive edit_view(name) with scripted answers, capturing notifies. Answers map a
-- prompt substring to the chosen VALUE. The action menu passes plain-string items;
-- the pick_list fallback passes { display, value } items — so we match on the
-- item's value and hand the whole item back, covering both.
local notifies
local function drive(name, answers)
  notifies = {}
  local o_select, o_notify = vim.ui.select, vim.notify
  vim.ui.select = function(items, opts, on_choice)
    local prompt, want = (opts and opts.prompt) or '', nil
    for pat, choice in pairs(answers) do
      if prompt:find(pat, 1, true) then want = choice break end
    end
    if want == nil then on_choice(nil); return end
    for _, it in ipairs(items) do
      local val = (type(it) == 'table') and it.value or it
      if val == want then on_choice(it); return end
    end
    on_choice(nil)
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

-- Fixtures: disjoint tags.
for i = 1, 2 do api.create('note', { title = 'Guia ' .. i, by = 'claude', tags = { 'guia' } }) end
api.create('note', { title = 'Meta one', by = 'claude', tags = { 'meta' } })
api.create('note', { title = 'AFO one',  by = 'claude', tags = { 'afo' } })
assert(api.save_view('Meta', 'tag:meta').ok)         -- excludes guia (old model would empty)
assert(api.save_view('Other', 'tag:afo').ok)
assert(api.save_subproject('Guias', 'Other', 'tag:guia').ok)
check("fixture: Guias starts with its 2 members under Other", count('Guias') == 2)

print("\n== picker reparents Guias under an 'excluding' parent → keeps members, rolls up ==")
drive('Guias', { ['update'] = 'Change parent', ['New parent'] = 'Meta' })
check("parent field moved to Meta via the picker", parent_of('Guias') == 'Meta', parent_of('Guias'))
check("the reparent success notify fired", notified('reparented'), table.concat(notifies, ' | '))
check("NO empty-composition warning is ever emitted (removed in v1.81.0)",
  not notified('0 under parent'), table.concat(notifies, ' | '))
check("Guias keeps its 2 members (never emptied)", count('Guias') == 2)
check("Meta now contains Guias: meta OR guia = 3", count('Meta') == 3, string.format("got %d", count('Meta')))

print("\n== picker refuses a cycle, and reports 'parent unchanged' ==")
assert(api.save_view('P', 'tag:afo').ok)
assert(api.save_subproject('C', 'P', 'tag:afo').ok)
assert(api.save_subproject('G', 'C', 'tag:afo').ok)
drive('C', { ['update'] = 'Change parent', ['New parent'] = 'G' })   -- G is C's descendant
check("cycle refused through the picker", notified('cycle'), table.concat(notifies, ' | '))
check("C's parent is unchanged after the refused cycle", parent_of('C') == 'P', parent_of('C'))
drive('C', { ['update'] = 'Change parent', ['New parent'] = 'P' })   -- already the parent
check("'parent unchanged' reported when re-picking the current parent",
  notified('unchanged'), table.concat(notifies, ' | '))

print("\n== rename goes through vim.ui.input and re-points children ==")
assert(api.save_view('RenParent', 'tag:afo').ok)
assert(api.save_subproject('RenChild', 'RenParent', 'tag:guia').ok)
do
  local o_input, o_notify = vim.ui.input, vim.notify
  notifies = {}
  vim.ui.input = function(_opts, on_confirm) on_confirm('RenParent-x') end
  vim.notify   = function(msg) notifies[#notifies + 1] = tostring(msg) end
  -- Action menu (vim.ui.select, still stubbed off) picks 'Rename'; the rename
  -- itself now uses vim.ui.input, stubbed just above.
  local o_select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    local prompt = (opts and opts.prompt) or ''
    if prompt:find('update', 1, true) then
      for _, it in ipairs(items) do
        local val = (type(it) == 'table') and it.value or it
        if val == 'Rename' then on_choice(it); return end
      end
    end
    on_choice(nil)
  end
  local ok, err = pcall(views.edit_view, 'RenParent')
  vim.ui.select, vim.ui.input, vim.notify = o_select, o_input, o_notify
  if not ok then error(err) end
  check("rename via vim.ui.input succeeded", notified('renamed'), table.concat(notifies, ' | '))
  check("child followed the rename (re-pointed to new parent name)",
    parent_of('RenChild') == 'RenParent-x', tostring(parent_of('RenChild')))
end

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
