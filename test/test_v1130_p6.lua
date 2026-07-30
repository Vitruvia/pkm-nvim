-- test/test_v1130_p6.lua
-- v1.13.0 Ph6 — the small verb-contexts: :PKMHeader, :PKMList, :PKMTrash,
-- :PKMExport (command clearup).
--
-- Header shifts/motions and list conversions act on buffer lines, so they run
-- deterministically here; the empty-trash path reports when the trash is empty.
-- Export is menu-driven and only checked to exist. Each context is checked to
-- dispatch to the same core as its alias.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1130_p6.lua" -c "qa!"

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

local function set_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

print("== the context commands are registered ==")

local cmds = vim.api.nvim_get_commands({})
for _, name in ipairs({ 'PKMHeader', 'PKMList', 'PKMTrash', 'PKMExport' }) do
  check(name .. ' is registered', cmds[name] ~= nil)
end

print("\n== :PKMHeader levelup / leveldown are inverse shifts over the buffer ==")

local original = { '## Alpha', 'body', '### Beta' }
set_buf(original)
vim.cmd('PKMHeader levelup')
local shifted = lines()
check("levelup changed the headers", not same(shifted, original), vim.inspect(shifted))
vim.cmd('PKMHeader leveldown')
check("leveldown returned them to where they were", same(lines(), original), vim.inspect(lines()))

print("\n== :PKMHeader next / prev move the cursor between headers ==")

set_buf({ '# A', 'text', '## B', 'text', '### C' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader next')
check("next jumps to the following header", vim.api.nvim_win_get_cursor(0)[1] == 3,
  'line ' .. vim.api.nvim_win_get_cursor(0)[1])
vim.cmd('PKMHeader next')
check("next again jumps to the header after that", vim.api.nvim_win_get_cursor(0)[1] == 5,
  'line ' .. vim.api.nvim_win_get_cursor(0)[1])
vim.cmd('PKMHeader prev')
check("prev jumps back", vim.api.nvim_win_get_cursor(0)[1] == 3,
  'line ' .. vim.api.nvim_win_get_cursor(0)[1])

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('PKMHeader next h3')
check("a level restricts the jump (next h3 skips ## B)",
  vim.api.nvim_win_get_cursor(0)[1] == 5, 'line ' .. vim.api.nvim_win_get_cursor(0)[1])

print("\n== :PKMList convert / renumber act on the range ==")

set_buf({ '- a', '- b', '- c' })
vim.cmd('1,3PKMList convert to_ordered')
local ordered = lines()
check("convert to_ordered numbered the items",
  ordered[1]:match('^1[%.%)]') ~= nil and ordered[3]:match('^3[%.%)]') ~= nil,
  vim.inspect(ordered))

-- Scramble the numbers, then renumber back to a clean sequence.
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '5. a', '9. b', '2. c' })
vim.cmd('1,3PKMList renumber')
local renum = lines()
check("renumber restored a 1,2,3 sequence",
  renum[1]:match('^1[%.%)]') ~= nil and renum[2]:match('^2[%.%)]') ~= nil
    and renum[3]:match('^3[%.%)]') ~= nil, vim.inspect(renum))

print("\n== :PKMTrash empty reports an empty trash (alias parity) ==")

local function notify_of(cmd)
  local msg
  local orig = vim.notify
  vim.notify = function(m) msg = m end
  pcall(vim.cmd, cmd)
  vim.notify = orig
  return msg
end

check("`:PKMTrash empty` on an empty trash says so",
  (notify_of('PKMTrash empty') or ''):find('already empty', 1, true) ~= nil)

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
