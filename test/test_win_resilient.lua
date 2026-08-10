-- test/test_win_resilient.lua
-- Item 12 (v1.67.0): closing every editing window with the sidebar + buffer
-- panel open left only winfix* panels, so the buffer bar's <CR> split from a
-- panel could find no room → E36 "Not enough room" (a crash). utils.
-- win_create_resilient retries the split after dropping the fixed sizes, then
-- restores them. The E36 itself is terminal-dimension dependent (not reliably
-- reproducible headless), so here we prove the helper's contract: it creates a
-- window, returns true, and leaves winfix flags as it found them.
--
-- Run: nvim --headless -u test/min_init.lua -c "luafile test/test_win_resilient.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local utils = require('pkm.utils')
local function nwins() return #vim.api.nvim_tabpage_list_wins(0) end

print("== creates a window in a normal layout, returns true ==")
vim.cmd('only'); vim.cmd('enew')
local before = nwins()
local ok = utils.win_create_resilient('noautocmd vsplit')
check("returned true", ok == true)
check("a window was created", nwins() == before + 1, before .. ' -> ' .. nwins())

print("\n== winfix flags are restored on windows that survive ==")
vim.cmd('only'); vim.cmd('enew')
vim.cmd('noautocmd botright split')
local panel = vim.api.nvim_get_current_win()
vim.wo[panel].winfixheight = true
vim.cmd('noautocmd topleft vsplit')
local side = vim.api.nvim_get_current_win()
vim.wo[side].winfixwidth = true
local ok2 = utils.win_create_resilient('noautocmd aboveleft new')
check("created a window with winfix panels present", ok2 == true)
check("panel winfixheight restored", vim.api.nvim_win_is_valid(panel) and vim.wo[panel].winfixheight == true)
check("side winfixwidth restored", vim.api.nvim_win_is_valid(side) and vim.wo[side].winfixwidth == true)

print("\n== a genuinely impossible command still returns false, no throw ==")
local ok3 = utils.win_create_resilient('this_is_not_a_command')
check("returns false rather than erroring", ok3 == false)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
