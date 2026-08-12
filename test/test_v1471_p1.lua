-- test/test_v1471_p1.lua
-- highlight_all_markdown must also enable markdown buffers that were ALREADY OPEN
-- when setup ran — FileType does not re-fire for them (a config reload, or a file
-- whose FileType fired before the autocmd registered). Regression for the gap
-- where only newly-:e'd markdown got highlighted.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1471_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

-- Open a NON-PKM markdown buffer BEFORE pkm.setup runs.
local nonpkm = vim.fn.tempname() .. '/proj/README.md'
vim.fn.mkdir(vim.fn.fnamemodify(nonpkm, ':h'), 'p')
vim.fn.writefile({ '# Title', 'note[0042] and text.' }, nonpkm)
vim.cmd('edit ' .. vim.fn.fnameescape(nonpkm))
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = 'markdown'
-- highlight_all_markdown now defaults ON (v1.74.0), and min_init already ran
-- pkm.setup(), so its live FileType autocmd has already enabled this buffer.
-- Disable it to recreate the pre-setup "not yet enabled" state this test exercises:
-- the point is that setup()'s existing-buffer loop (below) re-enables it.
require('pkm.syntax').disable(buf)

print("== before setup: not highlighted ==")
-- pkm.syntax is safe to require before setup; is_active should be false.
check("baseline inactive", require('pkm.syntax').is_active(buf) == false)

print("== setup with highlight_all_markdown enables the already-open buffer ==")
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
require('pkm').setup({
  root_path = root,
  pkm_mode  = { syntax = { enabled = true, highlight_all_markdown = true } },
})

check("pre-open markdown is now active", require('pkm.syntax').is_active(buf) == true)
check("tree-sitter highlighter attached", vim.treesitter.highlighter.active[buf] ~= nil)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
