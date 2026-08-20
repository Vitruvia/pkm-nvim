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

print("\n== plan_list_continuation: unordered families (bullets, tasks) ==")
p = md.plan_list_continuation('- bullet', 8)               -- dash bullet
check("dash bullet continues verbatim", p and p.newline == '- ' and p.ordered == false, p and p.newline)
p = md.plan_list_continuation('  * item', 8)               -- indented star bullet
check("indented star bullet keeps indent+marker", p and p.newline == '  * ' and p.cursor_col == 4,
  p and (p.newline .. '/' .. tostring(p.cursor_col)))
p = md.plan_list_continuation('+ item', 6)                 -- plus bullet
check("plus bullet continues verbatim", p and p.newline == '+ ', p and p.newline)
p = md.plan_list_continuation('- [ ] todo', 10)            -- unchecked task
check("task item continues as fresh unchecked box", p and p.newline == '- [ ] ' and p.ordered == false,
  p and p.newline)
p = md.plan_list_continuation('- [x] done', 10)            -- checked task → unchecked
check("checked task resets to unchecked", p and p.newline == '- [ ] ', p and p.newline)
check("thematic break (---) is not a list", md.plan_list_continuation('---', 3) == nil)

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

print("\n== list_newline: cursor lands after the rewritten marker (all families) ==")
-- Continue a lone item at its true end (insert-mode column == #line): the content
-- advances AND the cursor lands just past the new marker, not at column 0.
local function run_end(line)
  vim.cmd('enew!')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.cmd('startinsert')                        -- insert mode allows col == #line
  vim.api.nvim_win_set_cursor(0, { 1, #line })
  md.list_newline()
  vim.cmd('stopinsert')
  local c = vim.api.nvim_win_get_cursor(0)
  return vim.api.nvim_buf_get_lines(0, 1, 2, false)[1], c[1], c[2]
end
local nl, r, c = run_end('i. foo')
check("lone i. becomes ii. with cursor after it", nl == 'ii. ' and r == 2 and c == 4,
  string.format('%q @%d,%d', nl, r, c))
nl, r, c = run_end('1. foo')
check("lone 1. becomes 2. with cursor after it", nl == '2. ' and c == 3, string.format('%q @%d', nl, c))
nl, r, c = run_end('a) foo')
check("lone a) becomes b) with cursor after it", nl == 'b) ' and c == 3, string.format('%q @%d', nl, c))
nl, r, c = run_end('I - foo')
check("lone I - becomes II - with cursor after it", nl == 'II - ' and c == 5, string.format('%q @%d', nl, c))

print("\n== list_newline: unordered families continue (no renumber) ==")
nl, r, c = run_end('- foo')
check("dash bullet continues, cursor after marker", nl == '- ' and c == 2, string.format('%q @%d', nl, c))
nl, r, c = run_end('- [ ] foo')
check("task item continues as unchecked, cursor after box", nl == '- [ ] ' and c == 6,
  string.format('%q @%d', nl, c))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
