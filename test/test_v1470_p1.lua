-- test/test_v1470_p1.lua
-- :PKMSyntax [on|off|toggle] — manual highlighting control, plus the lazy facade
-- forwarding pkm-syntax's is_active(). A vault note enables with the full note
-- look; other markdown gets highlight-only.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1470_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })

local syntax = require('pkm.syntax')

print("== the facade forwards is_active() to the real backend ==")
check("is_active is a function through the facade", type(syntax.is_active) == 'function')

print("== :PKMSyntax on/off/toggle on a NON-PKM markdown buffer ==")
local nonpkm = vim.fn.tempname() .. '/proj/README.md'
vim.fn.mkdir(vim.fn.fnamemodify(nonpkm, ':h'), 'p')
vim.fn.writefile({ '# Title', 'note[0042] and **bold**.' }, nonpkm)
vim.cmd('edit ' .. vim.fn.fnameescape(nonpkm))
local buf = vim.api.nvim_get_current_buf()
if vim.bo[buf].filetype ~= 'markdown' then vim.bo[buf].filetype = 'markdown' end

vim.cmd('PKMSyntax off')   -- ensure a known baseline
check("inactive at baseline", syntax.is_active(buf) == false, tostring(syntax.is_active(buf)))

vim.cmd('PKMSyntax on')
check("on → active", syntax.is_active(buf) == true)
check("on → tree-sitter highlighter attached", vim.treesitter.highlighter.active[buf] ~= nil)

vim.cmd('PKMSyntax off')
check("off → inactive", syntax.is_active(buf) == false)

vim.cmd('PKMSyntax toggle')
check("toggle from off → active", syntax.is_active(buf) == true)
vim.cmd('PKMSyntax toggle')
check("toggle from on → inactive", syntax.is_active(buf) == false)

vim.cmd('PKMSyntax')   -- bare = toggle
check("bare :PKMSyntax toggles (→ active)", syntax.is_active(buf) == true)

print("== a vault note enables (full note look path) ==")
local notepath = root .. '/03-Consolidated/0001_note_x.md'
vim.fn.writefile({ '---', 'title: x', '---', '# H', 'body' }, notepath)
vim.cmd('edit ' .. vim.fn.fnameescape(notepath))
local nbuf = vim.api.nvim_get_current_buf()
vim.cmd('PKMSyntax off')
vim.cmd('PKMSyntax on')
check("note → active", syntax.is_active(nbuf) == true)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
