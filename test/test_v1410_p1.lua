-- test/test_v1410_p1.lua
-- markdown.wrap_range — structure-aware autowrap (Option A): a list item's
-- continuation lines are re-indented to marker_indent + 4 (never the marker width);
-- short markers are padded to the 4-space tab stop, long markers overflow the first
-- line; plain paragraphs reflow at their own indent; headers/tables/code/blockquotes
-- are left untouched. textwidth is set to 20 for predictable wrapping.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1410_p1.lua" -c "qa!"

local failures = 0
local function check(name, cond, detail)
  if cond then print("  ok   " .. name)
  else print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or "")); failures = failures + 1 end
end

local pkm = require('pkm')
local root = vim.fn.tempname() .. '/Note-Vault/00 - Test'
vim.fn.mkdir(root .. '/03-Consolidated', 'p')
pkm.setup({ root_path = root })
local md = require('pkm.markdown')

local function wrap(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].textwidth = 20
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  md.wrap_range(1, vim.api.nvim_buf_line_count(buf))
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

print("== short marker padded to the tab stop; continuation at marker_indent+4 ==")
local r = wrap({ 'i. aa bb cc dd ee ff gg' })
check("first line 'i.' padded to col 4; continuation at col 4", same(r, {
  'i.  aa bb cc dd ee',
  '    ff gg',
}), vim.inspect(r))

print("== long marker overflows the first line; continuation still at col 4 ==")
r = wrap({ 'xiii. aa bb cc dd ee ff gg' })
check("'xiii. ' content at col 6, continuation at col 4 (Option A)", same(r, {
  'xiii. aa bb cc dd ee',
  '    ff gg',
}), vim.inspect(r))

print("== a plain paragraph reflows at its own indent (no +4) ==")
r = wrap({ 'aa bb cc dd ee ff gg hh' })
check("plain paragraph wraps at col 0", same(r, {
  'aa bb cc dd ee ff gg',
  'hh',
}), vim.inspect(r))

print("== a tight list renumbers each item separately ==")
r = wrap({ 'i. one', 'ii. two' })
check("'i.' padded 2, 'ii.' padded 1", same(r, { 'i.  one', 'ii. two' }), vim.inspect(r))

print("== headers, tables, and fenced code are left untouched ==")
r = wrap({
  '# A header far longer than twenty columns wide',
  '| a very wide table row kept intact |',
  '```',
  'a code line far longer than twenty columns',
  '```',
  'i. short',
})
check("structural lines unchanged; only the list item wrapped", same(r, {
  '# A header far longer than twenty columns wide',
  '| a very wide table row kept intact |',
  '```',
  'a code line far longer than twenty columns',
  '```',
  'i.  short',
}), vim.inspect(r))

print("== blockquote lines are left untouched (deferred) ==")
r = wrap({ '> a quoted line far longer than twenty columns wide' })
check("blockquote unchanged", same(r, {
  '> a quoted line far longer than twenty columns wide',
}), vim.inspect(r))

print("== validity: 'civil.' is prose (col-0 continuation), 'iv.' is a list item ==")
local civ = wrap({ 'civil. one two three four five six' })
check("civil. wraps as plain (continuation at col 0)",
  civ[2] and civ[2]:match('^%S'), vim.inspect(civ))
local iv = wrap({ 'iv. one two three four five six seven' })
check("iv. wraps as a list (continuation at col 4)",
  iv[2] and iv[2]:match('^    %S'), vim.inspect(iv))

print("== idempotent: wrapping twice equals wrapping once ==")
local once = wrap({ 'i. aa bb cc dd ee ff gg' })
local twice = wrap(once)
check("second wrap is a no-op", same(once, twice), vim.inspect(twice))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
