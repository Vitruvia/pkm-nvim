-- test/test_v1120_p7.lua
-- v1.12.0 — the typed form the lifecycle was missing: renaming a view.
--
-- :PKMViewUpdate renames interactively; there was no argument form. views.rename
-- is the core both now share, and :PKMView rename <old> <new> is the typed path,
-- handling spaced names on both sides by resolving the old name as the longest
-- known view among the words.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1120_p7.lua" -c "qa!"

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
local views = require('pkm.views')

local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local function has_view(name)
  for _, v in ipairs(views.list()) do if v == name then return true end end
  return false
end

print("== the core renames, and keeps the filter ==")

views.save('leituras', 'tag:leitura')
local ok = views.rename('leituras', 'reading')
check("rename() succeeds", ok)
check("the old name is gone", not has_view('leituras'))
check("the new name is there", has_view('reading'))
check("and it kept its filter", views.get_tree('reading') ~= nil)

print("== a subproject follows its parent's rename ==")

views.save('projeto ativo', 'tag:projeto')
views.save_subproject('mecânica', 'projeto ativo', 'tag:mecanica')
check("rename() of the parent succeeds", views.rename('projeto ativo', 'projeto novo'))
check("the parent moved", has_view('projeto novo') and not has_view('projeto ativo'))
-- The child's parent pointer must have followed, or the child is orphaned.
local child_tree = views.get_tree('mecânica')
check("the child still resolves under the renamed parent", child_tree ~= nil)

print("== the command form, with spaces on both sides ==")

vim.cmd('PKMView rename projeto novo projeto renomeado')
check("a spaced old and new name both parse",
  has_view('projeto renomeado') and not has_view('projeto novo'),
  table.concat(views.list(), ', '))

print("== refusals ==")

print("  (the errors below are expected)")
local ok_dup, err_dup = views.rename('reading', 'projeto renomeado')
check("renaming onto an existing name is refused", ok_dup == false)
check("and says so", (err_dup or ''):find('already exists', 1, true) ~= nil, err_dup)

local ok_gone, err_gone = views.rename('does-not-exist', 'whatever')
check("renaming a view that is not there is refused", ok_gone == false)
check("with a not-in-views.json message",
  (err_gone or ''):find('views.json', 1, true) ~= nil, err_gone)

check("renaming to the same name is a quiet success", views.rename('reading', 'reading') == true)

-- The command with an unknown old name reports usage, changes nothing.
local before = table.concat(views.list(), ',')
local msg
local orig = vim.notify
vim.notify = function(m) msg = m end
vim.cmd('PKMView rename nope brandnew')
vim.notify = orig
check("the command refuses an unknown view", not has_view('brandnew'))
check("and shows usage", type(msg) == 'string' and msg:find('rename', 1, true))
check("the view set is unchanged", table.concat(views.list(), ',') == before)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
