-- test/test_list_continue.lua
-- Item 1: pressing <CR> inside an ordered-list item continues the numbering.
-- markdown.plan_list_continuation is the pure split; markdown.list_newline does
-- the buffer edit + cascade renumber. The insert-mode key itself (and the
-- ordinary-newline fallback fidelity) is smoke-tested; here we lock the logic.
--
-- Run: nvim --headless -u test/min_init.lua -c "luafile test/test_list_continue.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end
local function eq(a, b) return a == b end

local md = require('pkm.markdown')

print("== plan_list_continuation (pure) ==")
local p = md.plan_list_continuation('2. texto texto', 8)   -- cursor after "2. texto"
check("split keeps before", p and p.before == '2. texto', p and p.before)
check("split makes next item", p and p.newline == '3. texto', p and p.newline)
check("cursor lands after marker", p and p.cursor_col == 3, p and p.cursor_col)

p = md.plan_list_continuation('1. texto', 8)               -- at end → empty next item
check("end-of-item → empty next", p and p.newline == '2. ' and p.before == '1. texto', p and p.newline)

p = md.plan_list_continuation('  3) item', 9)              -- indent + ) separator
check("indent and ) separator preserved", p and p.newline == '  4) ' and p.cursor_col == 5,
  p and (p.newline .. '/' .. tostring(p.cursor_col)))

p = md.plan_list_continuation('10. x', 5)                  -- two-digit ordinal
check("two-digit ordinal increments", p and p.newline == '11. ', p and p.newline)

check("plain text is not a list", md.plan_list_continuation('plain text', 4) == nil)
check("heading is not a list", md.plan_list_continuation('## heading', 3) == nil)
check("bullet is not an ordered list", md.plan_list_continuation('- bullet', 2) == nil)

print("\n== list_newline: buffer edit + cascade renumber ==")
-- Split "2. bcd" after "2. b" (col 4, a valid normal-mode column); the tail "cd"
-- becomes the next item and the following "3. e" cascades to 4.
vim.cmd('enew')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '1. a', '2. bcd', '3. e' })
vim.api.nvim_win_set_cursor(0, { 2, 4 })
md.list_newline()
local out = vim.api.nvim_buf_get_lines(0, 0, -1, false)
check("a new item is inserted and the following item cascades",
  eq(table.concat(out, '|'), '1. a|2. b|3. cd|4. e'), table.concat(out, '|'))
check("cursor is on the new item after its marker",
  vim.api.nvim_win_get_cursor(0)[1] == 3 and vim.api.nvim_win_get_cursor(0)[2] == 3,
  vim.inspect(vim.api.nvim_win_get_cursor(0)))

print("\n== list_newline: split mid-text ==")
vim.cmd('enew')
vim.api.nvim_buf_set_lines(0, 0, -1, false, { '1. texto', '2. texto texto' })
vim.api.nvim_win_set_cursor(0, { 2, 8 })                   -- after "2. texto"
md.list_newline()
out = vim.api.nvim_buf_get_lines(0, 0, -1, false)
check("mid-text split makes the tail the next item",
  eq(table.concat(out, '|'), '1. texto|2. texto|3. texto'), table.concat(out, '|'))

print("\n== plan_list_continuation: roman / alpha / inciso families ==")
p = md.plan_list_continuation('ii. second', 10)            -- lowercase-roman subalínea
check("roman i. is a list", p ~= nil and p.newline:match('^i+%. ') ~= nil, p and p.newline)
p = md.plan_list_continuation('b) second', 9)              -- alpha
check("alpha b) is a list", p ~= nil and p.newline:match('^%l+%) ') ~= nil, p and p.newline)
p = md.plan_list_continuation('II - second', 11)           -- legal inciso
check("inciso II - is a list", p ~= nil and p.newline:match('^[IVXLCDM]+ %- ') ~= nil, p and p.newline)
check("'civil.' prose is not a list (invalid roman)", md.plan_list_continuation('civil. text', 6) == nil)

print("\n== list_newline: roman / alpha / inciso continue & renumber ==")
local function run(lines, row, col)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { row, col })
  md.list_newline()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')
end
-- Mid-text split after the first word (a valid normal-mode column), mirroring the
-- arabic case above; the tail becomes the next item and the family renumbers.
local out2
out2 = run({ 'i. texto', 'ii. texto texto' }, 2, #'ii. texto')
check("roman list continues (i.→ii.→iii.)", out2 == 'i. texto|ii. texto|iii. texto', out2)
out2 = run({ 'a) texto', 'b) texto texto' }, 2, #'b) texto')
check("alpha list continues (a)→b)→c))", out2 == 'a) texto|b) texto|c) texto', out2)
out2 = run({ 'I - texto', 'II - texto texto' }, 2, #'II - texto')
check("inciso list continues (I -→II -→III -)", out2 == 'I - texto|II - texto|III - texto', out2)

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
