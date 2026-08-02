-- test/test_v1330_p1.lua
-- markdown.renumber_sequence — the legal *inciso* family (LC 95/1998: uppercase
-- roman + ' - ' separator: I -, II -, III …). Originally introduced in v1.33.0 with
-- '.'/')' separators; **retargeted in v1.37.0** to the canonical legal ' - ' form
-- (the '.'/')' roman form was dropped — see CHANGELOG v1.37.0). Additive: the digit
-- / emphasis / header families are unchanged; nesting uses the same per-depth
-- counters. The ' - ' separator keeps it distinct from a lowercase-roman subalínea.
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

print("== an out-of-order inciso list is renumbered I -, II -, III - … ==")
set_buf({
  'III - primeiro inciso',
  'I - segundo inciso',
  'VII - terceiro inciso',
})
md.renumber_sequence(1, 3)
check("renumbered to I -, II -, III - preserving bodies", same(lines(), {
  'I - primeiro inciso',
  'II - segundo inciso',
  'III - terceiro inciso',
}), vim.inspect(lines()))

print("== higher counts (past X) work ==")
set_buf({
  'I - a', 'I - b', 'I - c', 'I - d', 'I - e',
  'I - f', 'I - g', 'I - h', 'I - i', 'I - j',
})
md.renumber_sequence(1, 10)
check("the tenth item is X -", lines()[10] == 'X - j', vim.inspect(lines()[10]))
check("the ninth item is IX -", lines()[9] == 'IX - i', vim.inspect(lines()[9]))

print("== nesting: indented inciso sub-items restart under each parent ==")
set_buf({
  'I - first artigo',
  '    V - sub one',
  '    V - sub two',
  'I - second artigo',
  '    IX - sub one',
})
md.renumber_sequence(1, 5)
check("parents renumber I, II and each sub-list restarts at I", same(lines(), {
  'I - first artigo',
  '    I - sub one',
  '    II - sub two',
  'II - second artigo',
  '    I - sub one',
}), vim.inspect(lines()))

print("== additive: a plain digit list is untouched by the inciso family ==")
set_buf({ '3. a', '1. b', '9. c' })
md.renumber_sequence(1, 3)
check("a plain digit list still renumbers 1,2,3 (not treated as inciso)",
  same(lines(), { '1. a', '2. b', '3. c' }), vim.inspect(lines()))

print("== the dropped '.'/')' roman form is no longer an inciso ==")
set_buf({ 'III. x', 'I. y' })
md.renumber_sequence(1, 2)
check("'I.'/'III.' (dot form) match no family now, so are left unchanged",
  same(lines(), { 'III. x', 'I. y' }), vim.inspect(lines()))

print("== a lowercase-letter list is still the alpha family (a) b) …) ==")
set_buf({ 'b) one', 'a) two' })
md.renumber_sequence(1, 2)
check("lowercase 'b)'/'a)' renumber as alíneas a), b)",
  same(lines(), { 'a) one', 'b) two' }), vim.inspect(lines()))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
