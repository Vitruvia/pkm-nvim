-- test/test_v1160_skill.lua
-- pkm.skill + :PKMAgentProtocol — installing the pkm-notes agent skill.
--
-- Verifies the installer locates the in-repo skill on the runtimepath and copies
-- a self-contained bundle (SKILL.md + the protocol and API docs) into a
-- destination, and that the command wires to it. All against temp dirs — never
-- the real ~/.claude.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1160_skill.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
    failures = failures + 1
  end
end

local function readable(path) return vim.fn.filereadable(path) == 1 end
local function contains(path, text)
  for _, l in ipairs(vim.fn.readfile(path)) do
    if l:find(text, 1, true) then return true end
  end
  return false
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
require('pkm.commands').register()   -- ensure :PKMAgentProtocol exists

local skill = require('pkm.skill')

print("== source and destination resolve ==")
check("source_dir finds the skill on the runtimepath",
  type(skill.source_dir()) == 'string' and skill.source_dir() ~= '',
  tostring(skill.source_dir()))
local dd = skill.default_dest()
check("default_dest names ~/.claude/skills/pkm-notes", dd:find('pkm%-notes') ~= nil, dd)

print("\n== install copies the self-contained bundle ==")
local dest = (vim.fn.tempname() .. '/skill-dest'):gsub('\\', '/')
local res = skill.install(dest)
check("install returns ok", res.ok, vim.inspect(res))
check("it reports the destination", res.dest == dest, tostring(res.dest))
for _, name in ipairs({ 'SKILL.md', 'AGENT_PROTOCOL.md', 'PKM_API.md' }) do
  check(name .. ' landed', readable(dest .. '/' .. name), dest .. '/' .. name)
end
check("SKILL.md carries the frontmatter name", contains(dest .. '/SKILL.md', 'name: pkm-notes'))
check("SKILL.md points the assistant at pkm.api", contains(dest .. '/SKILL.md', 'pkm.api'))

print("\n== install creates nested destinations ==")
local nested = (vim.fn.tempname() .. '/a/b/c/skill'):gsub('\\', '/')
local rn = skill.install(nested)
check("nested install succeeds", rn.ok and readable(nested .. '/SKILL.md'), vim.inspect(rn))

print("\n== the command installs too ==")
local dest2 = (vim.fn.tempname() .. '/skill-cmd'):gsub('\\', '/')
vim.cmd('PKMAgentProtocol install ' .. dest2)
check("the command wrote SKILL.md", readable(dest2 .. '/SKILL.md'), dest2)
check("PKMAgentProtocol install completes", vim.tbl_contains(
  vim.fn.getcompletion('PKMAgentProtocol ', 'cmdline'), 'install'))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
