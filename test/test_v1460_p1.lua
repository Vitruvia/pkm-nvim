-- test/test_v1460_p1.lua
-- markdown.wrap_range — fenced-code content now wraps WHITESPACE-PRESERVING.
-- Leading indentation and internal whitespace runs survive; a break happens only
-- at a space that fits the width; an over-long token overflows rather than being
-- split; continuation segments repeat the leading indent; lines are never joined.
-- textwidth = 20.
--
-- Run from repo root:
--   nvim --headless -u test/min_init.lua -c "luafile test/test_v1460_p1.lua" -c "qa!"

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

print("== indentation AND internal whitespace survive a wrap ==")
local r = wrap({ '```', '    def foo():  return  x', '```' })
check("indent kept; the double spaces are NOT collapsed", same(r, {
  '```',
  '    def foo():',
  '    return  x',
  '```',
}), vim.inspect(r))

print("== an over-long token overflows, it is never split; indent kept ==")
local long = string.rep('a', 25)
r = wrap({ '```', '  ' .. long .. ' bb', '```' })
check("long token intact and overflowing at its indent", same(r, {
  '```',
  '  ' .. long,
  '  bb',
  '```',
}), vim.inspect(r))

print("== a code line that fits is left byte-for-byte unchanged ==")
r = wrap({ '```', '  x = 1   # a note', '```' })
check("short code line (incl. its spacing) untouched", same(r, {
  '```',
  '  x = 1   # a note',
  '```',
}), vim.inspect(r))

print("== blank code lines are preserved ==")
r = wrap({ '```', 'a b c', '', 'd e f', '```' })
check("blank line between code kept", r[3] == '', vim.inspect(r))

print("== idempotent: wrapping already-wrapped code is a no-op ==")
local once = wrap({ '```', '    def foo():  return  x', '```' })
local twice = wrap(once)
check("second wrap equals the first", same(once, twice), vim.inspect(twice))

print("")
if failures == 0 then print("ALL PASS") else print(string.format("%d FAILURE(S)", failures)) end
