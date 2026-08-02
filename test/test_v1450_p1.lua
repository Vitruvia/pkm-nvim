-- test/test_v1450_p1.lua
-- markdown.wrap_range — blockquote reflow. A blockquote wraps like a paragraph
-- but at a normalised prefix of one `>` plus three spaces (a 4-column indent)
-- per nesting level, with the prefix repeated on every wrapped line. A bare `>`
-- line is a paragraph break; a quoted list/marker line is re-prefixed but not
-- folded into prose; a non-quote line ends the quote. textwidth = 20.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1450_p1.lua" -c "qa!"

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

print("== level 1: '>' + 3 spaces (4 cols), prefix repeated per wrapped line ==")
local r = wrap({ '> a quoted line far longer than twenty columns wide' })
check("reflowed at col 4, prefix on every line", same(r, {
  '>   a quoted line',
  '>   far longer than',
  '>   twenty columns',
  '>   wide',
}), vim.inspect(r))

print("== level 2: nested quote indents 4 cols per level (>   >   ) ==")
r = wrap({ '> > deep quote that runs well beyond twenty cols wide' })
check("depth-2 prefix is '>   >   ' (8 cols)", same(r, {
  '>   >   deep quote',
  '>   >   that runs',
  '>   >   well beyond',
  '>   >   twenty cols',
  '>   >   wide',
}), vim.inspect(r))

print("== a bare '>' line is a paragraph break, kept between quote paragraphs ==")
r = wrap({
  '> first para long enough to wrap once here',
  '>',
  '> second para also long enough to wrap here',
})
check("blank quote line preserved as '>'", same(r, {
  '>   first para long',
  '>   enough to wrap',
  '>   once here',
  '>',
  '>   second para also',
  '>   long enough to',
  '>   wrap here',
}), vim.inspect(r))

print("== a quoted list/marker line is re-prefixed but not folded into prose ==")
r = wrap({ '> - a bullet inside a quote that is quite long' })
check("quoted bullet re-prefixed, left on one line", same(r, {
  '>   - a bullet inside a quote that is quite long',
}), vim.inspect(r))

print("== a non-quote line ends the quote; the paragraph after it reflows plain ==")
r = wrap({
  '> quoted line that is long enough to wrap here',
  'plain paragraph following without blank line',
})
check("quote flushes, prose reflows at col 0", same(r, {
  '>   quoted line that',
  '>   is long enough',
  '>   to wrap here',
  'plain paragraph',
  'following without',
  'blank line',
}), vim.inspect(r))

print("== idempotent: wrapping an already-wrapped quote is a no-op ==")
local once = wrap({ '> a quoted line far longer than twenty columns wide' })
local twice = wrap(once)
check("second wrap equals the first", same(once, twice), vim.inspect(twice))

print("== a tight prefix without a space ('>text') normalises to '>   text' ==")
r = wrap({ '>tight one two three four five six seven eight' })
check("no-space prefix normalised", r[1] == '>   tight one two' , vim.inspect(r))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
