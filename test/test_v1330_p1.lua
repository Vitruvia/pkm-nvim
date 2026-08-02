-- test/test_v1330_p1.lua
-- markdown.renumber_sequence — the roman-numeral list family (legal *incisos*:
-- I, II, III …). Additive: the digit / emphasis / header families are unchanged;
-- an uppercase-roman ordered list is now recognised and renumbered, converting
-- each position to its roman form, and nesting via the same per-depth counters.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1330_p1.lua" -c "qa!"

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

print("== an out-of-order roman list is renumbered I, II, III … ==")
set_buf({
  'III. primeiro inciso',
  'I. segundo inciso',
  'VII. terceiro inciso',
})
md.renumber_sequence(1, 3)
check("renumbered to I, II, III preserving bodies", same(lines(), {
  'I. primeiro inciso',
  'II. segundo inciso',
  'III. terceiro inciso',
}), vim.inspect(lines()))

print("== the ')' separator and higher counts (past X) work ==")
set_buf({
  'I) a', 'I) b', 'I) c', 'I) d', 'I) e', 'I) f', 'I) g', 'I) h', 'I) i', 'I) j',
})
md.renumber_sequence(1, 10)
check("the tenth item is X)", lines()[10] == 'X) j', vim.inspect(lines()[10]))
check("the ninth item is IX)", lines()[9] == 'IX) i', vim.inspect(lines()[9]))

print("== nesting: indented roman sub-items restart under each parent ==")
set_buf({
  'I. first artigo',
  '    V. sub one',
  '    V. sub two',
  'I. second artigo',
  '    IX. sub one',
})
md.renumber_sequence(1, 5)
check("parents renumber I, II and each sub-list restarts at I", same(lines(), {
  'I. first artigo',
  '    I. sub one',
  '    II. sub two',
  'II. second artigo',
  '    I. sub one',
}), vim.inspect(lines()))

print("== additive: existing families still behave (a digit list is untouched by roman) ==")
set_buf({ '3. a', '1. b', '9. c' })
md.renumber_sequence(1, 3)
check("a plain digit list still renumbers 1,2,3 (not treated as roman)",
  same(lines(), { '1. a', '2. b', '3. c' }), vim.inspect(lines()))

print("== a lowercase-letter list is NOT romanised (handled by the alpha family) ==")
set_buf({ 'b. one', 'a. two' })
md.renumber_sequence(1, 2)
check("lowercase list is not turned into I/II; the alpha family renumbers a, b",
  same(lines(), { 'a. one', 'b. two' }), vim.inspect(lines()))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
