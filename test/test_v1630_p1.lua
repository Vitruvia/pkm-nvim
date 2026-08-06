-- test/test_v1630_p1.lua
-- Command-surface consolidation (v1.63.0) — pop-ups vs persistent panels vs view
-- data. The persistent view sidebar now has ONE door, :PKMPanel sidebar; the old
-- duplicate :PKMView sidebar (and the transient :PKMView list / bare-name open)
-- are gone from :PKMView, which keeps only view-management verbs. The transient
-- view pop-ups moved to :PKMBrowse views. Telescope pickers can't be driven
-- headless, so this asserts the deterministic invariants: which command opens the
-- persistent sidebar, that the removed verbs no longer do, and that :PKMView
-- still manages views.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1630_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local views = require('pkm.views')
-- Seed the view in the sidecar (views.json), not config.projects, so `rename`
-- (which refuses to touch config-defined views) has something it can act on.
views.save('Reading', 'tag:leitura')

print("== the persistent sidebar opens via :PKMPanel sidebar (the one door) ==")
check("sidebar starts closed", views.is_sidebar_open() == false)
vim.cmd('PKMPanel sidebar Reading')
check(":PKMPanel sidebar <view> opened it", views.is_sidebar_open() == true)
vim.cmd('PKMPanel sidebar')   -- toggle closed
check("it toggled closed again", views.is_sidebar_open() == false)

print("\n== :PKMView no longer opens the sidebar (dedup: verb removed) ==")
pcall(vim.cmd, 'PKMView sidebar Reading')
check(":PKMView sidebar does NOT open the sidebar anymore", views.is_sidebar_open() == false)
pcall(vim.cmd, 'PKMView Reading')   -- the old bare-name "open"
check(":PKMView <name> (old open) opens no sidebar", views.is_sidebar_open() == false)
pcall(vim.cmd, 'PKMView list')      -- the old transient list
check(":PKMView list opens no sidebar", views.is_sidebar_open() == false)

print("\n== :PKMView still MANAGES views (data ops retained) ==")
check("the seeded view exists", vim.tbl_contains(views.list(), 'Reading'))
vim.cmd('PKMView rename Reading Perusal')
check(":PKMView rename still works",
  vim.tbl_contains(views.list(), 'Perusal') and not vim.tbl_contains(views.list(), 'Reading'),
  table.concat(views.list(), ', '))

print("\n== the consolidated commands are all registered ==")
for _, c in ipairs({ 'PKMBrowse', 'PKMView', 'PKMPanel' }) do
  check(":" .. c .. " is a command", vim.fn.exists(':' .. c) == 2)
end
-- :PKMBrowse views completion offers `last` + the view names (proves the verb).
local comp = vim.fn.getcompletion('PKMBrowse views ', 'cmdline')
check(":PKMBrowse views completes `last`", vim.tbl_contains(comp, 'last'), vim.inspect(comp))
check(":PKMBrowse views completes a view name", vim.tbl_contains(comp, 'Perusal'), vim.inspect(comp))

-- :PKMView completion no longer offers the relocated verbs.
local vcomp = vim.fn.getcompletion('PKMView ', 'cmdline')
check(":PKMView no longer completes `sidebar`", not vim.tbl_contains(vcomp, 'sidebar'), vim.inspect(vcomp))
check(":PKMView no longer completes `list`", not vim.tbl_contains(vcomp, 'list'), vim.inspect(vcomp))
check(":PKMView still completes `rename`", vim.tbl_contains(vcomp, 'rename'), vim.inspect(vcomp))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
