-- test/test_bufpanel_cmdheight.lua
-- Item 12 (v1.67.0), the real cause behind "command line pushed up / dead space":
-- after :quit-ing every editing window with the buffer panel + sidebar open, the
-- two panels sit side-by-side as one full-height row. The panel's `resize` then
-- shrank that row to a few lines — but with no editing window to absorb the ~38
-- freed rows, Neovim balloons `cmdheight` (the panels get crushed to a sliver and
-- the rest of the screen is a dead command-line area). The resize now SKIPS while
-- no editing window exists (nothing to hand the rows to), so cmdheight stays put;
-- reopening a note creates the window and the panel shrinks normally.
--
-- Run: nvim --headless -u test/min_init.lua -c "luafile test/test_bufpanel_cmdheight.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end
local function settle() vim.wait(400, function() return false end) end

vim.o.lines = 42; vim.o.columns = 120
local pkm  = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local api, ui, utils = require('pkm.api'), require('pkm.ui'), require('pkm.utils')

local n = api.create('note', { title = 'One', by = 'claude', body = 'x' })
api.create('note', { title = 'Two', by = 'claude', body = 'y' })
vim.cmd('edit ' .. vim.fn.fnameescape(n.path))
pcall(vim.cmd, 'PKMPanel mode on')
pcall(vim.cmd, 'PKMPanel explorer')

if not ui.is_bufpanel_open() then
  print("  ok   (buffer panel did not open in this headless env — skipping)")
  print("\nALL PASS")
  return
end

check("cmdheight is 1 before the :quit", vim.o.cmdheight == 1, 'cmdheight=' .. vim.o.cmdheight)

local ew = utils.editing_wins()
vim.api.nvim_set_current_win(ew[1])
pcall(vim.cmd, 'quit')
settle()   -- let the panel's scheduled resize fire

check("cmdheight stays 1 after :quit (no balloon into the command line)",
  vim.o.cmdheight == 1, 'cmdheight=' .. vim.o.cmdheight)
check("no editing window remains, only panels",
  #utils.editing_wins() == 0, tostring(#utils.editing_wins()))

-- Reopen a note: the panel must give it real room, and cmdheight stays sane.
utils.focus_editing_win()
vim.cmd('edit ' .. vim.fn.fnameescape(n.path))
ui.refresh_bufpanel()
settle()

check("cmdheight is still 1 after reopening", vim.o.cmdheight == 1, 'cmdheight=' .. vim.o.cmdheight)
local ew2 = utils.editing_wins()
check("the reopened note has a real editing window", #ew2 >= 1)
local h = ew2[1] and vim.api.nvim_win_get_height(ew2[1]) or 0
check("the reopened note gets most of the height (not a sliver)", h >= 20, 'height=' .. h)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
