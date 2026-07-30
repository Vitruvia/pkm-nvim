-- test/test_v1130_p5.lua
-- v1.13.0 Ph5 — the :PKMBrowse and :PKMPanel verb-contexts (command clearup).
--
-- Most of this surface is pickers and panels the headless suite cannot drive,
-- so the test leans on the two deterministic footholds: `:PKMBrowse orphans`
-- on an empty vault reports "no orphaned notes", and the panel toggles are
-- observable through is_bufpanel_open / is_sidebar_open. The rest is checked to
-- exist and to dispatch to the right core through those observables.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p5.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local pkm   = require('pkm')
local ui    = require('pkm.ui')
local views = require('pkm.views')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

print("== the context commands are registered ==")

local cmds = vim.api.nvim_get_commands({})
check("the :PKMBrowse context exists", cmds.PKMBrowse ~= nil)
check("the :PKMPanel context exists", cmds.PKMPanel ~= nil)

print("\n== :PKMBrowse orphans reports an empty result, no picker ==")

local function notify_of(cmd)
  local msg
  local orig = vim.notify
  vim.notify = function(m) msg = m end
  pcall(vim.cmd, cmd)
  vim.notify = orig
  return msg
end

check("`:PKMBrowse orphans` on an empty vault says so",
  (notify_of('PKMBrowse orphans') or ''):find('no orphaned notes', 1, true) ~= nil)

print("\n== :PKMPanel buffers toggles the buffer panel ==")

check("the buffer panel starts closed", ui.is_bufpanel_open() == false)
vim.cmd('PKMPanel buffers')
check("`:PKMPanel buffers` opens it", ui.is_bufpanel_open() == true)
vim.cmd('PKMPanel buffers')
check("`:PKMPanel buffers` again toggles it back", ui.is_bufpanel_open() == false)

print("\n== :PKMPanel sidebar opens the view sidebar ==")

check("the sidebar starts closed", views.is_sidebar_open() == false)
vim.cmd('PKMPanel sidebar')
check("`:PKMPanel sidebar` opens it", views.is_sidebar_open() == true)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
