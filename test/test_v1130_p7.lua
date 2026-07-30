-- test/test_v1130_p7.lua
-- v1.13.0 Ph7 — folding the :PKMView and :PKMVault siblings into verbs
-- (command clearup).
--
-- The vault lifecycle verbs mutate the registry deterministically, so they run
-- headless with `!` to skip the git repository. The view sidebar and rename are
-- observable; the rest of the view surface is prompt/panel-driven and only
-- checked to exist. Each verb is checked to reach the same core as its alias.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p7.lua" -c "qa!"

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
local vault = require('pkm.vault')
local views = require('pkm.views')

local base   = vim.fn.tempname()
local nvroot = base .. '/Note-Vault'
local alpha  = nvroot .. '/00 - Alpha'
vim.fn.mkdir(alpha .. '/03-Consolidated', 'p')
vim.fn.mkdir(nvroot .. '/Unregistered', 'p')
pkm.setup({ root_path = alpha, vaults_path = nvroot })

local function has_vault(name) return vault.get(name) ~= nil end
local function has_view(name)
  for _, v in ipairs(views.list()) do if v == name then return true end end
  return false
end

print("== the vault context is registered ==")

local cmds = vim.api.nvim_get_commands({})
check("the :PKMVault context exists", cmds.PKMVault ~= nil)

print("\n== :PKMVault new / rename / renumber drive the registry ==")

vim.cmd('PKMVault! new Gamma')          -- ! → no git repository
check("`:PKMVault new` registered the vault", has_vault('Gamma'))

vim.cmd('PKMVault rename Gamma Delta')
check("`:PKMVault rename` renamed it", has_vault('Delta') and not has_vault('Gamma'))

vim.cmd('PKMVault renumber Delta 7')
check("`:PKMVault renumber` changed the number",
  vault.get('Delta') and vault.get('Delta').number == 7,
  vault.get('Delta') and vault.get('Delta').number)

print("\n== the view context is registered ==")

check("the :PKMView context exists", cmds.PKMView ~= nil)

print("\n== :PKMView rename still works (regression) ==")

views.save('reading', 'tag:leitura')
vim.cmd('PKMView rename reading perusal')
check("the view was renamed", has_view('perusal') and not has_view('reading'),
  table.concat(views.list(), ', '))

print("\n== :PKMView sidebar opens the sidebar (verb → open_sidebar) ==")

check("the sidebar starts closed", views.is_sidebar_open() == false)
vim.cmd('PKMView sidebar perusal')
check("`:PKMView sidebar` opened it", views.is_sidebar_open() == true)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
