-- test/test_v1390_p1.lua
-- markdown.renumber_legal / renumber_range — the one-pass nested Brazilian
-- legal-text renumber. Each line is classified by marker TYPE across five levels
-- (artigo Art. Nº/N · parágrafo § Nº/N · inciso R - · alínea a) · subalínea r.);
-- a per-level counter resets every deeper level when a shallower one appears.
-- renumber_range routes: ≥2 distinct legal levels → nested; otherwise the flat
-- single-family renumber_sequence.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1390_p1.lua" -c "qa!"

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

print("== a full nested legal block renumbers across all five levels ==")
set_buf({
  'Art. 3º Este é o artigo.',
  '§ 5º Primeiro parágrafo.',
  'III - primeiro inciso',
  'c) primeira alínea',
  'iii. primeira subalínea',
  'ii. segunda subalínea',
  'd) segunda alínea',
  'V - segundo inciso',
  '§ 2 Segundo parágrafo.',
  'I - inciso do segundo parágrafo',
  'texto de prosa (civil.) fora da hierarquia',
  'Art. 12 Segundo artigo.',
  'I - inciso do art 2',
})
md.renumber_legal(1, 13)
check("all levels renumbered, deeper levels reset, prose preserved", same(lines(), {
  'Art. 1º Este é o artigo.',
  '§ 1º Primeiro parágrafo.',
  'I - primeiro inciso',
  'a) primeira alínea',
  'i. primeira subalínea',
  'ii. segunda subalínea',
  'b) segunda alínea',
  'II - segundo inciso',
  '§ 2º Segundo parágrafo.',
  'I - inciso do segundo parágrafo',
  'texto de prosa (civil.) fora da hierarquia',
  'Art. 2º Segundo artigo.',
  'I - inciso do art 2',
}), vim.inspect(lines()))

print("== the ordinal rule: 'º' up to the ninth, cardinal from the tenth ==")
do
  local input = {}
  for _ = 1, 11 do input[#input + 1] = 'Art. 1 texto' end
  set_buf(input)
  md.renumber_legal(1, 11)
  local got = lines()
  check("the 9th artigo is Art. 9º",  got[9]  == 'Art. 9º texto',  vim.inspect(got[9]))
  check("the 10th artigo is Art. 10", got[10] == 'Art. 10 texto', vim.inspect(got[10]))
  check("the 11th artigo is Art. 11", got[11] == 'Art. 11 texto', vim.inspect(got[11]))
end

print("== blockquote prefixes are preserved ==")
set_buf({
  '> Art. 2º Citado.',
  '> I - inciso citado',
  '> II - outro',
})
md.renumber_legal(1, 3)
check("the '> ' prefix survives and levels renumber", same(lines(), {
  '> Art. 1º Citado.',
  '> I - inciso citado',
  '> II - outro',
}), vim.inspect(lines()))

print("== renumber_range routes a multi-level block to the nested renumber ==")
set_buf({
  'II - inciso',
  'b) alínea',
  'a) outra alínea',
  'I - outro inciso',
})
md.renumber_range(1, 4)
check("two levels (inciso + alínea) → nested: alíneas reset under each inciso",
  same(lines(), {
    'I - inciso',
    'a) alínea',
    'b) outra alínea',
    'II - outro inciso',
  }), vim.inspect(lines()))

print("== renumber_range routes a single legal level to the flat renumber ==")
set_buf({ 'III - a', 'I - b', 'II - c' })
md.renumber_range(1, 3)
check("one level (incisos only) → single-family renumber, I -, II -, III -",
  same(lines(), { 'I - a', 'II - b', 'III - c' }), vim.inspect(lines()))

print("== renumber_range routes a plain digit list to the flat renumber ==")
set_buf({ '3. a', '1. b', '9. c' })
md.renumber_range(1, 3)
check("no legal markers → single-family digit renumber 1., 2., 3.",
  same(lines(), { '1. a', '2. b', '3. c' }), vim.inspect(lines()))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
