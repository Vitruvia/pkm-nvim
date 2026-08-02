-- test/test_v1340_p1.lua
-- markdown.renumber_sequence — the lettered-list family (legal *alíneas*:
-- a, b, c …). Additive: the digit / emphasis / header / roman families are
-- unchanged; a lowercase-letter ordered list is now recognised and renumbered,
-- converting each position to its letter label (bijective base-26: a … z, aa …),
-- and nesting via the same per-depth counters. Detection and the renumber branch
-- are bounded to one or two letters, so a mid-range prose line is never swept.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1340_p1.lua" -c "qa!"

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

print("== an out-of-order alínea list is renumbered a, b, c … ==")
set_buf({
  'c) primeira alínea',
  'a) segunda alínea',
  'b) terceira alínea',
})
md.renumber_sequence(1, 3)
check("renumbered to a, b, c preserving bodies", same(lines(), {
  'a) primeira alínea',
  'b) segunda alínea',
  'c) terceira alínea',
}), vim.inspect(lines()))

print("== the '.' separator is preserved ==")
set_buf({ 'b. one', 'a. two', 'c. three' })
md.renumber_sequence(1, 3)
check("dot-separated alíneas renumber a., b., c.",
  same(lines(), { 'a. one', 'b. two', 'c. three' }), vim.inspect(lines()))

print("== past z the label wraps to two letters (aa, ab …) ==")
do
  local input = {}
  for _ = 1, 28 do input[#input + 1] = 'a) item' end   -- all 'a)', renumbered by position
  set_buf(input)
  md.renumber_sequence(1, 28)
  local got = lines()
  check("the 26th item is z)", got[26] == 'z) item', vim.inspect(got[26]))
  check("the 27th item is aa)", got[27] == 'aa) item', vim.inspect(got[27]))
  check("the 28th item is ab)", got[28] == 'ab) item', vim.inspect(got[28]))
end

print("== nesting: indented alínea sub-items restart under each parent ==")
set_buf({
  'a. first',
  '    c. sub one',
  '    c. sub two',
  'b. second',
  '    e. sub one',
})
md.renumber_sequence(1, 5)
check("parents renumber a, b and each sub-list restarts at a", same(lines(), {
  'a. first',
  '    a. sub one',
  '    b. sub two',
  'b. second',
  '    a. sub one',
}), vim.inspect(lines()))

print("== additive: a digit list is still handled by the digit family ==")
set_buf({ '3. a', '1. b', '9. c' })
md.renumber_sequence(1, 3)
check("a plain digit list still renumbers 1,2,3 (not treated as alpha)",
  same(lines(), { '1. a', '2. b', '3. c' }), vim.inspect(lines()))

print("== additive: an uppercase-roman inciso list is still its own family ==")
set_buf({ 'III - x', 'I - y', 'II - z' })
md.renumber_sequence(1, 3)
check("uppercase roman incisos renumber I -, II -, III - (not lowercased to alpha)",
  same(lines(), { 'I - x', 'II - y', 'III - z' }), vim.inspect(lines()))

print("== a prose line (>2 leading letters before punctuation) is not swept ==")
set_buf({
  'b) one',
  'a) two',
  'this is prose.',
})
md.renumber_sequence(1, 3)
check("the two alíneas renumber a, b; the prose line is left intact", same(lines(), {
  'a) one',
  'b) two',
  'this is prose.',
}), vim.inspect(lines()))

print("")
if failures == 0 then
  print("ALL PASS")
else
  print(string.format("%d FAILURE(S)", failures))
end
