-- test/test_v1380_p1.lua
-- markdown.renumber_sequence — the legal *subalínea* family (lowercase roman + '.':
-- i., ii., iii …). The token is validated as a canonical roman numeral, so ordinary
-- words made of roman letters (civil., mil.) are not mistaken for markers and are
-- left untouched. Tried BEFORE the alpha family, so 'i.' is roman i (not the 9th
-- letter); the alpha family keeps '.' for non-roman letters (a., b.).
-- Renumber only — subalínea highlighting is deferred to the highlighting phase
-- (it needs a validity check the matchadd regex cannot do).
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1380_p1.lua" -c "qa!"

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

local md = require('pkm.markdown')

local function set_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end
local function lines() return vim.api.nvim_buf_get_lines(0, 0, -1, false) end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

print("== an out-of-order subalínea list is renumbered i., ii., iii. … ==")
set_buf({ 'iii. primeira', 'i. segunda', 'ii. terceira' })
md.renumber_sequence(1, 3)
check("renumbered to i., ii., iii. preserving bodies", same(lines(), {
  'i. primeira', 'ii. segunda', 'iii. terceira',
}), vim.inspect(lines()))

print("== higher counts (past x) work and stay lowercase ==")
do
  local input = {}
  for _ = 1, 11 do input[#input + 1] = 'i. item' end
  set_buf(input)
  md.renumber_sequence(1, 11)
  local got = lines()
  check("the 9th item is ix.", got[9] == 'ix. item', vim.inspect(got[9]))
  check("the 10th item is x.", got[10] == 'x. item', vim.inspect(got[10]))
  check("the 11th item is xi.", got[11] == 'xi. item', vim.inspect(got[11]))
end

print("== nesting: indented subalíneas restart under each parent ==")
set_buf({
  'i. first parent',
  '    iii. sub one',
  '    iii. sub two',
  'ii. second parent',
  '    v. sub one',
})
md.renumber_sequence(1, 5)
check("parents i, ii and each sub-list restarts at i", same(lines(), {
  'i. first parent',
  '    i. sub one',
  '    ii. sub two',
  'ii. second parent',
  '    i. sub one',
}), vim.inspect(lines()))

print("== a roman-letter WORD (civil.) is validated out, not renumbered ==")
set_buf({ 'iii. first', 'civil. not a marker', 'i. second' })
md.renumber_sequence(1, 3)
check("civil. is left intact; the two real subalíneas renumber i., ii.", same(lines(), {
  'i. first', 'civil. not a marker', 'ii. second',
}), vim.inspect(lines()))

print("== disambiguation: '.' + non-roman letter stays the alpha family ==")
set_buf({ 'b. one', 'a. two' })
md.renumber_sequence(1, 2)
check("'b.'/'a.' (a is not roman) renumber as alíneas a., b.",
  same(lines(), { 'a. one', 'b. two' }), vim.inspect(lines()))

print("== disambiguation: 'i.' is roman subalínea, not the 9th letter ==")
set_buf({ 'ii. one', 'i. two' })
md.renumber_sequence(1, 2)
check("'ii.'/'i.' renumber as roman i., ii. (not lettered)",
  same(lines(), { 'i. one', 'ii. two' }), vim.inspect(lines()))

print("== additive: inciso 'I -' and a digit list still behave ==")
set_buf({ 'II - a', 'I - b' })
md.renumber_sequence(1, 2)
check("inciso still renumbers I -, II -", same(lines(), { 'I - a', 'II - b' }),
  vim.inspect(lines()))
set_buf({ '3. a', '1. b' })
md.renumber_sequence(1, 2)
check("digit list still renumbers 1., 2.", same(lines(), { '1. a', '2. b' }),
  vim.inspect(lines()))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
