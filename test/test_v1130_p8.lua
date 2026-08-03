-- test/test_v1130_p8.lua
-- v1.13.0 Ph8 — the command-surface audit (command clearup).
--
-- The clearup introduced eleven verb-contexts over the flat commands, keeping
-- every old name as an alias. This file is the standing guard on that surface:
-- the full roster is present (no command lost, none duplicated or stray), and
-- each context's completion offers its verbs — the property that stops a verb
-- from existing without completing.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p8.lua" -c "qa!"

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

-- The whole expected roster after the alias deletion: thirteen verb-contexts and
-- four standalone commands — the three loners, plus :PKMTags, the vault-wide
-- bulk tag command kept when its per-note siblings became :PKMTag verbs. No
-- aliases remain. (:PKMAgentProtocol joined the contexts with the pkm.api work —
-- it installs the pkm-notes agent skill; :PKMSyntax joined with the on/off
-- highlighting toggle.)
local CONTEXTS = {
  'PKMNote', 'PKMTag', 'PKMCite', 'PKMView', 'PKMVault', 'PKMBrowse',
  'PKMPanel', 'PKMHeader', 'PKMList', 'PKMTrash', 'PKMExport', 'PKMAgentProtocol',
  'PKMSyntax',
}
local STANDALONE = { 'PKMCheck', 'PKMStats', 'PKMToggleAutoSync', 'PKMTags' }
local ALIASES = {}

print("== the whole roster is registered ==")

local cmds = vim.api.nvim_get_commands({})
local expected = {}
for _, group in ipairs({ CONTEXTS, STANDALONE, ALIASES }) do
  for _, name in ipairs(group) do
    expected[name] = true
    if cmds[name] == nil then check(name .. ' is registered', false) end
  end
end

print("  ok   all " .. (#CONTEXTS + #STANDALONE + #ALIASES) .. " expected commands checked")

print("\n== the count matches exactly — nothing lost, nothing stray ==")

local pkm_cmds, stray = 0, {}
for name in pairs(cmds) do
  if name:match('^PKM') then
    pkm_cmds = pkm_cmds + 1
    if not expected[name] then stray[#stray + 1] = name end
  end
end
local want = #CONTEXTS + #STANDALONE + #ALIASES
check("there are exactly " .. want .. " :PKM* commands", pkm_cmds == want,
  'found ' .. pkm_cmds)
check("no unexpected :PKM* command exists", #stray == 0, table.concat(stray, ', '))

print("\n== each context's completion offers its verbs ==")

local function completes(cmdline, verbs)
  local got = vim.fn.getcompletion(cmdline, 'cmdline')
  local set = {}
  for _, c in ipairs(got) do set[c] = true end
  for _, v in ipairs(verbs) do
    if not set[v] then return false, v end
  end
  return true
end

local VERB_AUDIT = {
  { 'PKMNote ',   { 'new', 'rename', 'delete', 'settitle' } },
  { 'PKMTag ',    { 'add', 'remove', 'merge' } },
  { 'PKMCite ',   { 'add', 'remove', 'goto', 'insert' } },
  { 'PKMView ',   { 'add', 'new', 'delete', 'sidebar', 'rename' } },
  { 'PKMVault ',  { 'new', 'rename', 'renumber', 'adopt' } },
  { 'PKMBrowse ', { 'recent', 'orphans', 'tags' } },
  { 'PKMPanel ',  { 'buffers', 'nav', 'sidebar', 'autoswitch', 'mode' } },
  { 'PKMHeader ', { 'append', 'next', 'levelup' } },
  { 'PKMList ',   { 'convert', 'renumber' } },
  { 'PKMTrash ',  { 'restore', 'empty' } },
  { 'PKMExport ', { 'simple', 'deep' } },
  { 'PKMAgentProtocol ', { 'install', 'update', 'path' } },
  { 'PKMSyntax ', { 'on', 'off', 'toggle' } },
}

for _, row in ipairs(VERB_AUDIT) do
  local ok, missing = completes(row[1], row[2])
  check((':' .. row[1] .. '<Tab> offers its verbs'), ok,
    ok and nil or ('missing: ' .. tostring(missing)))
end

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
